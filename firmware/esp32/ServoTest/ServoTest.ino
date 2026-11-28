/*
 * ============================================================================
 *  PilahPintar — Uji tiga servo MG996R bergiliran (ESP32)
 * ============================================================================
 *  Sketch mandiri: cukup board ESP32 + tiga servo MG996R + catu daya servo.
 *  Tanpa Wi-Fi, Firebase, STM32, sensor, atau library servo.
 *
 *  Urutan: servo 1 maju -> kembali -> jeda beberapa detik -> servo 2 maju ->
 *  kembali -> jeda -> servo 3 ... lalu ulang dari servo 1.
 *
 *  Tiap servo memakai kanal PWM (LEDC) sendiri. Servo yang sedang tidak
 *  bergiliran ditahan di sudut awal (kHoldIdle). Kalau servo masih bergerak
 *  bersamaan, cek kabel: GND servo harus disatukan dengan GND ESP32, dan kabel
 *  sinyal (oranye) tiap servo harus ke pinnya sendiri.
 *
 *  Rangkaian (sama dengan firmware utama):
 *    Servo 1 organik     kabel sinyal (oranye) -> GPIO 25
 *    Servo 2 logam       kabel sinyal (oranye) -> GPIO 26
 *    Servo 3 recyclable  kabel sinyal (oranye) -> GPIO 27
 *    Kabel merah semua servo   -> +6 V LM2596 #2 (JANGAN dari pin 5V/3V3 ESP32)
 *    Kabel cokelat semua servo -> GND LM2596, lalu GND LM2596 -> GND ESP32
 *
 *  Buka Serial Monitor 115200 baud. Ketik perintah lalu Enter:
 *    a        mulai / hentikan mode bergiliran otomatis (aktif saat menyala)
 *    1 2 3    gerakkan satu servo sekali
 *    h        bawa semua servo ke sudut awal, satu per satu
 *    j<ms>    ubah jeda antar servo, contoh: j5000 (5 detik)
 *    d<deg>   ubah sudut dorong, contoh: d120
 *    k<deg>   ubah sudut kembali (awal), contoh: k10
 *    t<ms>    ubah waktu tiap gerakan, contoh: t800
 *    ?        tampilkan bantuan dan pengaturan sekarang
 * ============================================================================
 */
#include <Arduino.h>

// Samakan dengan config.h firmware utama.
#define SERVO_ORGANIK_PIN 25
#define SERVO_LOGAM_PIN 26
#define SERVO_RECYCLABLE_PIN 27
#define SERVO_HOME_DEG 0     // pendorong mundur penuh
#define SERVO_PUSH_DEG 180   // pendorong maju penuh
#define SERVO_MIN_US 500     // lebar pulsa untuk 0°
#define SERVO_MAX_US 2400    // lebar pulsa untuk 180°

constexpr uint32_t kDefaultGapMs = 3000;   // jeda antar servo (bisa diubah: j<ms>)
constexpr uint32_t kDefaultMoveMs = 800;   // waktu tiap gerakan maju / kembali
constexpr uint32_t kHomeStaggerMs = 800;   // waktu tiap servo menuju sudut awal saat boot
// true  = servo yang tidak bergiliran terus diberi pulsa sudut awal, jadi
//         menahan posisinya dan tidak ikut bergerak karena gangguan.
// false = servo yang tidak bergiliran tidak diberi pulsa (hemat arus, lemas).
constexpr bool kHoldIdle = true;

constexpr uint32_t kPwmFreqHz = 50;        // servo: periode 20 ms
constexpr uint8_t kPwmBits = 16;
constexpr uint32_t kPeriodUs = 1000000UL / kPwmFreqHz;
constexpr uint32_t kSerialLineTimeoutMs = 100;  // perintah tanpa Enter juga diproses

struct ServoChannel {
  const char *name;
  uint8_t pin;
  uint8_t ledcChannel;  // kanal berbeda-beda, di timer berbeda
};

ServoChannel channels[] = {
    {"organik", SERVO_ORGANIK_PIN, 0},
    {"logam", SERVO_LOGAM_PIN, 2},
    {"recyclable", SERVO_RECYCLABLE_PIN, 4},
};
constexpr uint8_t kCount = sizeof(channels) / sizeof(channels[0]);

int homeDeg = SERVO_HOME_DEG;
int pushDeg = SERVO_PUSH_DEG;
uint32_t moveMs = kDefaultMoveMs;
uint32_t gapMs = kDefaultGapMs;

enum class Phase : uint8_t { Idle, Push, Return, Gap };
Phase phase = Phase::Idle;
uint8_t current = 0;        // servo yang sedang bergiliran
uint32_t phaseStartMs = 0;
bool autoMode = true;
int8_t pendingSingle = -1;  // servo yang diminta lewat perintah 1/2/3
bool homeRequested = false;
uint32_t roundCount = 0;

char lineBuf[16];
uint8_t lineLen = 0;
uint32_t lastCharMs = 0;

// ---------------------------------------------------------------------------
// Servo (LEDC langsung, tanpa library)
// ---------------------------------------------------------------------------

uint32_t degToDuty(int deg) {
  deg = constrain(deg, 0, 180);
  const uint32_t us = map(deg, 0, 180, SERVO_MIN_US, SERVO_MAX_US);
  return (uint32_t)((uint64_t)us * ((1UL << kPwmBits) - 1) / kPeriodUs);
}

// Kirim pulsa posisi ke satu servo.
void servoWrite(const ServoChannel &c, int deg) { ledcWrite(c.pin, degToDuty(deg)); }

// Hentikan pulsa: servo diam dan tidak menahan posisi.
void servoRelease(const ServoChannel &c) { ledcWrite(c.pin, 0); }

// Servo yang sedang tidak bergiliran: tahan di sudut awal (kHoldIdle) atau lepas.
void servoIdle(const ServoChannel &c) {
  if (kHoldIdle) {
    servoWrite(c, homeDeg);
  } else {
    servoRelease(c);
  }
}

// Tampilkan pulsa yang benar-benar keluar di tiap pin (0 = tidak ada pulsa).
void printPulses() {
  Serial.print("           pulsa:");
  for (uint8_t i = 0; i < kCount; i++) {
    const uint32_t us =
        (uint32_t)((uint64_t)ledcRead(channels[i].pin) * kPeriodUs / ((1UL << kPwmBits) - 1));
    Serial.printf("  GPIO%u(%s)=%lu us", channels[i].pin, channels[i].name, us);
  }
  Serial.println();
}

bool setupServoPins() {
  bool ok = true;
  for (uint8_t i = 0; i < kCount; i++) {
    ServoChannel &c = channels[i];
    if (ledcAttachChannel(c.pin, kPwmFreqHz, kPwmBits, c.ledcChannel)) {
      servoRelease(c);
      Serial.printf("  servo %u %-10s GPIO %u -> kanal PWM %u: OK\n", i + 1, c.name,
                    c.pin, c.ledcChannel);
    } else {
      Serial.printf("  servo %u %-10s GPIO %u -> kanal PWM %u: GAGAL\n", i + 1, c.name,
                    c.pin, c.ledcChannel);
      ok = false;
    }
  }
  return ok;
}

void homeAll() {
  Serial.printf("Membawa semua servo ke sudut awal %d°, satu per satu...\n", homeDeg);
  for (uint8_t i = 0; i < kCount; i++) {
    const ServoChannel &c = channels[i];
    Serial.printf("  servo %u %-10s -> %d°\n", i + 1, c.name, homeDeg);
    servoWrite(c, homeDeg);
    delay(kHomeStaggerMs);
    servoIdle(c);
  }
}

void startCycle(uint8_t i) {
  current = i;
  const ServoChannel &c = channels[i];
  servoWrite(c, pushDeg);
  Serial.printf("[%6.1f s] servo %u %-10s (GPIO %u): maju ke %d°\n", millis() / 1000.0f,
                i + 1, c.name, c.pin, pushDeg);
  delay(50);  // nilai PWM baru berlaku di awal periode berikutnya (20 ms)
  printPulses();
  phase = Phase::Push;
  phaseStartMs = millis();
}

void updateSequence() {
  const uint32_t now = millis();
  const uint32_t elapsed = now - phaseStartMs;
  const ServoChannel &c = channels[current];

  switch (phase) {
    case Phase::Idle:
      if (homeRequested) {
        homeRequested = false;
        homeAll();
      } else if (pendingSingle >= 0) {
        const uint8_t i = pendingSingle;
        pendingSingle = -1;
        startCycle(i);
      } else if (autoMode) {
        startCycle(0);
      }
      break;

    case Phase::Push:
      if (elapsed >= moveMs) {
        servoWrite(c, homeDeg);
        Serial.printf("[%6.1f s] servo %u %-10s (GPIO %u): kembali ke %d°\n", now / 1000.0f,
                      current + 1, c.name, c.pin, homeDeg);
        phase = Phase::Return;
        phaseStartMs = now;
      }
      break;

    case Phase::Return:
      if (elapsed >= moveMs) {
        servoIdle(c);
        if (autoMode && pendingSingle < 0 && !homeRequested) {
          Serial.printf("           jeda %.1f detik...\n", gapMs / 1000.0f);
        }
        phase = Phase::Gap;
        phaseStartMs = now;
      }
      break;

    case Phase::Gap:
      // Perintah 1/2/3/h tidak perlu menunggu jeda penuh.
      if (pendingSingle >= 0 || homeRequested || !autoMode) {
        phase = Phase::Idle;
        break;
      }
      if (elapsed < gapMs) break;
      if (current == kCount - 1) {
        roundCount++;
        Serial.printf("--- putaran ke-%lu selesai ---\n", roundCount);
      }
      startCycle((current + 1) % kCount);
      break;
  }
}

// ---------------------------------------------------------------------------
// Perintah Serial
// ---------------------------------------------------------------------------

void printSettings() {
  Serial.printf("Pengaturan: awal %d°, dorong %d°, gerakan %lu ms, jeda %lu ms, "
                "otomatis %s\n",
                homeDeg, pushDeg, moveMs, gapMs, autoMode ? "AKTIF" : "mati");
  if (homeDeg == pushDeg) {
    Serial.println("PERINGATAN: sudut awal = sudut dorong, servo tidak akan bergerak.");
  }
}

void printHelp() {
  Serial.println();
  Serial.println("=== Uji tiga servo MG996R bergiliran ===");
  Serial.println("Perintah:");
  Serial.println("  a       mulai / hentikan mode bergiliran otomatis");
  Serial.println("  1 2 3   gerakkan satu servo sekali");
  Serial.println("  h       bawa semua servo ke sudut awal");
  Serial.println("  j<ms>   jeda antar servo, contoh j5000");
  Serial.println("  d<deg>  sudut dorong, contoh d120");
  Serial.println("  k<deg>  sudut kembali (awal), contoh k10");
  Serial.println("  t<ms>   waktu tiap gerakan, contoh t800");
  Serial.println("  ?       bantuan ini");
  printSettings();
  Serial.println();
}

// Baca angka setelah huruf perintah. false jika tidak ada angka atau di luar batas.
bool parseNumber(const char *arg, long minV, long maxV, long &out) {
  char *end = nullptr;
  const long v = strtol(arg, &end, 10);
  if (end == arg || v < minV || v > maxV) return false;
  out = v;
  return true;
}

void handleCommand(const char *line) {
  const char cmd = (char)tolower((unsigned char)line[0]);
  const char *arg = line + 1;
  long v = 0;

  if (cmd >= '1' && cmd < '1' + kCount && line[1] == '\0') {
    const uint8_t i = cmd - '1';
    autoMode = false;
    pendingSingle = i;
    Serial.printf("Servo %u %s akan bergerak sekali%s.\n", i + 1, channels[i].name,
                  phase == Phase::Idle || phase == Phase::Gap
                      ? ""
                      : " setelah servo sekarang kembali");
    return;
  }

  switch (cmd) {
    case 'a':
      autoMode = !autoMode;
      pendingSingle = -1;
      Serial.println(autoMode ? "Mode bergiliran otomatis AKTIF."
                              : "Mode bergiliran otomatis berhenti.");
      break;

    case 'h':
      autoMode = false;
      pendingSingle = -1;
      homeRequested = true;
      break;

    case 'j':
      if (parseNumber(arg, 0, 60000, v)) {
        gapMs = (uint32_t)v;
        printSettings();
      } else {
        Serial.println("Format: j<0-60000>, contoh j5000 (5 detik)");
      }
      break;

    case 'd':
      if (parseNumber(arg, 0, 180, v)) {
        pushDeg = (int)v;
        printSettings();
      } else {
        Serial.println("Format: d<0-180>, contoh d120");
      }
      break;

    case 'k':
      if (parseNumber(arg, 0, 180, v)) {
        homeDeg = (int)v;
        printSettings();
        Serial.println("Ketik h agar semua servo pindah ke sudut awal yang baru.");
      } else {
        Serial.println("Format: k<0-180>, contoh k10");
      }
      break;

    case 't':
      if (parseNumber(arg, 200, 5000, v)) {
        moveMs = (uint32_t)v;
        printSettings();
      } else {
        Serial.println("Format: t<200-5000>, contoh t800");
      }
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
  // Serial Monitor diset "No line ending": proses setelah jeda singkat.
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

  Serial.println("Menyiapkan PWM:");
  if (!setupServoPins()) {
    Serial.println("Ada pin yang gagal. Cek nomor pin, lalu restart.");
  }

  homeAll();
  Serial.println("Mulai bergiliran...");
}

void loop() {
  readSerial();
  updateSequence();
  delay(5);
}
