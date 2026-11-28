#include "config.h"

#include "sorter.h"

#include <ESP32Servo.h>
#include <esp_timer.h>
#include <math.h>

#include "sort_rules.h"

namespace Sorter {
namespace {

constexpr uint8_t kPusherCount = 3;
constexpr int8_t kNoPusher = -1;  // anorganik: tidak didorong, jatuh di ujung sabuk
constexpr uint32_t kTickMs = 5;
constexpr uint8_t kTransitSize = 8;
constexpr uint32_t kCalPrintMs = 250;

// Bit sensor, untuk mengabaikan sensor yang aktif terus (tersangkut/salah setel).
// LDR tidak membuka item karena bisa terpengaruh cahaya ruangan.
constexpr uint8_t kSharp = 1, kInductive = 2, kCapacitive = 4, kSoil = 8, kRain = 16;
constexpr uint8_t kSharpSamples = 5;  // median 5 sampel (25 ms) meredam derau Sharp IR
constexpr int kSharpMinMm = 80, kSharpMaxMm = 900;

const sr_config_t kRules = {
    SOIL_WET_RAW,
    CAPACITIVE_MEANS_ORGANIC != 0,
    BOTTLE_MIN_HEIGHT_MM,
    STYROFOAM_BY_LDR != 0,
    PAPER_MAX_HEIGHT_MM,
    PAPER_BY_LDR != 0,
};

// Urutan pendorong = urutan tempat sampah di sepanjang sabuk.
const char *const kPusherNames[kPusherCount] = {"organik", "logam", "recyclable"};
const uint8_t kPusherPins[kPusherCount] = {SERVO_ORGANIK_PIN, SERVO_LOGAM_PIN,
                                           SERVO_RECYCLABLE_PIN};
const uint16_t kPusherDistanceMm[kPusherCount] = {
    PUSHER_ORGANIK_DISTANCE_MM, PUSHER_LOGAM_DISTANCE_MM, PUSHER_RECYCLABLE_DISTANCE_MM};

struct Pusher {
  Servo servo;
  uint8_t phase = 0;  // 0 siaga, 1 maju, 2 mundur
  uint32_t phaseMs = 0;
  float angle = SERVO_HOME_DEG;
  int target = SERVO_HOME_DEG;
  int written = -1;
  bool attached = false;
};
Pusher pushers[kPusherCount];
uint32_t lastStartMs = 0;
bool anyStarted = false;

enum class PushResult { Started, Wait, Busy };

// Item yang sudah diklasifikasi dan sedang berjalan menuju pendorongnya.
struct Transit {
  uint32_t dueMs;
  int8_t pusher;
  sr_category_t category;
  const char *reason;
};
Transit transit[kTransitSize];
volatile uint8_t transitCount = 0;

// Item yang sedang melewati zona sensor.
struct Window {
  bool open = false;
  uint32_t firstMs = 0;
  uint32_t lastMs = 0;
  sr_features_t f;
} win;

struct Reading {
  bool sharpValid = false;
  int sharpMm = 0;
  int sharpMv = 0;
  bool inductive = false;
  bool capacitive = false;
  int soilRaw = 4095;
  bool raindrop = false;
  bool bright = false;
} cur;

uint16_t sharpBuf[kSharpSamples] = {0};
uint8_t sharpIdx = 0;
uint32_t sharpValidMs = 0;
uint8_t ignored = 0;
QueueHandle_t reports = nullptr;

volatile bool runningFlag = false;
volatile bool calFlag = false;
volatile int8_t testRequest = -1;
bool wasRunning = false;
bool wasCal = false;
// Sensor pemilah hanya dibaca saat konveyor berjalan atau mode kalibrasi.
// Bawaan saat alat dinyalakan: mati, sampai ada START dari aplikasi.
bool sensorsOn = false;
uint32_t lastCalPrintMs = 0;

int8_t pusherFor(sr_category_t c) {
  switch (c) {
    case SR_ORGANIK: return 0;
    case SR_LOGAM: return 1;
    case SR_RECYCLABLE: return 2;
    default: return kNoPusher;
  }
}

void sendReport(sr_category_t category, const char *item, bool ok) {
  Report r;
  strlcpy(r.category, sr_category_key(category), sizeof r.category);
  strlcpy(r.item, item, sizeof r.item);
  r.ok = ok;
  if (xQueueSend(reports, &r, 0) != pdTRUE) {
    Serial.println("[SORT] antrean laporan penuh, satu hasil hilang");
  }
}

// ---------------------------------------------------------------------------
// Pendorong (servo crank slider)
// ---------------------------------------------------------------------------

// Gerakkan servo menuju target, dibatasi SERVO_SPEED_DEG_S (0 = langsung).
void moveServo(Pusher &p) {
  if (SERVO_SPEED_DEG_S <= 0) {
    p.angle = p.target;
  } else {
    const float step = SERVO_SPEED_DEG_S * kTickMs / 1000.0f;
    if (p.angle < p.target) {
      p.angle = p.angle + step > p.target ? p.target : p.angle + step;
    } else if (p.angle > p.target) {
      p.angle = p.angle - step < p.target ? p.target : p.angle - step;
    }
  }
  const int deg = (int)lroundf(p.angle);
  if (p.attached && deg != p.written) {
    p.servo.write(deg);
    p.written = deg;
  }
}

void attachServo(uint8_t i) {
  Pusher &p = pushers[i];
  if (p.attached) return;
  p.servo.setPeriodHertz(50);
  p.servo.attach(kPusherPins[i], SERVO_MIN_US, SERVO_MAX_US);
  p.servo.write(SERVO_HOME_DEG);  // servo sudah di posisi awal, tidak ada lonjakan
  p.written = SERVO_HOME_DEG;
  p.attached = true;
}

void detachServo(Pusher &p) {
  if (!SERVO_DETACH_WHEN_IDLE || !p.attached) return;
  p.servo.detach();
  p.attached = false;
}

// Wait: servo lain baru saja mulai bergerak, coba lagi pada tick berikutnya.
PushResult startPush(uint8_t i, uint32_t nowMs) {
  Pusher &p = pushers[i];
  if (p.phase != 0) return PushResult::Busy;
  if (anyStarted && nowMs - lastStartMs < SERVO_START_GAP_MS) return PushResult::Wait;
  attachServo(i);
  p.target = SERVO_PUSH_DEG;
  p.phase = 1;
  p.phaseMs = nowMs;
  lastStartMs = nowMs;
  anyStarted = true;
  return PushResult::Started;
}

void updatePushers(uint32_t nowMs) {
  for (auto &p : pushers) {
    const bool arrived = (int)lroundf(p.angle) == p.target;
    if (p.phase == 1 && arrived && nowMs - p.phaseMs >= SERVO_PUSH_MS) {
      p.target = SERVO_HOME_DEG;
      p.phase = 2;
      p.phaseMs = nowMs;
    } else if (p.phase == 2 && arrived && nowMs - p.phaseMs >= SERVO_RETURN_MS) {
      p.phase = 0;
      detachServo(p);
    }
    moveServo(p);
  }
}

// Pendorong yang sedang bergerak langsung kembali, lalu dilepas seperti biasa.
void homeAllPushers(uint32_t nowMs) {
  for (auto &p : pushers) {
    if (p.phase == 0) continue;
    p.target = SERVO_HOME_DEG;
    p.phase = 2;
    p.phaseMs = nowMs;
  }
}

// ---------------------------------------------------------------------------
// Sensor
// ---------------------------------------------------------------------------
// Tegangan Sharp IR -> jarak (mm). Di luar 80–900 mm dianggap tidak valid
// (terlalu dekat: kurva GP2Y0A21 berbalik; terlalu jauh: tidak ada benda/sensor lepas).
int sharpMmFromMv(int mv) {
  if (mv < 300) return -1;
  const float cm = SHARP_CURVE_A * powf(mv / 1000.0f, -SHARP_CURVE_B);
  return (int)lroundf(cm * 10.0f);
}

uint16_t medianSharp() {
  uint16_t v[kSharpSamples];
  memcpy(v, sharpBuf, sizeof v);
  for (uint8_t a = 1; a < kSharpSamples; a++) {
    const uint16_t x = v[a];
    int8_t b = a - 1;
    while (b >= 0 && v[b] > x) {
      v[b + 1] = v[b];
      b--;
    }
    v[b + 1] = x;
  }
  return v[kSharpSamples / 2];
}

void readSensors(uint32_t nowMs) {
  // PC817 menarik output ke LOW saat sensor proximity mendeteksi benda.
  cur.inductive = digitalRead(INDUCTIVE_PIN) == LOW;
  cur.capacitive = USE_CAPACITIVE && digitalRead(CAPACITIVE_PIN) == LOW;
  cur.soilRaw = analogRead(SOIL_PIN);
  cur.raindrop = USE_RAINDROP && digitalRead(RAINDROP_PIN) == RAINDROP_WET_LEVEL;
  cur.bright = USE_LDR && digitalRead(LDR_PIN) == LDR_BRIGHT_LEVEL;

  sharpBuf[sharpIdx] = (uint16_t)analogReadMilliVolts(SHARP_PIN);
  sharpIdx = (sharpIdx + 1) % kSharpSamples;
  cur.sharpMv = medianSharp();
  cur.sharpMm = sharpMmFromMv(cur.sharpMv);
  cur.sharpValid = cur.sharpMm >= kSharpMinMm && cur.sharpMm <= kSharpMaxMm;
  if (cur.sharpValid) sharpValidMs = nowMs;
}

// Sharp IR melihat benda?
//  - mode samping: sinar setinggi ±45 mm terpotong (hanya benda tinggi).
//  - mode atas: benda lebih tinggi dari SHARP_MIN_HEIGHT_MM.
bool sharpSeesItem() {
  if (!cur.sharpValid) return false;
  if (SHARP_SIDE_MOUNT) {
    return cur.sharpMm < SHARP_SIDE_EMPTY_DISTANCE_MM - SHARP_SIDE_TRIGGER_MM;
  }
  return cur.sharpMm < SHARP_BELT_DISTANCE_MM - SHARP_MIN_HEIGHT_MM;
}

// Tinggi benda dari Sharp IR (mm). Mode samping tidak mengukur tinggi:
// sinar terpotong berarti benda minimal setinggi sensor (BOTTLE_MIN_HEIGHT_MM).
int sharpHeightMm() {
  if (SHARP_SIDE_MOUNT) return sharpSeesItem() ? BOTTLE_MIN_HEIGHT_MM : 0;
  return SHARP_BELT_DISTANCE_MM - cur.sharpMm;
}

uint8_t activeMask() {
  uint8_t m = 0;
  if (sharpSeesItem()) m |= kSharp;
  if (cur.inductive) m |= kInductive;
  if (cur.capacitive) m |= kCapacitive;
  if (cur.soilRaw <= SOIL_WET_RAW) m |= kSoil;
  if (cur.raindrop) m |= kRain;
  return m;
}

// ---------------------------------------------------------------------------
// Item
// ---------------------------------------------------------------------------
void finishItem(uint32_t nowMs) {
  const sr_result_t res = sr_classify(&win.f, &kRules);
  const uint32_t inZoneMs = win.lastMs - win.firstMs;
  Serial.printf(
      "[ITEM] %s (%s) | tinggi=%dmm ldr=%d induktif=%d kapasitif=%d soil=%d hujan=%d | "
      "di zona %lu ms, keputusan %lu ms setelah item lewat\n",
      sr_category_key(res.category), res.reason, win.f.height_mm, win.f.bright,
      win.f.inductive, win.f.capacitive, win.f.soil_min_raw, win.f.raindrop,
      (unsigned long)inZoneMs,
      (unsigned long)(nowMs - win.lastMs));
  if (calFlag) {
    Serial.printf("CSV,%lu,%d,%d,%d,%d,%d,%d,%s,%s\n", (unsigned long)inZoneMs,
                  win.f.height_mm, win.f.bright, win.f.inductive, win.f.capacitive,
                  win.f.soil_min_raw, win.f.raindrop, sr_category_key(res.category), res.reason);
  }
  if (!runningFlag) return;  // kalibrasi dengan konveyor berhenti: tidak didorong

  const int8_t p = pusherFor(res.category);
  const float distanceMm = p == kNoPusher ? BELT_END_DISTANCE_MM : kPusherDistanceMm[p];
  const uint32_t centerMs = win.firstMs + inZoneMs / 2;
  const uint32_t dueMs = centerMs + (uint32_t)(distanceMm * 1000.0f / BELT_SPEED_MM_S);
  const int32_t lateMs = (int32_t)(nowMs - dueMs);
  if (lateMs > PUSH_LATE_TOLERANCE_MS) {
    Serial.printf("[SORT] terlambat %ld ms ke pendorong %s: jauhkan pendorong dari zona "
                  "sensor, perlambat sabuk, atau perkecil ITEM_GAP_MS\n",
                  (long)lateMs, p == kNoPusher ? "ujung sabuk" : kPusherNames[p]);
    sendReport(res.category, res.reason, false);
    return;
  }
  if (transitCount == kTransitSize) {
    Serial.println("[SORT] terlalu banyak item di sabuk, item ini gagal");
    sendReport(res.category, res.reason, false);
    return;
  }
  transit[transitCount] = {dueMs, p, res.category, res.reason};
  transitCount = transitCount + 1;
}

void trackItem(uint32_t nowMs) {
  const uint8_t mask = activeMask();
  ignored &= mask;  // sensor yang sudah normal kembali dipakai lagi
  const uint8_t active = mask & ~ignored;

  if (active) {
    if (!win.open) {
      win.open = true;
      win.firstMs = nowMs;
      win.f = sr_features_t{false, false, -1, false, 0, false};
    }
    win.lastMs = nowMs;
    if (active & kInductive) win.f.inductive = true;
    if (active & kCapacitive) win.f.capacitive = true;
    if (active & kRain) win.f.raindrop = true;
    if (cur.bright) win.f.bright = true;
    if (!(ignored & kSoil) && (win.f.soil_min_raw < 0 || cur.soilRaw < win.f.soil_min_raw)) {
      win.f.soil_min_raw = cur.soilRaw;
    }
    if (active & kSharp) {
      const int height = sharpHeightMm();
      if (height > win.f.height_mm) win.f.height_mm = height;
    }
    if (nowMs - win.firstMs > ITEM_MAX_MS) {
      Serial.printf("[SORT] sensor aktif terus > %d ms:%s%s%s%s%s. Diabaikan sampai normal; "
                    "cek sampah tersangkut atau setelan sensor\n",
                    ITEM_MAX_MS, (active & kSharp) ? " SharpIR" : "",
                    (active & kInductive) ? " induktif" : "",
                    (active & kCapacitive) ? " kapasitif" : "",
                    (active & kSoil) ? " soil" : "", (active & kRain) ? " raindrop" : "");
      ignored |= active;
      win.open = false;
    }
    return;
  }
  if (win.open && nowMs - win.lastMs >= ITEM_GAP_MS) {
    win.open = false;
    finishItem(nowMs);
  }
}

// ---------------------------------------------------------------------------
// Mode satu sensor, satu servo (SORT_MODE_PER_SENSOR 1)
// ---------------------------------------------------------------------------
// Stasiun = sensor yang dipasang tepat sebelum servonya. Indeks sama dengan
// indeks pendorong: 0 organik, 1 logam, 2 recyclable.
const uint16_t kStationDistanceMm[kPusherCount] = {STATION_ORGANIK_SENSOR_TO_PUSHER_MM,
                                                   STATION_LOGAM_SENSOR_TO_PUSHER_MM,
                                                   STATION_RECYCLABLE_SENSOR_TO_PUSHER_MM};
// Urutan fisik di sabuk: logam (1), organik (0), recyclable (2).
const char *const kStationSensor[kPusherCount] = {"soil/kapasitif", "induktif",
                                                  "Sharp IR/LDR"};
const sr_category_t kStationCategory[kPusherCount] = {SR_ORGANIK, SR_LOGAM, SR_RECYCLABLE};

struct Station {
  bool active = false;  // sensor sedang melihat sampah
  bool fired = false;   // servo sudah dijadwalkan untuk sampah ini
  bool stuck = false;   // aktif terus > ITEM_MAX_MS, diabaikan sampai normal
  uint32_t sinceMs = 0;
  uint32_t lastActiveMs = 0;
  int maxHeight = 0;    // khusus stasiun Sharp IR
};
Station stations[kPusherCount];

bool organikWet() { return cur.soilRaw <= SOIL_WET_RAW; }

// Kertas: pantulan laser kuat ke LDR di stasiun recyclable.
bool ldrPaper() { return USE_LDR && STATION_RECYCLABLE_USE_LDR && cur.bright; }

bool stationActive(uint8_t i) {
  switch (i) {
    case 0:
      return organikWet() || (STATION_ORGANIK_USE_RAINDROP && cur.raindrop) ||
             (USE_CAPACITIVE && STATION_ORGANIK_USE_CAPACITIVE && cur.capacitive);
    case 1:
      return cur.inductive;
    default:
      return sharpSeesItem() || ldrPaper();
  }
}

const char *stationReason(uint8_t i) {
  if (i == 1) return "Logam (induktif)";
  if (i == 2) return (ldrPaper() && !sharpSeesItem()) ? "Kertas (LDR)" : "Botol (tinggi)";
  if (organikWet()) return "Organik (soil)";
  if (STATION_ORGANIK_USE_RAINDROP && cur.raindrop) return "Organik (raindrop)";
  return "Organik (kapasitif)";
}

void queueTransit(uint32_t dueMs, int8_t pusher, sr_category_t category, const char *reason) {
  if (transitCount == kTransitSize) {
    Serial.println("[SORT] terlalu banyak item di sabuk, item ini gagal");
    sendReport(category, reason, false);
    return;
  }
  transit[transitCount] = {dueMs, pusher, category, reason};
  transitCount = transitCount + 1;
}

// Sensor stasiun i mendeteksi sampah: jadwalkan servonya.
void fireStation(uint8_t i, uint32_t detectMs, uint32_t nowMs) {
  Station &st = stations[i];
  st.fired = true;
  const char *reason = stationReason(i);
  const uint32_t travelMs = (uint32_t)(kStationDistanceMm[i] * 1000.0f / BELT_SPEED_MM_S);
  Serial.printf("[STASIUN] %s -> servo %s dalam %lu ms (%s)\n", kStationSensor[i],
                kPusherNames[i], (unsigned long)travelMs, reason);
  if (calFlag) {
    Serial.printf("CSV,%s,%lu,%d,%d,%d,%d,%d,%d\n", kPusherNames[i],
                  (unsigned long)(nowMs - st.sinceMs), st.maxHeight, cur.bright, cur.inductive,
                  cur.capacitive, cur.soilRaw, cur.raindrop);
  }
  if (!runningFlag) return;  // kalibrasi dengan konveyor berhenti: tidak didorong
  queueTransit(detectMs + travelMs, (int8_t)i, kStationCategory[i], reason);
}

void trackStations(uint32_t nowMs) {
  for (uint8_t i = 0; i < kPusherCount; i++) {
    Station &st = stations[i];
    if (stationActive(i)) {
      if (!st.active) {
        st.active = true;
        st.fired = false;
        st.sinceMs = nowMs;
        st.maxHeight = 0;
      }
      st.lastActiveMs = nowMs;
      if (st.stuck) continue;
      if (nowMs - st.sinceMs > ITEM_MAX_MS) {
        st.stuck = true;
        Serial.printf("[SORT] sensor %s aktif terus > %d ms. Diabaikan sampai normal; cek "
                      "sampah tersangkut atau setelan sensor\n", kStationSensor[i], ITEM_MAX_MS);
        continue;
      }
      if (st.fired) continue;
      if (i == 2 && !SHARP_SIDE_MOUNT && !ldrPaper()) {
        // Sharp IR dari atas: servo recyclable hanya untuk benda tinggi (botol).
        const int height = sharpHeightMm();
        if (height > st.maxHeight) st.maxHeight = height;
        if (st.maxHeight >= BOTTLE_MIN_HEIGHT_MM) fireStation(i, nowMs, nowMs);
      } else if (nowMs - st.sinceMs >= STATION_MIN_ACTIVE_MS) {
        // Sharp IR dari samping: sinar terpotong sudah berarti benda tinggi.
        if (i == 2) st.maxHeight = BOTTLE_MIN_HEIGHT_MM;
        fireStation(i, st.sinceMs, nowMs);
      }
      continue;
    }
    if (!st.active || nowMs - st.lastActiveMs < ITEM_GAP_MS) continue;
    st.active = false;
    if (st.stuck) {
      st.stuck = false;
      Serial.printf("[SORT] sensor %s normal kembali\n", kStationSensor[i]);
      continue;
    }
    // Benda rendah lewat Sharp IR tanpa didorong: anorganik, jatuh di ujung sabuk.
    if (i == 2 && !st.fired && !SHARP_SIDE_MOUNT) {
      Serial.printf("[STASIUN] Sharp IR: benda rendah %d mm -> anorganik (ujung sabuk)\n",
                    st.maxHeight);
      if (calFlag) {
        Serial.printf("CSV,anorganik,%lu,%d,%d,%d,%d,%d,%d\n",
                      (unsigned long)(st.lastActiveMs - st.sinceMs), st.maxHeight, cur.bright,
                      cur.inductive, cur.capacitive, cur.soilRaw, cur.raindrop);
      }
      if (runningFlag) sendReport(SR_ANORGANIK, "Residu (rendah)", true);
    }
  }
}

void resetStations() {
  for (auto &st : stations) st = Station{};
}

// Jalankan pendorong untuk item yang sudah sampai di depannya.
void moveTransit(uint32_t nowMs) {
  uint8_t i = 0;
  while (i < transitCount) {
    const Transit t = transit[i];
    if ((int32_t)(nowMs - t.dueMs) < 0) {
      i++;
      continue;
    }
    bool ok = true;
    if (t.pusher != kNoPusher) {
      const PushResult r = startPush(t.pusher, nowMs);
      if (r == PushResult::Wait && (int32_t)(nowMs - t.dueMs) <= PUSH_LATE_TOLERANCE_MS) {
        i++;  // menunggu giliran servo lain, masih dalam toleransi
        continue;
      }
      ok = r == PushResult::Started;
      if (!ok) Serial.printf("[SORT] pendorong %s %s, item terlewat\n", kPusherNames[t.pusher],
                             r == PushResult::Busy ? "masih bergerak" : "tidak dapat giliran");
    }
    sendReport(t.category, t.reason, ok);
    for (uint8_t j = i + 1; j < transitCount; j++) transit[j - 1] = transit[j];
    transitCount = transitCount - 1;
  }
}

void handleRunningChange() {
  const bool running = runningFlag;
  if (running == wasRunning) return;
  wasRunning = running;
  if (running) {
    Serial.println("[SORT] konveyor berjalan, pemilahan aktif");
    return;
  }
  if (transitCount > 0) {
    Serial.printf("[SORT] konveyor berhenti: %u item di sabuk dilaporkan gagal\n",
                  transitCount);
  }
  for (uint8_t i = 0; i < transitCount; i++) {
    sendReport(transit[i].category, transit[i].reason, false);
  }
  transitCount = 0;
  win.open = false;
  resetStations();
  homeAllPushers(millis());
}

void handleTestRequest(uint32_t nowMs) {
  const int8_t req = testRequest;
  if (req < 0) return;
  testRequest = -1;
  const PushResult r = startPush(req, nowMs);
  if (r == PushResult::Wait) {
    testRequest = req;  // tunggu giliran servo lain
    return;
  }
  Serial.printf("[TES] pendorong %s %s\n", kPusherNames[req],
                r == PushResult::Started ? "bergerak" : "masih bergerak, coba lagi");
}

void printCalibration(uint32_t nowMs) {
  const bool cal = calFlag;
  if (cal != wasCal) {
    wasCal = cal;
    Serial.printf("[CAL] mode kalibrasi %s\n", cal ? "AKTIF" : "MATI");
    if (cal) {
      if (SORT_MODE_PER_SENSOR) {
        Serial.println("CSV,servo,lama_ms,tinggi_mm,ldr_terang,induktif,kapasitif,soil_raw,raindrop");
      } else {
        Serial.println("CSV,lama_ms,tinggi_mm,ldr_terang,induktif,kapasitif,soil_raw,raindrop,kategori,alasan");
      }
    }
  }
  if (!cal || nowMs - lastCalPrintMs < kCalPrintMs) return;
  lastCalPrintMs = nowMs;
  char sharpText[56];
  if (cur.sharpValid && SHARP_SIDE_MOUNT) {
    snprintf(sharpText, sizeof sharpText, "sharp=%dmm (%s) %dmV", cur.sharpMm,
             sharpSeesItem() ? "TERPOTONG" : "kosong", cur.sharpMv);
  } else if (cur.sharpValid) {
    snprintf(sharpText, sizeof sharpText, "sharp=%dmm (tinggi %dmm) %dmV", cur.sharpMm,
             SHARP_BELT_DISTANCE_MM - cur.sharpMm, cur.sharpMv);
  } else {
    snprintf(sharpText, sizeof sharpText, "sharp=-- (%dmV, di luar 80-900 mm)", cur.sharpMv);
  }
  Serial.printf("[CAL] %s | ldr=%d induktif=%d kapasitif=%d soil=%d raindrop=%d%s\n", sharpText,
                cur.bright, cur.inductive, cur.capacitive, cur.soilRaw, cur.raindrop,
                ignored ? " | ada sensor diabaikan" : "");
}

// Nyalakan/matikan pembacaan sensor pemilah mengikuti status konveyor.
void updateSensorPower() {
  const bool want = runningFlag || calFlag;
  if (want == sensorsOn) return;
  sensorsOn = want;
  if (want) {
    // Isi ulang buffer median agar nilai lama sebelum sensor mati tidak
    // dianggap benda.
    for (auto &v : sharpBuf) v = (uint16_t)analogReadMilliVolts(SHARP_PIN);
    Serial.println("[SORT] sensor pemilah AKTIF");
  } else {
    Serial.println("[SORT] sensor pemilah MATI (konveyor berhenti)");
  }
}

void tick() {
  const uint32_t nowMs = millis();
  updateSensorPower();
  if (sensorsOn) readSensors(nowMs);
  handleRunningChange();
  if (runningFlag || calFlag) {
    if (SORT_MODE_PER_SENSOR) {
      trackStations(nowMs);
    } else {
      trackItem(nowMs);
    }
  } else {
    win.open = false;
    resetStations();
  }
  moveTransit(nowMs);
  updatePushers(nowMs);
  handleTestRequest(nowMs);
  printCalibration(nowMs);
}

// Pengukuran jitter. Ditulis hanya oleh task pemilah, dibaca loop() lewat
// takeTimingStats() dengan spinlock (beberapa mikrodetik).
portMUX_TYPE timingMux = portMUX_INITIALIZER_UNLOCKED;
TimingStats timing = {};
bool timingStarted = false;

void recordTiming(int64_t startUs, int64_t prevStartUs, int64_t endUs) {
  const uint32_t execUs = (uint32_t)(endUs - startUs);
  portENTER_CRITICAL(&timingMux);
  timing.ticks++;
  if (execUs > timing.maxExecUs) timing.maxExecUs = execUs;
  if (prevStartUs != 0) {
    const uint32_t periodUs = (uint32_t)(startUs - prevStartUs);
    const int32_t lateUs = (int32_t)periodUs - (int32_t)(kTickMs * 1000);
    if (periodUs > timing.maxPeriodUs) timing.maxPeriodUs = periodUs;
    if (lateUs > timing.maxLateUs) timing.maxLateUs = lateUs;
    if (lateUs > 1000) timing.lateOver1ms++;
  }
  timingStarted = true;
  portEXIT_CRITICAL(&timingMux);
}

void task(void *) {
  TickType_t last = xTaskGetTickCount();
  int64_t prevStartUs = 0;
  for (;;) {
    const int64_t startUs = esp_timer_get_time();
    tick();
    recordTiming(startUs, prevStartUs, esp_timer_get_time());
    prevStartUs = startUs;
    vTaskDelayUntil(&last, pdMS_TO_TICKS(kTickMs));
  }
}

}  // namespace

void begin() {
  reports = xQueueCreate(16, sizeof(Report));

  pinMode(INDUCTIVE_PIN, INPUT);  // pull-up 10 kΩ eksternal
  if (USE_CAPACITIVE) pinMode(CAPACITIVE_PIN, INPUT);

  // Bawa servo ke posisi awal satu per satu, agar ketiganya tidak menarik arus
  // puncak bersamaan saat alat dinyalakan.
  for (uint8_t i = 0; i < kPusherCount; i++) {
    attachServo(i);
    delay(SERVO_STARTUP_STAGGER_MS);
    detachServo(pushers[i]);
  }
  Serial.printf("[SORT] %u pendorong di posisi awal (dinyalakan bergiliran)\n", kPusherCount);

  pinMode(LDR_PIN, INPUT);
  pinMode(RAINDROP_PIN, INPUT);
  analogSetPinAttenuation(SHARP_PIN, ADC_11db);  // rentang 0–3,1 V
  analogSetPinAttenuation(SOIL_PIN, ADC_11db);
  for (auto &v : sharpBuf) v = (uint16_t)analogReadMilliVolts(SHARP_PIN);
  Serial.printf("[SORT] mode: %s\n", SORT_MODE_PER_SENSOR
                    ? "satu sensor satu servo (induktif->logam, soil/kapasitif->organik, "
                      "Sharp IR->recyclable)"
                    : "zona gabungan + aturan sort_rules");
  Serial.printf("[SORT] Sharp IR dipasang %s\n", SHARP_SIDE_MOUNT
                    ? "di samping (sinar terpotong = benda tinggi)"
                    : "di atas (mengukur tinggi)");
  Serial.printf("[SORT] sensor: Sharp IR GPIO%d, LDR %s, raindrop %s\n", SHARP_PIN,
                USE_LDR ? "aktif" : "mati", USE_RAINDROP ? "aktif" : "mati");

  // Core 1 (APP_CPU), terpisah dari Wi-Fi/lwIP di core 0. Prioritas di atas
  // loop() (HTTPS, ultrasonik) sehingga request jaringan yang memblok tidak
  // menunda tick pemilah. Lihat SORTER_TASK_CORE di config.h.
  xTaskCreatePinnedToCore(task, "sorter", 6144, nullptr, SORTER_TASK_PRIORITY, nullptr,
                          SORTER_TASK_CORE);
  Serial.printf("[SORT] task pemilah: core %d, prioritas %d, periode %lu ms\n",
                SORTER_TASK_CORE, SORTER_TASK_PRIORITY, (unsigned long)kTickMs);
}

void setConveyorRunning(bool running) { runningFlag = running; }

bool popReport(Report &out) {
  return reports != nullptr && xQueueReceive(reports, &out, 0) == pdTRUE;
}

void setCalibration(bool on) { calFlag = on; }

void testPusher(uint8_t index) {
  if (index < kPusherCount) testRequest = (int8_t)index;
}

// Sharp IR dianggap sehat jika pernah memberi pembacaan valid dalam 2 detik
// terakhir (sabuk kosong pun terbaca ±SHARP_BELT_DISTANCE_MM).
bool distanceSensorOk() { return millis() - sharpValidMs < 2000; }

bool sensorsActive() { return sensorsOn; }

uint8_t itemsInTransit() { return transitCount; }

bool takeTimingStats(TimingStats &out) {
  portENTER_CRITICAL(&timingMux);
  const bool started = timingStarted;
  out = timing;
  timing = {};
  portEXIT_CRITICAL(&timingMux);
  return started;
}

}  // namespace Sorter
