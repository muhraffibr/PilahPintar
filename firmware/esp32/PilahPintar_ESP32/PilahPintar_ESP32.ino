/*
 * ============================================================================
 *  PilahPintar — Firmware ESP32 (gateway IoT)
 * ============================================================================
 *  Tugas ESP32:
 *   1. Memilah sampah di zona sensor konveyor bawah (sorter.cpp):
 *      VL53L1X, induktif, kapasitif, soil moisture -> 3 servo pendorong
 *   2. Membaca kapasitas 4 tempat sampah (ultrasonik)      -> bins/<kategori>
 *   3. Melaporkan setiap item yang selesai dipilah          -> sortings/<pushId>
 *   4. Mengirim heartbeat status sistem tiap 5 detik        -> system_status
 *   5. Membaca perintah START/STOP dari aplikasi            <- commands/latest
 *      dan meneruskannya ke STM32 lewat UART.
 *
 *  Board   : ESP32 Dev Module (ESP32-DevKitC V4 / WROOM-32U)
 *  Library : ArduinoJson 7.x (Benoit Blanchon), VL53L1X (Pololu),
 *            ESP32Servo (Kevin Harrington) — semua dari Library Manager
 *  Setup   : salin secrets.example.h -> secrets.h, isi Wi-Fi & Firebase.
 *
 *  Perintah Serial Monitor (115200, Newline):
 *    $CAL,ON / $CAL,OFF  mode kalibrasi sensor pemilah
 *    $TES,0 / 1 / 2      gerakkan pendorong organik / logam / recyclable sekali
 *    $SIM,ON / $SIM,OFF  "STM32 virtual" untuk uji tanpa STM32
 *
 *  Protokol UART ke STM32 (detail: pp_protocol.h & firmware/README.md):
 *    ESP32 -> STM32 : $CMD,START   $CMD,STOP   $PING
 *    STM32 -> ESP32 : $ACK,<cmd>   $NAK,<cmd>,<alasan>
 *                     $STS,<RUN|STOP>,<kode_gangguan>     (tiap 1 detik)
 *                     $SRT,<kategori>,<OK|FAIL>[,<item>]  (opsional)
 * ============================================================================
 */
#include "config.h"

#include <ArduinoJson.h>
#include <WiFi.h>
#include <sys/time.h>
#include <time.h>

#include "bin_sensors.h"
#include "firebase_rtdb.h"
#include "pp_protocol.h"
#include "sorter.h"

// Kategori — HARUS sama dengan aplikasi (lib/models/waste_category.dart).
const char *const KATEGORI_ORGANIK = "organik";
const char *const KATEGORI_RECYCLABLE = "recyclable";
const char *const KATEGORI_LOGAM = "logam";
const char *const KATEGORI_ANORGANIK = "anorganik";

HardwareSerial StmSerial(2);
FirebaseRtdb firebase;
pp_reader_t stmReader;
pp_reader_t usbReader;
#if DEBUG_INJECT_FROM_USB
// "STM32 virtual": ketik $SIM,ON di Serial Monitor agar ESP32 membalas
// perintah seolah STM32 tersambung (uji tanpa STM32).
bool virtualStm = false;
bool virtualRunning = false;
uint32_t lastVirtualStsMs = 0;
#endif

void handleStmMessage(const pp_msg_t &m);

// ---------------------------------------------------------------------------
// State perangkat (dikirim ke system_status)
// ---------------------------------------------------------------------------
struct DeviceState {
  bool systemOn = false;         // sistem pemilah dijalankan (START diterima)
  bool conveyorRunning = false;  // dilaporkan STM32 lewat $STS
  uint8_t faultCode = 0;         // dilaporkan STM32 lewat $STS
  bool stmOnline = false;
  uint32_t lastStmMs = 0;
} dev;

struct PendingCommand {
  bool active = false;
  char code[8] = "";
  uint32_t sentMs = 0;
} pending;
uint64_t lastHandledIssuedAt = 0;

int almostFullThreshold = 70;
int fullThreshold = 90;

// Antrean laporan pemilahan — tidak hilang saat Wi-Fi putus sebentar.
struct SortEvent {
  char category[12];
  char item[24];
  bool ok;
  uint64_t timestampMs;  // 0 = pakai waktu server
};
constexpr uint8_t kQueueSize = 16;
SortEvent sortQueue[kQueueSize];
uint8_t queueHead = 0;
uint8_t queueCount = 0;

uint32_t bootMs = 0;
uint32_t lastHeartbeatMs = 0;
uint32_t lastCommandPollMs = 0;
uint32_t lastBinReportMs = 0;
uint32_t lastSettingsPollMs = 0;
uint32_t lastPingMs = 0;
uint32_t lastSortAttemptMs = 0;
uint32_t lastWifiAttemptMs = 0;
bool heartbeatDue = false;
bool settingsLoaded = false;
float lastReportedPct[BinSensors::kCount] = {-100, -100, -100, -100};

// ---------------------------------------------------------------------------
// Utilitas
// ---------------------------------------------------------------------------

// Epoch milidetik dari NTP; 0 jika jam belum tersinkron.
uint64_t epochMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  if (tv.tv_sec < 1700000000) return 0;
  return (uint64_t)tv.tv_sec * 1000ULL + tv.tv_usec / 1000;
}

bool isCategory(const char *s) {
  return strcmp(s, KATEGORI_ORGANIK) == 0 || strcmp(s, KATEGORI_RECYCLABLE) == 0 ||
         strcmp(s, KATEGORI_LOGAM) == 0 || strcmp(s, KATEGORI_ANORGANIK) == 0;
}

const char *binStatus(float pct) {
  if (pct >= fullThreshold) return "FULL";
  if (pct >= almostFullThreshold) return "ALMOST_FULL";
  return "NORMAL";
}

// Teks gangguan untuk system_status.error ("" = normal).
const char *faultText() {
  if (!dev.stmOnline) return "STM32 tidak merespons (periksa kabel UART)";
  switch (dev.faultCode) {
    case 0: return "";
    case 1: return "Motor konveyor overcurrent";
    case 2: return "Konveyor macet";
    case 3: return "Tombol darurat ditekan";
    case 4: return "STM32 kehilangan sinyal dari ESP32";
    default: return "Gangguan konveyor";
  }
}

#if DEBUG_INJECT_FROM_USB
// Proses satu baris seolah datang dari STM32, mis. "STS,RUN,0".
void injectFromStm(const char *body) {
  pp_msg_t msg;
  if (pp_parse_body(body, strlen(body), &msg) == PP_MSG) handleStmMessage(msg);
}

void updateVirtualStm() {
  if (!virtualStm || millis() - lastVirtualStsMs < 1000) return;
  lastVirtualStsMs = millis();
  injectFromStm(virtualRunning ? "STS,RUN,0" : "STS,STOP,0");
}
#endif

void sendToStm(const char *type, const char *field = nullptr) {
#if DEBUG_INJECT_FROM_USB
  if (virtualStm) {
    if (strcmp(type, "CMD") == 0 && field) {
      virtualRunning = strcmp(field, "START") == 0;
      char reply[24];
      snprintf(reply, sizeof reply, "ACK,%s", field);
      Serial.printf("[SIM] STM32 virtual menerima %s\n", field);
      injectFromStm(reply);
      lastVirtualStsMs = 0;  // kirim STS berikutnya segera
    }
    return;
  }
#endif
  char frame[PP_MAX_LINE + 8];
  const char *fields[1] = {field};
  const size_t n = pp_build(frame, sizeof frame, type, fields, field ? 1 : 0);
  if (n == 0) return;
  StmSerial.write((const uint8_t *)frame, n);
  if (strcmp(type, "PING") != 0) Serial.printf("[STM] -> %s", frame);
}

// ---------------------------------------------------------------------------
// Laporan pemilahan
// ---------------------------------------------------------------------------
// Dipanggil loop() untuk setiap hasil dari sorter.cpp, juga untuk pesan
// "$SRT,<kategori>,<OK|FAIL>,<item>" dari STM32 atau Serial Monitor, contoh:
//
//   laporkanPemilahan(KATEGORI_LOGAM, true, "Kaleng minuman");
//   laporkanPemilahan(KATEGORI_ANORGANIK, false);   // gagal dipilah
// ---------------------------------------------------------------------------
void laporkanPemilahan(const char *kategori, bool berhasil, const char *item = "") {
  if (!isCategory(kategori)) {
    Serial.printf("[SORT] kategori tidak dikenal: %s\n", kategori);
    return;
  }
  if (queueCount == kQueueSize) {  // penuh: buang yang paling lama
    queueHead = (queueHead + 1) % kQueueSize;
    queueCount--;
  }
  SortEvent &e = sortQueue[(queueHead + queueCount) % kQueueSize];
  strlcpy(e.category, kategori, sizeof e.category);
  strlcpy(e.item, item ? item : "", sizeof e.item);
  e.ok = berhasil;
  e.timestampMs = epochMs();
  queueCount++;
  Serial.printf("[SORT] %s %s %s (antrean %u)\n", kategori, berhasil ? "OK" : "FAIL",
                e.item, queueCount);
}

// ---------------------------------------------------------------------------
// Pesan dari STM32
// ---------------------------------------------------------------------------
void patchCommandStatus(const char *status) {
  if (WiFi.status() != WL_CONNECTED || !firebase.ready()) return;
  JsonDocument doc;
  doc["status"] = status;
  String body;
  serializeJson(doc, body);
  if (!firebase.patch("commands/latest", body)) {
    Serial.printf("[FB] gagal update status perintah: %s\n", firebase.lastError().c_str());
  }
}

void handleStmMessage(const pp_msg_t &m) {
  if (!dev.stmOnline) heartbeatDue = true;
  dev.stmOnline = true;
  dev.lastStmMs = millis();

  if (pp_is(&m, "STS")) {
    const bool running = strcmp(pp_field(&m, 0), "RUN") == 0;
    const uint8_t fault = (uint8_t)atoi(pp_field(&m, 1));
    if (running != dev.conveyorRunning || fault != dev.faultCode) heartbeatDue = true;
    dev.conveyorRunning = running;
    dev.faultCode = fault;
    if (running) dev.systemOn = true;
  } else if (pp_is(&m, "ACK") || pp_is(&m, "NAK")) {
    const bool ack = pp_is(&m, "ACK");
    const char *cmd = pp_field(&m, 0);
    Serial.printf("[STM] <- %s %s %s\n", m.type, cmd, pp_field(&m, 1));
    if (pending.active && strcmp(cmd, pending.code) == 0) {
      pending.active = false;
      if (ack) {
        const bool start = strcmp(cmd, "START") == 0;
        dev.systemOn = start;
        dev.conveyorRunning = start;
        if (start) dev.faultCode = 0;
      }
      heartbeatDue = true;
      patchCommandStatus(ack ? "DONE" : "FAILED");
    }
  } else if (pp_is(&m, "SRT")) {
    laporkanPemilahan(pp_field(&m, 0), strcmp(pp_field(&m, 1), "OK") == 0,
                      pp_field(&m, 2));
  }
}

// Perintah yang diketik di Serial Monitor. true jika sudah ditangani.
bool handleUsbCommand(const pp_msg_t &m) {
  if (pp_is(&m, "CAL")) {
    Sorter::setCalibration(strcmp(pp_field(&m, 0), "ON") == 0);
    return true;
  }
  if (pp_is(&m, "TES")) {
    Sorter::testPusher((uint8_t)atoi(pp_field(&m, 0)));
    return true;
  }
#if DEBUG_INJECT_FROM_USB
  if (pp_is(&m, "SIM")) {
    virtualStm = strcmp(pp_field(&m, 0), "ON") == 0;
    virtualRunning = false;
    Serial.printf("[SIM] STM32 virtual %s\n", virtualStm ? "AKTIF" : "MATI");
    return true;
  }
#endif
  return false;
}

void readSerialInto(Stream &port, pp_reader_t &reader, const char *source, bool fromUsb) {
  while (port.available()) {
    pp_msg_t msg;
    const pp_result_t res = pp_reader_feed(&reader, (char)port.read(), &msg);
    if (res == PP_MSG) {
      if (fromUsb && (handleUsbCommand(msg) || !DEBUG_INJECT_FROM_USB)) continue;
      handleStmMessage(msg);
    } else if (res != PP_NONE) {
      Serial.printf("[%s] frame ditolak (kode %d)\n", source, res);
    }
  }
}

void checkStmLink() {
  if (dev.stmOnline && millis() - dev.lastStmMs > STM_LINK_TIMEOUT_MS) {
    dev.stmOnline = false;
    dev.conveyorRunning = false;
    heartbeatDue = true;
    Serial.println("[STM] link terputus");
  }
  if (pending.active && millis() - pending.sentMs > COMMAND_ACK_TIMEOUT_MS) {
    pending.active = false;
    Serial.printf("[STM] tidak ada balasan untuk %s\n", pending.code);
    patchCommandStatus("FAILED");
  }
  if (millis() - lastPingMs >= STM_PING_INTERVAL_MS) {
    lastPingMs = millis();
    sendToStm("PING");
  }
}

// ---------------------------------------------------------------------------
// Firebase
// ---------------------------------------------------------------------------
void sendHeartbeat() {
  JsonDocument doc;
  doc["system_status"] = dev.systemOn ? "ON" : "OFF";
  doc["conveyor_status"] = dev.conveyorRunning ? "RUNNING" : "STOPPED";
  doc["connection_status"] = "CONNECTED";
  doc["last_updated"][".sv"] = "timestamp";  // waktu server Firebase
  doc["error"] = faultText();
  String body;
  serializeJson(doc, body);
  if (firebase.patch("system_status", body)) {
    heartbeatDue = false;
  } else {
    Serial.printf("[FB] heartbeat gagal: %s\n", firebase.lastError().c_str());
  }
  lastHeartbeatMs = millis();
}

void flushSortQueue() {
  lastSortAttemptMs = 0;
  uint8_t sent = 0;
  while (queueCount > 0 && sent < 4) {
    const SortEvent &e = sortQueue[queueHead];
    JsonDocument doc;
    doc["category"] = e.category;
    doc["status"] = e.ok ? "SUCCESS" : "FAILED";
    if (e.item[0]) doc["item"] = e.item;
    if (e.timestampMs) {
      doc["timestamp"] = e.timestampMs;
    } else {
      doc["timestamp"][".sv"] = "timestamp";
    }
    String body;
    serializeJson(doc, body);
    if (!firebase.post("sortings", body)) {
      Serial.printf("[FB] kirim pemilahan gagal: %s\n", firebase.lastError().c_str());
      lastSortAttemptMs = millis();  // coba lagi 2 dtk kemudian
      return;
    }
    queueHead = (queueHead + 1) % kQueueSize;
    queueCount--;
    sent++;
  }
}

void reportBins(bool force) {
  bool changed = force;
  for (uint8_t i = 0; i < BinSensors::kCount; i++) {
    if (BinSensors::valid(i) &&
        fabsf(BinSensors::percent(i) - lastReportedPct[i]) >= BIN_REPORT_DELTA_PCT) {
      changed = true;
    }
  }
  if (!changed) return;

  // Multi-path update: satu PATCH untuk keempat tempat sampah.
  JsonDocument doc;
  uint8_t count = 0;
  for (uint8_t i = 0; i < BinSensors::kCount; i++) {
    if (!BinSensors::valid(i)) continue;  // sensor belum terpasang/gagal
    const String k = BinSensors::key(i);
    const float pct = roundf(BinSensors::percent(i) * 10.0f) / 10.0f;
    doc[k + "/id"] = "bin_" + k;
    doc[k + "/category"] = k;
    doc[k + "/capacity_percentage"] = pct;
    doc[k + "/status"] = binStatus(pct);
    doc[k + "/last_updated"][".sv"] = "timestamp";
    count++;
  }
  lastBinReportMs = millis();
  if (count == 0) return;

  String body;
  serializeJson(doc, body);
  if (firebase.patch("bins", body)) {
    for (uint8_t i = 0; i < BinSensors::kCount; i++) {
      if (BinSensors::valid(i)) lastReportedPct[i] = BinSensors::percent(i);
    }
  } else {
    Serial.printf("[FB] kirim kapasitas gagal: %s\n", firebase.lastError().c_str());
  }
}

void handleCommandJson(const String &body) {
  if (body == "null" || body.length() == 0) return;
  JsonDocument doc;
  if (deserializeJson(doc, body)) return;

  const char *status = doc["status"] | "";
  const char *command = doc["command"] | "";
  const uint64_t issuedAt = doc["issued_at"] | (uint64_t)0;
  if (strcmp(status, "PENDING") != 0 || issuedAt == lastHandledIssuedAt) return;
  lastHandledIssuedAt = issuedAt;

  const uint64_t now = epochMs();
  if (now != 0 && now > issuedAt + COMMAND_MAX_AGE_MS) {
    Serial.printf("[CMD] %s diabaikan (kedaluwarsa)\n", command);
    patchCommandStatus("FAILED");
    return;
  }
  if (strcmp(command, "START") != 0 && strcmp(command, "STOP") != 0) {
    patchCommandStatus("FAILED");
    return;
  }
  if (!dev.stmOnline) {
    Serial.printf("[CMD] %s gagal: STM32 tidak terhubung\n", command);
    patchCommandStatus("FAILED");
    return;
  }

  Serial.printf("[CMD] %s dari aplikasi\n", command);
  // "ACK" ditulis dulu; balasan STM32 kemudian menjadi "DONE"/"FAILED".
  patchCommandStatus("ACK");
  strlcpy(pending.code, command, sizeof pending.code);
  pending.active = true;
  pending.sentMs = millis();
  sendToStm("CMD", command);
}

void pollCommand() {
  lastCommandPollMs = millis();
  String body;
  if (firebase.get("commands/latest", body)) {
    handleCommandJson(body);
  } else {
    Serial.printf("[FB] baca perintah gagal: %s\n", firebase.lastError().c_str());
  }
}

void pollSettings() {
  lastSettingsPollMs = millis();
  String body;
  if (!firebase.get("settings", body) || body == "null") return;
  JsonDocument doc;
  if (deserializeJson(doc, body)) return;
  almostFullThreshold = doc["almost_full_threshold"] | almostFullThreshold;
  fullThreshold = doc["full_threshold"] | fullThreshold;
  settingsLoaded = true;
}

void maintainWifi() {
  if (WiFi.status() == WL_CONNECTED) return;
  if (millis() - lastWifiAttemptMs < 10000 && lastWifiAttemptMs != 0) return;
  lastWifiAttemptMs = millis();
  Serial.printf("[WIFI] menyambung ke %s ...\n", WIFI_SSID);
  WiFi.disconnect();
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void printStatus() {
  static uint32_t last = 0;
  if (millis() - last < 10000) return;
  last = millis();
  Serial.printf("[INFO] wifi=%s fb=%s stm=%s sistem=%s konveyor=%s antrean=%u\n",
                WiFi.status() == WL_CONNECTED ? "ok" : "putus",
                firebase.ready() ? "ok" : "belum", dev.stmOnline ? "ok" : "putus",
                dev.systemOn ? "ON" : "OFF", dev.conveyorRunning ? "RUN" : "STOP",
                queueCount);
  for (uint8_t i = 0; i < BinSensors::kCount; i++) {
    Serial.printf("       %-10s jarak=%.1f cm  kapasitas=%.1f%%%s\n", BinSensors::key(i),
                  BinSensors::lastDistanceCm(i), BinSensors::percent(i),
                  BinSensors::valid(i) ? "" : "  (sensor belum terbaca)");
  }
  Serial.printf("       pemilah    vl53l1x=%s item_di_sabuk=%u\n",
                Sorter::tofOk() ? "ok" : "GAGAL", Sorter::itemsInTransit());
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n=== PilahPintar ESP32 ===");

  StmSerial.setRxBufferSize(1024);  // HTTPS bisa memblok ±0,5 dtk
  StmSerial.begin(STM_UART_BAUD, SERIAL_8N1, STM_UART_RX_PIN, STM_UART_TX_PIN);
  pp_reader_init(&stmReader);
  pp_reader_init(&usbReader);
  Serial.println("Perintah: $CAL,ON kalibrasi | $TES,0..2 uji pendorong");
#if DEBUG_INJECT_FROM_USB
  Serial.println("Mode uji: $SIM,ON = STM32 virtual | $SRT,logam,OK,Kaleng = laporan pemilahan");
#endif

  BinSensors::begin();
  Sorter::begin();

  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  maintainWifi();
  configTime(0, 0, "pool.ntp.org", "time.google.com");  // epoch UTC

  firebase.begin(FIREBASE_API_KEY, FIREBASE_DATABASE_URL, FIREBASE_DEVICE_EMAIL,
                 FIREBASE_DEVICE_PASSWORD);
  bootMs = millis();
}

void loop() {
  // 1. Lokal (tetap jalan walau internet putus)
  readSerialInto(StmSerial, stmReader, "STM", false);
  readSerialInto(Serial, usbReader, "USB", true);
#if DEBUG_INJECT_FROM_USB
  updateVirtualStm();
#endif
  Sorter::setConveyorRunning(dev.stmOnline && dev.conveyorRunning);
  Sorter::Report report;
  while (Sorter::popReport(report)) {
    laporkanPemilahan(report.category, report.ok, report.item);
  }
  BinSensors::update();
  checkStmLink();
  printStatus();

  // 2. Jaringan
  maintainWifi();
  if (WiFi.status() != WL_CONNECTED) return;
  if (!firebase.ensureAuth()) {
    static uint32_t lastLog = 0;
    if (millis() - lastLog > 10000) {
      lastLog = millis();
      Serial.printf("[FB] %s\n", firebase.lastError().c_str());
    }
    return;
  }

  // Tunggu sebentar setelah boot agar status STM32 sudah diketahui.
  // Setiap jenis penulisan diberi jeda minimal agar tidak membanjiri server
  // ketika gagal (mis. rules menolak).
  const uint32_t now = millis();
  const bool stmKnown = dev.stmOnline || now - bootMs > STM_LINK_TIMEOUT_MS;
  const uint32_t sinceHeartbeat = now - lastHeartbeatMs;
  if (stmKnown && ((heartbeatDue && sinceHeartbeat >= 1000) ||
                   sinceHeartbeat >= HEARTBEAT_INTERVAL_MS)) {
    sendHeartbeat();
  }
  if ((!settingsLoaded && now - lastSettingsPollMs >= 5000) ||
      now - lastSettingsPollMs >= SETTINGS_POLL_INTERVAL_MS) {
    pollSettings();
  }
  if (queueCount > 0 && now - lastSortAttemptMs >= 2000) flushSortQueue();
  if (now - lastCommandPollMs >= COMMAND_POLL_INTERVAL_MS) pollCommand();
  const uint32_t sinceBins = now - lastBinReportMs;
  if (sinceBins >= 1000) reportBins(sinceBins >= BIN_REPORT_INTERVAL_MS);
}
