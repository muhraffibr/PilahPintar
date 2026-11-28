/*
 * ============================================================================
 *  PilahPintar — Uji sensor Capacitive Soil Moisture (ESP32)
 * ============================================================================
 *  Sketch mandiri: cukup board ESP32 + sensor soil moisture. Tanpa Wi-Fi,
 *  Firebase, STM32, atau sensor lain.
 *
 *  Rangkaian (sama dengan firmware utama):
 *    Sensor VCC  -> 3V3 ESP32   (JANGAN 5 V: tegangan keluaran bisa > 3,3 V)
 *    Sensor GND  -> GND
 *    Sensor AOUT -> GPIO 36 (VP)
 *
 *  Buka Serial Monitor 115200 baud. Ketik satu huruf lalu Enter:
 *    k  simpan nilai sekarang sebagai acuan KERING
 *       (sensor di udara, atau menyentuh sampah kering seperti kertas/plastik)
 *    b  simpan nilai sekarang sebagai acuan BASAH
 *       (sensor menyentuh sisa makanan basah / dicelup air sampai garis batas)
 *    r  reset nilai min/maks
 *    p  ganti tampilan teks <-> grafik (Tools -> Serial Plotter)
 *
 *  Setelah k dan b, sketch menyarankan nilai SOIL_WET_RAW untuk config.h.
 *  Makin BASAH, nilai ADC makin KECIL.
 * ============================================================================
 */
#include <Arduino.h>

// Samakan dengan config.h firmware utama.
#define SOIL_PIN 36
#define SOIL_WET_RAW 2200  // <= nilai ini dianggap basah (organik)

constexpr uint8_t kSamples = 16;          // sampel per pembacaan (dirata-rata)
constexpr uint32_t kPrintIntervalMs = 500;
constexpr int kUnstableSpread = 400;      // selisih maks-min dalam 1 pembacaan

int dryRef = 3200;  // acuan awal; ganti dengan perintah k
int wetRef = 1500;  // acuan awal; ganti dengan perintah b
bool dryRecorded = false;
bool wetRecorded = false;
bool plotMode = false;

int sessionMin = 4095;
int sessionMax = 0;
int lastAvg = 0;
uint32_t lastPrintMs = 0;

struct Reading {
  int avg;
  int min;
  int max;
  int mv;
};

Reading readSoil() {
  Reading r{0, 4095, 0, 0};
  long sum = 0;
  for (uint8_t i = 0; i < kSamples; i++) {
    const int v = analogRead(SOIL_PIN);
    sum += v;
    r.min = min(r.min, v);
    r.max = max(r.max, v);
    delayMicroseconds(500);
  }
  r.avg = sum / kSamples;
  r.mv = analogReadMilliVolts(SOIL_PIN);
  return r;
}

// 0% = acuan kering, 100% = acuan basah.
int wetPercent(int raw) {
  if (dryRef == wetRef) return 0;
  const long pct = (long)(dryRef - raw) * 100 / (dryRef - wetRef);
  return constrain(pct, 0, 100);
}

// Pesan jika pembacaan menunjukkan masalah rangkaian; nullptr jika wajar.
const char *diagnose(const Reading &r) {
  if (r.max - r.min > kUnstableSpread) {
    return "TIDAK STABIL: AOUT kemungkinan lepas (pin mengambang)";
  }
  if (r.avg < 150) return "~0 V: AOUT tersambung ke GND, atau sensor tidak dapat daya";
  if (r.avg > 4000) return "mentok 3,3 V: cek kabel, atau VCC sensor diberi 5 V";
  return nullptr;
}

void printSuggestion() {
  if (!dryRecorded || !wetRecorded) return;
  if (wetRef >= dryRef) {
    Serial.println("[SARAN] Acuan basah tidak lebih kecil dari acuan kering. Ulangi k dan b.");
    return;
  }
  const int threshold = (dryRef + wetRef) / 2;
  Serial.printf("[SARAN] kering=%d basah=%d -> isi config.h: #define SOIL_WET_RAW %d\n",
                dryRef, wetRef, threshold);
  if (dryRef - wetRef < 400) {
    Serial.println("[SARAN] Selisih kering-basah kecil (< 400). Pastikan sampah menempel "
                   "di area sensor, bukan hanya ujungnya.");
  }
}

void handleCommand(char c) {
  switch (tolower(c)) {
    case 'k':
      dryRef = lastAvg;
      dryRecorded = true;
      Serial.printf("[CAL] acuan KERING = %d\n", dryRef);
      printSuggestion();
      break;
    case 'b':
      wetRef = lastAvg;
      wetRecorded = true;
      Serial.printf("[CAL] acuan BASAH = %d\n", wetRef);
      printSuggestion();
      break;
    case 'r':
      sessionMin = 4095;
      sessionMax = 0;
      Serial.println("[CAL] min/maks direset");
      break;
    case 'p':
      plotMode = !plotMode;
      if (!plotMode) Serial.println("[CAL] tampilan teks");
      break;
    default:
      break;  // abaikan Enter dan karakter lain
  }
}

void setup() {
  Serial.begin(115200);
  delay(300);
  analogReadResolution(12);                    // 0–4095
  analogSetPinAttenuation(SOIL_PIN, ADC_11db); // rentang ±0–3,1 V

  Serial.println("\n=== Uji Soil Moisture (GPIO 36) ===");
  Serial.printf("Ambang sekarang SOIL_WET_RAW = %d (<= ini dianggap basah)\n", SOIL_WET_RAW);
  Serial.println("Perintah: k = acuan kering | b = acuan basah | r = reset | p = grafik");
}

void loop() {
  while (Serial.available()) handleCommand((char)Serial.read());

  if (millis() - lastPrintMs < kPrintIntervalMs) return;
  lastPrintMs = millis();

  const Reading r = readSoil();
  lastAvg = r.avg;
  sessionMin = min(sessionMin, r.avg);
  sessionMax = max(sessionMax, r.avg);

  if (plotMode) {
    // Format Serial Plotter: label:nilai dipisah koma.
    Serial.printf("raw:%d,ambang:%d,kering:%d,basah:%d\n", r.avg, SOIL_WET_RAW, dryRef, wetRef);
    return;
  }

  const char *problem = diagnose(r);
  const bool wet = r.avg <= SOIL_WET_RAW;
  Serial.printf("raw=%4d (%4d-%4d)  %4d mV  basah %3d%%  %-17s | sesi min=%d maks=%d",
                r.avg, r.min, r.max, r.mv, wetPercent(r.avg),
                wet ? "BASAH -> organik" : "kering", sessionMin, sessionMax);
  if (problem) Serial.printf("  !! %s", problem);
  Serial.println();
}
