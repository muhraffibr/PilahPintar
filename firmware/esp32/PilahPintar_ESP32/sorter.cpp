#include "config.h"

#include "sorter.h"

#include <ESP32Servo.h>
#include <VL53L1X.h>
#include <Wire.h>

#include "sort_rules.h"

namespace Sorter {
namespace {

constexpr uint8_t kPusherCount = 3;
constexpr int8_t kNoPusher = -1;  // anorganik: tidak didorong, jatuh di ujung sabuk
constexpr uint32_t kTickMs = 5;
constexpr uint8_t kTransitSize = 8;
constexpr uint32_t kCalPrintMs = 250;

// Bit sensor, untuk mengabaikan sensor yang aktif terus (tersangkut/salah setel).
constexpr uint8_t kTof = 1, kInductive = 2, kCapacitive = 4, kSoil = 8;

const sr_config_t kRules = {
    SOIL_WET_RAW,
    CAPACITIVE_MEANS_ORGANIC != 0,
    BOTTLE_MIN_HEIGHT_MM,
    STYROFOAM_MIN_SIGNAL_MCPS,
    PAPER_MAX_HEIGHT_MM,
    PAPER_MIN_SIGNAL_MCPS,
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
};
Pusher pushers[kPusherCount];

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
  bool tofValid = false;
  int tofMm = 0;
  float signal = 0;
  bool inductive = false;
  bool capacitive = false;
  int soilRaw = 4095;
} cur;

VL53L1X tof;
bool tofReady = false;
uint8_t tofErrors = 0;
uint8_t ignored = 0;
QueueHandle_t reports = nullptr;

volatile bool runningFlag = false;
volatile bool calFlag = false;
volatile int8_t testRequest = -1;
bool wasRunning = false;
bool wasCal = false;
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
  if (deg != p.written) {
    p.servo.write(deg);
    p.written = deg;
  }
}

bool startPush(uint8_t i, uint32_t nowMs) {
  Pusher &p = pushers[i];
  if (p.phase != 0) return false;
  p.target = SERVO_PUSH_DEG;
  p.phase = 1;
  p.phaseMs = nowMs;
  return true;
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
    }
    moveServo(p);
  }
}

void homeAllPushers() {
  for (auto &p : pushers) {
    p.target = SERVO_HOME_DEG;
    p.phase = 0;
  }
}

// ---------------------------------------------------------------------------
// Sensor
// ---------------------------------------------------------------------------
void tofFailed() {
  cur.tofValid = false;
  if (++tofErrors >= 20) {
    tofReady = false;
    Serial.println("[SORT] VL53L1X tidak merespons, dimatikan sampai ESP32 restart");
  }
}

void readSensors() {
  // PC817 menarik output ke LOW saat sensor proximity mendeteksi benda.
  cur.inductive = digitalRead(INDUCTIVE_PIN) == LOW;
  cur.capacitive = digitalRead(CAPACITIVE_PIN) == LOW;
  cur.soilRaw = analogRead(SOIL_PIN);

  if (!tofReady) return;
  const bool ready = tof.dataReady();
  if (tof.last_status != 0) return tofFailed();
  if (!ready) return;
  tof.read(false);
  if (tof.last_status != 0) return tofFailed();
  tofErrors = 0;
  cur.tofValid = tof.ranging_data.range_status == VL53L1X::RangeValid;
  cur.tofMm = tof.ranging_data.range_mm;
  cur.signal = tof.ranging_data.peak_signal_count_rate_MCPS;
}

uint8_t activeMask() {
  uint8_t m = 0;
  if (cur.tofValid && cur.tofMm < TOF_BELT_DISTANCE_MM - TOF_MIN_HEIGHT_MM) m |= kTof;
  if (cur.inductive) m |= kInductive;
  if (cur.capacitive) m |= kCapacitive;
  if (cur.soilRaw <= SOIL_WET_RAW) m |= kSoil;
  return m;
}

// ---------------------------------------------------------------------------
// Item
// ---------------------------------------------------------------------------
void finishItem(uint32_t nowMs) {
  const sr_result_t res = sr_classify(&win.f, &kRules);
  const uint32_t inZoneMs = win.lastMs - win.firstMs;
  Serial.printf(
      "[ITEM] %s (%s) | tinggi=%dmm sinyal=%.2f induktif=%d kapasitif=%d soil=%d | "
      "di zona %lu ms, keputusan %lu ms setelah item lewat\n",
      sr_category_key(res.category), res.reason, win.f.height_mm, win.f.signal_mcps,
      win.f.inductive, win.f.capacitive, win.f.soil_min_raw, (unsigned long)inZoneMs,
      (unsigned long)(nowMs - win.lastMs));
  if (calFlag) {
    Serial.printf("CSV,%lu,%d,%.2f,%d,%d,%d,%s,%s\n", (unsigned long)inZoneMs,
                  win.f.height_mm, win.f.signal_mcps, win.f.inductive, win.f.capacitive,
                  win.f.soil_min_raw, sr_category_key(res.category), res.reason);
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
      win.f = sr_features_t{false, false, -1, 0, 0.0f};
    }
    win.lastMs = nowMs;
    if (active & kInductive) win.f.inductive = true;
    if (active & kCapacitive) win.f.capacitive = true;
    if (!(ignored & kSoil) && (win.f.soil_min_raw < 0 || cur.soilRaw < win.f.soil_min_raw)) {
      win.f.soil_min_raw = cur.soilRaw;
    }
    if (active & kTof) {
      const int height = TOF_BELT_DISTANCE_MM - cur.tofMm;
      if (height > win.f.height_mm) win.f.height_mm = height;
      if (cur.signal > win.f.signal_mcps) win.f.signal_mcps = cur.signal;
    }
    if (nowMs - win.firstMs > ITEM_MAX_MS) {
      Serial.printf("[SORT] sensor aktif terus > %d ms:%s%s%s%s. Diabaikan sampai normal; "
                    "cek sampah tersangkut atau setelan sensor\n",
                    ITEM_MAX_MS, (active & kTof) ? " VL53L1X" : "",
                    (active & kInductive) ? " induktif" : "",
                    (active & kCapacitive) ? " kapasitif" : "",
                    (active & kSoil) ? " soil" : "");
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
      ok = startPush(t.pusher, nowMs);
      if (!ok) Serial.printf("[SORT] pendorong %s masih bergerak, item terlewat\n",
                             kPusherNames[t.pusher]);
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
  homeAllPushers();
}

void handleTestRequest(uint32_t nowMs) {
  const int8_t req = testRequest;
  if (req < 0) return;
  testRequest = -1;
  Serial.printf("[TES] pendorong %s %s\n", kPusherNames[req],
                startPush(req, nowMs) ? "bergerak" : "masih bergerak, coba lagi");
}

void printCalibration(uint32_t nowMs) {
  const bool cal = calFlag;
  if (cal != wasCal) {
    wasCal = cal;
    Serial.printf("[CAL] mode kalibrasi %s\n", cal ? "AKTIF" : "MATI");
    if (cal) {
      Serial.println("CSV,lama_ms,tinggi_mm,sinyal_mcps,induktif,kapasitif,soil_raw,kategori,alasan");
    }
  }
  if (!cal || nowMs - lastCalPrintMs < kCalPrintMs) return;
  lastCalPrintMs = nowMs;
  char tofText[48];
  if (cur.tofValid) {
    snprintf(tofText, sizeof tofText, "tof=%dmm (tinggi %dmm) sinyal=%.2f", cur.tofMm,
             TOF_BELT_DISTANCE_MM - cur.tofMm, cur.signal);
  } else {
    snprintf(tofText, sizeof tofText, "tof=%s", tofReady ? "--" : "GAGAL");
  }
  Serial.printf("[CAL] %s | induktif=%d kapasitif=%d soil=%d%s\n", tofText, cur.inductive,
                cur.capacitive, cur.soilRaw, ignored ? " | ada sensor diabaikan" : "");
}

void tick() {
  const uint32_t nowMs = millis();
  readSensors();
  handleRunningChange();
  if (runningFlag || calFlag) {
    trackItem(nowMs);
  } else {
    win.open = false;
  }
  moveTransit(nowMs);
  updatePushers(nowMs);
  handleTestRequest(nowMs);
  printCalibration(nowMs);
}

void task(void *) {
  TickType_t last = xTaskGetTickCount();
  for (;;) {
    tick();
    vTaskDelayUntil(&last, pdMS_TO_TICKS(kTickMs));
  }
}

}  // namespace

void begin() {
  reports = xQueueCreate(16, sizeof(Report));

  pinMode(INDUCTIVE_PIN, INPUT);  // pull-up 10 kΩ eksternal
  pinMode(CAPACITIVE_PIN, INPUT);

  for (uint8_t i = 0; i < kPusherCount; i++) {
    pushers[i].servo.setPeriodHertz(50);
    pushers[i].servo.attach(kPusherPins[i], SERVO_MIN_US, SERVO_MAX_US);
    pushers[i].servo.write(SERVO_HOME_DEG);
    pushers[i].written = SERVO_HOME_DEG;
  }

  Wire.begin(TOF_SDA_PIN, TOF_SCL_PIN);
  Wire.setClock(400000);
  tof.setTimeout(100);
  if (tof.init()) {
    tof.setDistanceMode(VL53L1X::Short);    // sampai ±1,3 m, paling tahan cahaya matahari
    tof.setMeasurementTimingBudget(20000);  // 20 ms per pengukuran
    tof.startContinuous(20);
    tofReady = true;
    Serial.println("[SORT] VL53L1X siap");
  } else {
    Serial.printf("[SORT] VL53L1X tidak terdeteksi: cek VIN 3V3, SDA %d, SCL %d\n",
                  TOF_SDA_PIN, TOF_SCL_PIN);
  }

  // Core 0 (bersama Wi-Fi), supaya loop() di core 1 yang menunggu HTTPS dan
  // mengukur ultrasonik tidak terganggu dan tidak mengganggu.
  xTaskCreatePinnedToCore(task, "sorter", 6144, nullptr, 5, nullptr, 0);
}

void setConveyorRunning(bool running) { runningFlag = running; }

bool popReport(Report &out) {
  return reports != nullptr && xQueueReceive(reports, &out, 0) == pdTRUE;
}

void setCalibration(bool on) { calFlag = on; }

void testPusher(uint8_t index) {
  if (index < kPusherCount) testRequest = (int8_t)index;
}

bool tofOk() { return tofReady; }

uint8_t itemsInTransit() { return transitCount; }

}  // namespace Sorter
