/*
 * Pembacaan kapasitas 4 tempat sampah dengan sensor ultrasonik.
 * Non-blocking per sensor: update() mengukur satu sensor setiap
 * BIN_MEASURE_INTERVAL_MS (median 3 sampel; perubahan kecil diratakan,
 * perubahan >= BIN_JUMP_PCT langsung dipakai).
 */
#pragma once

#include <Arduino.h>

namespace BinSensors {

constexpr uint8_t kCount = 4;

void begin();
void update();

// Kunci kategori, sama dengan aplikasi & database: organik, recyclable, logam, anorganik.
const char *key(uint8_t i);

// false jika sensor belum pernah / berkali-kali gagal membaca (tidak dikirim).
bool valid(uint8_t i);

// 0–100 %.
float percent(uint8_t i);

// Jarak terakhir (cm) untuk kalibrasi lewat Serial Monitor; -1 jika gagal.
float lastDistanceCm(uint8_t i);

}  // namespace BinSensors
