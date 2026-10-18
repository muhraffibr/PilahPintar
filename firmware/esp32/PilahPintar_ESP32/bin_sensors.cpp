#include "config.h"

#include "bin_sensors.h"

namespace BinSensors {
namespace {

struct Bin {
  const char *key;
  uint8_t trig;
  uint8_t echo;
  float percent;
  float lastCm;
  uint8_t failures;
  bool valid;
};

Bin bins[kCount] = {
    {"organik", BIN_ORGANIK_TRIG, BIN_ORGANIK_ECHO, 0, -1, 0, false},
    {"recyclable", BIN_RECYCLABLE_TRIG, BIN_RECYCLABLE_ECHO, 0, -1, 0, false},
    {"logam", BIN_LOGAM_TRIG, BIN_LOGAM_ECHO, 0, -1, 0, false},
    {"anorganik", BIN_ANORGANIK_TRIG, BIN_ANORGANIK_ECHO, 0, -1, 0, false},
};

uint8_t nextIndex = 0;
uint32_t lastMeasureMs = 0;

// Satu pengukuran (cm), -1 jika tidak ada pantulan.
float pingCm(uint8_t trig, uint8_t echo) {
  digitalWrite(trig, LOW);
  delayMicroseconds(2);
  digitalWrite(trig, HIGH);
  delayMicroseconds(10);
  digitalWrite(trig, LOW);
  const unsigned long us = pulseIn(echo, HIGH, 12000UL);  // maks ±2 m, cukup untuk tempat sampah
  if (us == 0) return -1;
  return us * 0.0343f / 2.0f;
}

float median3(float a, float b, float c) {
  if (a > b) { float t = a; a = b; b = t; }
  if (b > c) { float t = b; b = c; c = t; }
  if (a > b) { float t = a; a = b; b = t; }
  return b;
}

void measure(Bin &bin) {
  float s[3];
  uint8_t ok = 0;
  for (uint8_t i = 0; i < 3; i++) {
    const float cm = pingCm(bin.trig, bin.echo);
    if (cm > 0) s[ok++] = cm;
    delay(15);  // hindari gema dari pengukuran sebelumnya
  }
  if (ok == 0) {
    bin.lastCm = -1;
    if (++bin.failures >= 3) bin.valid = false;
    return;
  }
  const float cm = ok == 3 ? median3(s[0], s[1], s[2]) : s[0];
  bin.lastCm = cm;
  bin.failures = 0;

  float pct = (BIN_EMPTY_DISTANCE_CM - cm) /
              (BIN_EMPTY_DISTANCE_CM - BIN_FULL_DISTANCE_CM) * 100.0f;
  pct = constrain(pct, 0.0f, 100.0f);

  // Perubahan besar (sampah dibuang/dikosongkan) langsung dipakai; perubahan
  // kecil diratakan agar angka tidak "loncat" karena noise.
  if (!bin.valid || fabsf(pct - bin.percent) >= BIN_JUMP_PCT) {
    bin.percent = pct;
  } else {
    bin.percent = bin.percent * 0.6f + pct * 0.4f;
  }
  bin.valid = true;
}

}  // namespace

void begin() {
  for (auto &bin : bins) {
    pinMode(bin.trig, OUTPUT);
    digitalWrite(bin.trig, LOW);
    pinMode(bin.echo, INPUT);
  }
}

void update() {
  if (millis() - lastMeasureMs < BIN_MEASURE_INTERVAL_MS) return;
  lastMeasureMs = millis();
  measure(bins[nextIndex]);
  nextIndex = (nextIndex + 1) % kCount;
}

const char *key(uint8_t i) { return bins[i].key; }
bool valid(uint8_t i) { return bins[i].valid; }
float percent(uint8_t i) { return bins[i].percent; }
float lastDistanceCm(uint8_t i) { return bins[i].lastCm; }

}  // namespace BinSensors
