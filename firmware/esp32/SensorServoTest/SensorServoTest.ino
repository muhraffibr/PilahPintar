/*
 * ============================================================================
 *  PilahPintar — Uji sensor + servo per stasiun (ESP32)
 * ============================================================================
 *  Sketch mandiri: ESP32 + tiga sensor + tiga servo MG996R. Tanpa Wi-Fi,
 *  Firebase, atau STM32. Pasangan sensor -> servo sama dengan firmware utama:
 *
 *    stasiun 1  soil moisture basah     -> servo organik     (GPIO 25)
 *    stasiun 2  sensor induktif (logam) -> servo logam       (GPIO 26)
 *    stasiun 3  Sharp IR, benda tinggi  -> servo recyclable  (GPIO 27)
 *
 *  Begitu sensor mendeteksi sampah, servonya mendorong setelah jeda
 *  (jarak sensor ke pendorong / kecepatan sabuk). Servo selalu bergerak
 *  BERGILIRAN: kalau dua stasiun terpicu bersamaan, servo kedua menunggu
 *  servo pertama kembali. Servo yang diam ditahan di sudut awal.
 *
 *  Rangkaian (sama dengan config.h firmware utama):
 *    Soil moisture   VCC 3V3, GND, AOUT -> GPIO 32 (D32)
 *    Induktif        LJ12A3-4-Z/BX 12 V lewat PC817, pull-up 10 kΩ ke 3V3
 *                    -> GPIO 34 (LOW = ada logam)
 *    Sharp IR        GP2Y0A21 VCC 5 V, GND, Vo -> GPIO 33 (D33)
 *                    + kapasitor 10 µF dekat VCC–GND sensor
 *    Servo           sinyal ke GPIO 25 / 26 / 27, daya 6 V dari LM2596,
 *                    GND LM2596 WAJIB disatukan dengan GND ESP32
 *
 *  Buka Serial Monitor 115200 baud. Ketik perintah lalu Enter:
 *    v        tampilkan / sembunyikan nilai sensor tiap 0,5 detik
 *    s        aktifkan / matikan pemicu servo dari sensor
 *    b        jeda sabuk aktif / mati (mati = servo langsung mendorong)
 *    1 2 3    dorong satu servo secara manual
 *    ?        bantuan
 * ============================================================================
 */
#include <Arduino.h>

// ---------------------------------------------------------------------------
// Pengaturan — samakan dengan config.h firmware utama
// ---------------------------------------------------------------------------
#define SERVO_ORGANIK_PIN 25
#define SERVO_LOGAM_PIN 26
#define SERVO_RECYCLABLE_PIN 27
#define SERVO_HOME_DEG 0
#define SERVO_PUSH_DEG 180
#define SERVO_MIN_US 500
#define SERVO_MAX_US 2400

#define SOIL_PIN 32    // D32 (ADC1)
#define INDUCTIVE_PIN 34
#define SHARP_PIN 33   // D33 (ADC1)

#define SOIL_WET_RAW 2200            // <= nilai ini dianggap basah (organik)
#define SHARP_BELT_DISTANCE_MM 200   // jarak Sharp IR ke sabuk kosong
#define BOTTLE_MIN_HEIGHT_MM 45      // benda setinggi ini atau lebih -> recyclable
#define SHARP_CURVE_A 27.86f         // jarak_cm = A * V^-B
#define SHARP_CURVE_B 1.15f

#define BELT_SPEED_MM_S 100.0f
#define STATION_ORGANIK_SENSOR_TO_PUSHER_MM 40
#define STATION_LOGAM_SENSOR_TO_PUSHER_MM 40
#define STATION_RECYCLABLE_SENSOR_TO_PUSHER_MM 40
#define STATION_MIN_ACTIVE_MS 20     // sensor harus aktif selama ini (anti derau)

constexpr uint32_t kPushMs = 700;        // waktu fase maju
constexpr uint32_t kReturnMs = 700;      // waktu fase kembali
constexpr uint32_t kServoGapMs = 300;    // jeda sebelum servo berikutnya boleh bergerak
constexpr uint32_t kReleaseMs = 150;     // sensor harus mati selama ini sebelum bisa memicu lagi
constexpr uint32_t kHomeStaggerMs = 800; // waktu tiap servo menuju sudut awal saat boot
constexpr uint32_t kMonitorIntervalMs = 500;

constexpr uint32_t kPwmFreqHz = 50;
constexpr uint8_t kPwmBits = 16;
constexpr uint32_t kPeriodUs = 1000000UL / kPwmFreqHz;
constexpr uint32_t kSerialLineTimeoutMs = 100;

constexpr uint8_t kSharpSamples = 5;     // median 5 sampel meredam derau Sharp IR
constexpr int kSharpMinMm = 80, kSharpMaxMm = 900;  // di luar ini tidak valid
constexpr uint8_t kSoilSamples = 4;

// ---------------------------------------------------------------------------
// Data stasiun
// ---------------------------------------------------------------------------
struct Station {
  const char *name;
  const char *sensor;
  uint8_t servoPin;
  uint8_t ledcChannel;
  uint16_t sensorToPusherMm;
  // status sensor
  bool raw;              // sensor aktif saat ini (belum di-debounce)
  uint32_t sinceMs;      // mulai aktif
  uint32_t lastActiveMs; // terakhir aktif
  bool fired;            // sudah memicu servo untuk benda ini
  // antrean servo
  bool pending;
  uint32_t dueMs;
};

Station stations[] = {
    {"organik", "soil", SERVO_ORGANIK_PIN, 0, STATION_ORGANIK_SENSOR_TO_PUSHER_MM},
    {"logam", "induktif", SERVO_LOGAM_PIN, 2, STATION_LOGAM_SENSOR_TO_PUSHER_MM},
    {"recyclable", "sharp", SERVO_RECYCLABLE_PIN, 4, STATION_RECYCLABLE_SENSOR_TO_PUSHER_MM},
};
constexpr uint8_t kCount = sizeof(stations) / sizeof(stations[0]);

// Nilai sensor terakhir
int soilRaw = 4095;
bool inductive = false;
int sharpMv = 0;
int sharpMm = -1;
int heightMm = 0;
uint16_t sharpBuf[kSharpSamples] = {0};
uint8_t sharpIdx = 0;

// Servo
enum class Phase : uint8_t { Idle, Push, Return, Gap };
Phase phase = Phase::Idle;
uint8_t current = 0;
uint32_t phaseStartMs = 0;

bool armed = true;       // sensor memicu servo
bool monitor = true;     // tampilkan nilai sensor
bool beltDelay = true;   // pakai jeda jarak sensor -> pendorong
uint32_t lastMonitorMs = 0;

char lineBuf[16];
uint8_t lineLen = 0;
uint32_t lastCharMs = 0;

// ---------------------------------------------------------------------------
// Servo (LEDC langsung)
// ---------------------------------------------------------------------------
uint32_t degToDuty(int deg) {
  deg = constrain(deg, 0, 180);
  const uint32_t us = map(deg, 0, 180, SERVO_MIN_US, SERVO_MAX_US);
  return (uint32_t)((uint64_t)us * ((1UL << kPwmBits) - 1) / kPeriodUs);
}

void servoWrite(const Station &s, int deg) { ledcWrite(s.servoPin, degToDuty(deg)); }

void setupServos() {
  for (uint8_t i = 0; i < kCount; i++) {
    Station &s = stations[i];
    const bool ok = ledcAttachChannel(s.servoPin, kPwmFreqHz, kPwmBits, s.ledcChannel);
    ledcWrite(s.servoPin, 0);
    Serial.printf("  servo %u %-10s GPIO %u kanal %u: %s\n", i + 1, s.name, s.servoPin,
                  s.ledcChannel, ok ? "OK" : "GAGAL");
  }
  // Ke sudut awal satu per satu agar arus awal tidak menumpuk; lalu ditahan.
  for (uint8_t i = 0; i < kCount; i++) {
    servoWrite(stations[i], SERVO_HOME_DEG);
    delay(kHomeStaggerMs);
  }
}

uint32_t stationDelayMs(const Station &s) {
  if (!beltDelay) return 0;
  return (uint32_t)lroundf(s.sensorToPusherMm * 1000.0f / BELT_SPEED_MM_S);
}

// Masukkan dorongan ke antrean. false jika servo itu sudah antre / bergerak.
bool requestPush(uint8_t i, uint32_t dueMs) {
  Station &s = stations[i];
  if (s.pending || (phase != Phase::Idle && phase != Phase::Gap && current == i)) return false;
  s.pending = true;
  s.dueMs = dueMs;
  return true;
}

void startPush(uint8_t i, uint32_t now) {
  Station &s = stations[i];
  s.pending = false;
  current = i;
  servoWrite(s, SERVO_PUSH_DEG);
  const int32_t late = (int32_t)(now - s.dueMs);
  Serial.printf("[%7.2f s] SERVO %u %s: maju%s\n", now / 1000.0f, i + 1, s.name,
                late > 50 ? " (terlambat, menunggu servo lain)" : "");
  phase = Phase::Push;
  phaseStartMs = now;
}

void updateServos(uint32_t now) {
  const uint32_t elapsed = now - phaseStartMs;
  switch (phase) {
    case Phase::Idle:
    case Phase::Gap: {
      if (phase == Phase::Gap && elapsed < kServoGapMs) break;
      phase = Phase::Idle;
      // Pilih antrean yang jatuh tempo paling awal.
      int8_t next = -1;
      for (uint8_t i = 0; i < kCount; i++) {
        const Station &s = stations[i];
        if (!s.pending || (int32_t)(now - s.dueMs) < 0) continue;
        if (next < 0 || (int32_t)(s.dueMs - stations[next].dueMs) < 0) next = i;
      }
      if (next >= 0) startPush(next, now);
      break;
    }
    case Phase::Push:
      if (elapsed >= kPushMs) {
        servoWrite(stations[current], SERVO_HOME_DEG);
        phase = Phase::Return;
        phaseStartMs = now;
      }
      break;
    case Phase::Return:
      if (elapsed >= kReturnMs) {
        Serial.printf("[%7.2f s] SERVO %u %s: kembali\n", now / 1000.0f, current + 1,
                      stations[current].name);
        phase = Phase::Gap;
        phaseStartMs = now;
      }
      break;
  }
}

// ---------------------------------------------------------------------------
// Sensor
// ---------------------------------------------------------------------------
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

void readSensors() {
  long sum = 0;
  for (uint8_t i = 0; i < kSoilSamples; i++) sum += analogRead(SOIL_PIN);
  soilRaw = sum / kSoilSamples;

  // PC817 menarik output ke LOW saat sensor induktif mendeteksi logam.
  inductive = digitalRead(INDUCTIVE_PIN) == LOW;

  sharpBuf[sharpIdx] = (uint16_t)analogReadMilliVolts(SHARP_PIN);
  sharpIdx = (sharpIdx + 1) % kSharpSamples;
  sharpMv = medianSharp();
  sharpMm = sharpMmFromMv(sharpMv);
  const bool valid = sharpMm >= kSharpMinMm && sharpMm <= kSharpMaxMm;
  heightMm = valid ? SHARP_BELT_DISTANCE_MM - sharpMm : 0;

  stations[0].raw = soilRaw <= SOIL_WET_RAW;
  stations[1].raw = inductive;
  stations[2].raw = valid && heightMm >= BOTTLE_MIN_HEIGHT_MM;
}

void sensorDetail(uint8_t i, char *buf, size_t n) {
  switch (i) {
    case 0: snprintf(buf, n, "soil=%d (basah <= %d)", soilRaw, SOIL_WET_RAW); break;
    case 1: snprintf(buf, n, "induktif=LOW (logam)"); break;
    default: snprintf(buf, n, "tinggi=%d mm (>= %d)", heightMm, BOTTLE_MIN_HEIGHT_MM); break;
  }
}

void updateStations(uint32_t now) {
  for (uint8_t i = 0; i < kCount; i++) {
    Station &s = stations[i];
    if (s.raw) {
      if (now - s.lastActiveMs > kReleaseMs) {  // benda baru
        s.sinceMs = now;
        s.fired = false;
      }
      s.lastActiveMs = now;
      if (!s.fired && now - s.sinceMs >= STATION_MIN_ACTIVE_MS) {
        s.fired = true;
        char detail[48];
        sensorDetail(i, detail, sizeof detail);
        if (!armed) {
          Serial.printf("[%7.2f s] DETEKSI %s: %s (pemicu servo mati)\n", now / 1000.0f,
                        s.sensor, detail);
        } else if (requestPush(i, now + stationDelayMs(s))) {
          Serial.printf("[%7.2f s] DETEKSI %s: %s -> servo %s dalam %lu ms\n",
                        now / 1000.0f, s.sensor, detail, s.name, stationDelayMs(s));
        } else {
          Serial.printf("[%7.2f s] DETEKSI %s: %s (servo %s masih sibuk, diabaikan)\n",
                        now / 1000.0f, s.sensor, detail, s.name);
        }
      }
    }
  }
}

void printMonitor(uint32_t now) {
  if (!monitor || now - lastMonitorMs < kMonitorIntervalMs) return;
  lastMonitorMs = now;
  Serial.printf("soil=%4d %s | induktif=%s | sharp=%4d mV ", soilRaw,
                stations[0].raw ? "BASAH" : "kering", inductive ? "LOGAM" : "-    ", sharpMv);
  if (sharpMm >= kSharpMinMm && sharpMm <= kSharpMaxMm) {
    Serial.printf("jarak=%3d mm tinggi=%3d mm %s\n", sharpMm, heightMm,
                  stations[2].raw ? "TINGGI" : "");
  } else {
    Serial.println("jarak=di luar jangkauan");
  }
}

// ---------------------------------------------------------------------------
// Perintah Serial
// ---------------------------------------------------------------------------
void printHelp() {
  Serial.println();
  Serial.println("=== Uji sensor + servo per stasiun ===");
  Serial.println("  stasiun 1  soil moisture (GPIO 32)  -> servo organik    (GPIO 25)");
  Serial.println("  stasiun 2  induktif      (GPIO 34)  -> servo logam      (GPIO 26)");
  Serial.println("  stasiun 3  Sharp IR      (GPIO 33)  -> servo recyclable (GPIO 27)");
  Serial.println("Perintah:");
  Serial.println("  v       tampilkan / sembunyikan nilai sensor");
  Serial.println("  s       aktifkan / matikan pemicu servo dari sensor");
  Serial.println("  b       jeda sabuk aktif / mati");
  Serial.println("  1 2 3   dorong satu servo secara manual");
  Serial.println("  ?       bantuan ini");
  Serial.printf("Status: pemicu servo %s, jeda sabuk %s (%lu ms), tampilan nilai %s\n\n",
                armed ? "AKTIF" : "mati", beltDelay ? "AKTIF" : "mati",
                stationDelayMs(stations[0]), monitor ? "AKTIF" : "mati");
}

void handleCommand(const char *line) {
  const char cmd = (char)tolower((unsigned char)line[0]);
  if (cmd >= '1' && cmd < '1' + kCount && line[1] == '\0') {
    const uint8_t i = cmd - '1';
    Serial.println(requestPush(i, millis()) ? "Dorong manual masuk antrean."
                                            : "Servo itu sedang antre / bergerak.");
    return;
  }
  switch (cmd) {
    case 'v':
      monitor = !monitor;
      Serial.printf("Tampilan nilai sensor %s.\n", monitor ? "AKTIF" : "mati");
      break;
    case 's':
      armed = !armed;
      Serial.printf("Pemicu servo dari sensor %s.\n", armed ? "AKTIF" : "mati");
      break;
    case 'b':
      beltDelay = !beltDelay;
      Serial.printf("Jeda sabuk %s (%lu ms).\n", beltDelay ? "AKTIF" : "mati",
                    stationDelayMs(stations[0]));
      break;
    case '?':
      printHelp();
      break;
    default:
      Serial.printf("Perintah tidak dikenal: \"%s\" (ketik ? untuk bantuan)\n", line);
      break;
  }
}

void readSerial() {
  while (Serial.available()) {
    const char ch = (char)Serial.read();
    lastCharMs = millis();
    if (ch == '\r' || ch == '\n') {
      if (lineLen > 0) {
        lineBuf[lineLen] = '\0';
        handleCommand(lineBuf);
        lineLen = 0;
      }
    } else if (ch != ' ' && lineLen < sizeof(lineBuf) - 1) {
      lineBuf[lineLen++] = ch;
    }
  }
  if (lineLen > 0 && millis() - lastCharMs >= kSerialLineTimeoutMs) {
    lineBuf[lineLen] = '\0';
    handleCommand(lineBuf);
    lineLen = 0;
  }
}

// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(500);
  printHelp();

  pinMode(INDUCTIVE_PIN, INPUT);  // GPIO 34 tanpa pull-up internal: pakai 10 kΩ eksternal
  analogReadResolution(12);
  analogSetPinAttenuation(SOIL_PIN, ADC_11db);
  analogSetPinAttenuation(SHARP_PIN, ADC_11db);
  for (uint8_t i = 0; i < kSharpSamples; i++) {
    sharpBuf[i] = (uint16_t)analogReadMilliVolts(SHARP_PIN);
    delay(5);
  }

  Serial.println("Menyiapkan servo:");
  setupServos();
  Serial.println("Siap. Dekatkan sampah ke sensor.\n");
}

void loop() {
  const uint32_t now = millis();
  readSerial();
  readSensors();
  updateStations(now);
  updateServos(now);
  printMonitor(now);
  delay(5);
}
