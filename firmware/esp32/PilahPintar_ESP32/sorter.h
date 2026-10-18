/*
 * Pemilahan di zona deteksi konveyor bawah: sensor -> klasifikasi -> pendorong.
 *
 * Berjalan sebagai task FreeRTOS sendiri di core 0, sehingga tetap tepat waktu
 * walaupun loop() sedang menunggu HTTPS ke Firebase (bisa ±0,5–1 detik).
 *
 * Alur satu item:
 *   1. Item masuk zona sensor: salah satu sensor aktif (VL53L1X, induktif,
 *      kapasitif, atau soil moisture basah).
 *   2. Selama di zona, ciri dikumpulkan: tinggi & pantulan maksimum, induktif,
 *      kapasitif, soil moisture terendah.
 *   3. Semua sensor tidak aktif selama ITEM_GAP_MS -> item diklasifikasi
 *      (sort_rules.c).
 *   4. Pendorong yang sesuai digerakkan saat item lewat di depannya:
 *        waktu = tengah item di zona + jarak pendorong / kecepatan sabuk.
 *      Anorganik tidak didorong; jatuh di ujung sabuk.
 *   5. Hasilnya dikirim ke loop() lewat antrean -> laporkanPemilahan().
 */
#pragma once

#include <Arduino.h>

namespace Sorter {

struct Report {
  char category[12];
  char item[24];
  bool ok;
};

void begin();

// Status konveyor dari STM32 (dipanggil loop()). Saat konveyor berhenti, item
// yang masih di sabuk dilaporkan gagal dan semua pendorong kembali ke posisi awal.
void setConveyorRunning(bool running);

// Ambil satu hasil pemilahan; false jika antrean kosong.
bool popReport(Report &out);

// Mode kalibrasi: cetak nilai sensor mentah tiap 250 ms dan baris CSV per item.
// Item tetap dideteksi walaupun konveyor berhenti (gerakkan sampah dengan tangan).
void setCalibration(bool on);

// Gerakkan satu pendorong sekali: 0 organik, 1 logam, 2 recyclable.
void testPusher(uint8_t index);

bool tofOk();
uint8_t itemsInTransit();

}  // namespace Sorter
