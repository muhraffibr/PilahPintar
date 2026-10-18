/*
 * ============================================================================
 *  PilahPintar — Firmware STM32 (pengendali konveyor)
 * ============================================================================
 *  Board : STM32F411CEU6 "Black Pill"
 *          Arduino IDE -> Board "Generic STM32F4 series",
 *          Board part number "BlackPill F411CE"
 *  Core  : STM32duino (STMicroelectronics) 2.x
 *
 *  Tugas STM32:
 *   - Menjalankan / menghentikan 2 motor konveyor (atas & bawah) sesuai
 *     perintah ESP32, masing-masing dengan soft start.
 *   - Melindungi sistem: tombol darurat, arus berlebih, link ESP32 putus.
 *   - Melaporkan status ke ESP32 tiap 1 detik.
 *
 *  Protokol UART (detail: pp_protocol.h & firmware/README.md):
 *    ESP32 -> STM32 : $CMD,START   $CMD,STOP   $PING
 *    STM32 -> ESP32 : $ACK,<cmd>   $NAK,<cmd>,<alasan>
 *                     $STS,<RUN|STOP>,<kode_gangguan>
 *
 *  Kode gangguan: 0 normal · 1 arus berlebih · 2 macet · 3 tombol darurat
 *                 4 link ESP32 putus
 * ============================================================================
 */
#include "config.h"
#include "pp_protocol.h"

enum : uint8_t {
  FAULT_NONE = 0,
  FAULT_OVERCURRENT = 1,
  FAULT_JAM = 2,
  FAULT_ESTOP = 3,
  FAULT_LINK = 4,
};

HardwareSerial EspSerial(PIN_ESP_RX, PIN_ESP_TX);
pp_reader_t reader;

struct Motor {
  int pwm;
  int in1;
  int in2;
  int targetDuty;
  int duty;
  uint32_t lastRampMs;
};
Motor motors[] = {
    {PIN_MOTOR_A_PWM, PIN_MOTOR_A_IN1, PIN_MOTOR_A_IN2, MOTOR_A_DUTY, 0, 0},  // konveyor atas
    {PIN_MOTOR_B_PWM, PIN_MOTOR_B_IN1, PIN_MOTOR_B_IN2, MOTOR_B_DUTY, 0, 0},  // konveyor bawah
};

bool running = false;
uint8_t fault = FAULT_NONE;
uint32_t lastRxMs = 0;
uint32_t lastStatusMs = 0;
uint32_t overCurrentSinceMs = 0;
uint32_t estopHighSinceMs = 0;

// ---------------------------------------------------------------------------
// Kirim ke ESP32
// ---------------------------------------------------------------------------
void sendFrame(const char *type, const char *f0 = nullptr, const char *f1 = nullptr) {
  const char *fields[2] = {f0, f1};
  const uint8_t n = f1 ? 2 : (f0 ? 1 : 0);
  char frame[PP_MAX_LINE + 8];
  const size_t len = pp_build(frame, sizeof frame, type, fields, n);
  if (len > 0) EspSerial.write((const uint8_t *)frame, len);
}

void sendStatus() {
  char code[4];
  snprintf(code, sizeof code, "%u", fault);
  sendFrame("STS", running ? "RUN" : "STOP", code);
  lastStatusMs = millis();
}

// ---------------------------------------------------------------------------
// Motor
// ---------------------------------------------------------------------------
void applyDuty(Motor &m, int duty) {
  m.duty = constrain(duty, 0, 255);
  analogWrite(m.pwm, m.duty);
}

void motorsStopNow() {
  for (Motor &m : motors) {
    applyDuty(m, 0);
    if (m.in1 >= 0) digitalWrite(m.in1, LOW);
    if (m.in2 >= 0) digitalWrite(m.in2, LOW);
  }
}

void motorsStartRamp() {
  for (Motor &m : motors) m.lastRampMs = millis();
}

// Soft start: naikkan duty tiap motor bertahap sampai kecepatan kerjanya.
void updateRamp() {
  if (!running) return;
  for (Motor &m : motors) {
    if (m.in1 >= 0) digitalWrite(m.in1, HIGH);
    if (m.in2 >= 0) digitalWrite(m.in2, LOW);
    if (m.duty >= m.targetDuty) continue;
    const uint32_t stepMs = m.targetDuty > 0 ? max(1, MOTOR_RAMP_MS / m.targetDuty) : 1;
    if (millis() - m.lastRampMs < stepMs) continue;
    m.lastRampMs = millis();
    applyDuty(m, m.duty + 1);
  }
}

void stopWithFault(uint8_t code) {
  running = false;
  fault = code;
  motorsStopNow();
  sendStatus();  // laporkan segera, jangan tunggu interval
}

// ---------------------------------------------------------------------------
// Perlindungan
// ---------------------------------------------------------------------------
// Aktif jika PB12 HIGH (tombol ditekan / kabel putus) selama ESTOP_DEBOUNCE_MS.
bool estopActive() {
#if USE_ESTOP
  if (digitalRead(PIN_ESTOP) == LOW) {
    estopHighSinceMs = 0;
    return false;
  }
  if (estopHighSinceMs == 0) estopHighSinceMs = millis() | 1;
  return millis() - estopHighSinceMs >= ESTOP_DEBOUNCE_MS;
#else
  return false;
#endif
}

bool overCurrent() {
#if USE_CURRENT_SENSE
  if (analogRead(PIN_CURRENT) < CURRENT_LIMIT_RAW) {
    overCurrentSinceMs = 0;
    return false;
  }
  if (overCurrentSinceMs == 0) overCurrentSinceMs = millis();
  return millis() - overCurrentSinceMs >= CURRENT_TRIP_MS;
#else
  return false;
#endif
}

void checkSafety() {
  // Tombol darurat dilaporkan juga saat konveyor diam, supaya aplikasi tahu.
  // Gangguan tetap tercatat setelah tombol dilepas sampai ada START baru.
  if (estopActive()) {
    if (running || fault != FAULT_ESTOP) stopWithFault(FAULT_ESTOP);
    return;
  }
  if (!running) return;
  if (overCurrent()) {
    stopWithFault(FAULT_OVERCURRENT);
  } else if (LINK_TIMEOUT_MS > 0 && millis() - lastRxMs > LINK_TIMEOUT_MS) {
    stopWithFault(FAULT_LINK);
  }
  // Tambahkan deteksi macet (FAULT_JAM) di sini bila memakai encoder/limit switch.
}

// ---------------------------------------------------------------------------
// Pesan dari ESP32
// ---------------------------------------------------------------------------
void handleMessage(const pp_msg_t &m) {
  lastRxMs = millis();
  if (pp_is(&m, "PING")) return;

  if (pp_is(&m, "CMD")) {
    const char *cmd = pp_field(&m, 0);
    if (strcmp(cmd, "START") == 0) {
      if (estopActive()) {
        fault = FAULT_ESTOP;
        sendFrame("NAK", "START", "ESTOP");
      } else {
        fault = FAULT_NONE;  // START sekaligus mereset gangguan
        running = true;
        motorsStartRamp();
        sendFrame("ACK", "START");
      }
    } else if (strcmp(cmd, "STOP") == 0) {
      running = false;
      motorsStopNow();
      sendFrame("ACK", "STOP");
    } else {
      sendFrame("NAK", cmd, "UNKNOWN");
    }
    sendStatus();
  }
}

void readEsp() {
  while (EspSerial.available()) {
    pp_msg_t msg;
    if (pp_reader_feed(&reader, (char)EspSerial.read(), &msg) == PP_MSG) {
      handleMessage(msg);
    }
  }
}

// LED: menyala = berjalan, kedip cepat = gangguan, kedip lambat = siaga.
void updateLed() {
  bool on;
  if (running) {
    on = true;
  } else if (fault != FAULT_NONE) {
    on = (millis() / 150) % 2;
  } else {
    on = (millis() / 1000) % 2;
  }
  digitalWrite(PIN_LED, on ? LOW : HIGH);  // aktif LOW
}

// ---------------------------------------------------------------------------
void setup() {
  pinMode(PIN_LED, OUTPUT);
  for (Motor &m : motors) {
    pinMode(m.pwm, OUTPUT);
    if (m.in1 >= 0) pinMode(m.in1, OUTPUT);
    if (m.in2 >= 0) pinMode(m.in2, OUTPUT);
  }
#if USE_ESTOP
  pinMode(PIN_ESTOP, INPUT_PULLUP);
#endif
#if USE_CURRENT_SENSE
  analogReadResolution(12);
#endif
  analogWriteResolution(8);
  analogWriteFrequency(MOTOR_PWM_FREQ_HZ);
  motorsStopNow();

  EspSerial.begin(ESP_BAUD);
  pp_reader_init(&reader);
  lastRxMs = millis();
}

void loop() {
  readEsp();
  checkSafety();
  updateRamp();
  if (millis() - lastStatusMs >= STATUS_INTERVAL_MS) sendStatus();
  updateLed();
}
