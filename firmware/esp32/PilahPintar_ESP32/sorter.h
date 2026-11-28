/*
 * Pemilahan di zona deteksi konveyor bawah: sensor -> klasifikasi -> pendorong.
 *
 * Berjalan sebagai task FreeRTOS sendiri di core 0, sehingga tetap tepat waktu
 * walaupun loop() sedang menunggu HTTPS ke Firebase (bisa ±0,5–1 detik).
 *
 * Mode SATU SENSOR, SATU SERVO (SORT_MODE_PER_SENSOR 1, bawaan):
 *   Setiap servo punya sensor sendiri yang dipasang tepat sebelum servonya.
 *     induktif (paling depan)               -> servo logam
 *     soil moisture / kapasitif             -> servo organik
 *     Sharp IR (botol) / LDR + laser (kertas) -> servo recyclable
 *     ujung sabuk (tanpa sensor)            -> anorganik & lainnya
 *   Begitu sensor stasiun aktif >= STATION_MIN_ACTIVE_MS (Sharp IR: tinggi
 *   >= BOTTLE_MIN_HEIGHT_MM), servonya dijadwalkan:
 *     waktu = saat terdeteksi + jarak sensor ke servo / kecepatan sabuk.
 *   Benda rendah yang lewat Sharp IR tanpa didorong dilaporkan anorganik.
 *   Servo tetap bergerak bergiliran (lihat config.h).
 *
 * Mode zona gabungan (SORT_MODE_PER_SENSOR 0), alur satu item:
 *   1. Item masuk zona sensor: salah satu sensor aktif (Sharp IR melihat benda,
 *      induktif, kapasitif, soil moisture basah, atau raindrop basah).
 *   2. Selama di zona, ciri dikumpulkan: tinggi maksimum (Sharp IR), pantulan
 *      laser (LDR), induktif, kapasitif, soil moisture terendah, raindrop.
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

bool distanceSensorOk();  // Sharp IR memberi pembacaan valid
// Sensor pemilah dibaca? Bawaan mati; aktif hanya saat konveyor berjalan
// (setelah START) atau mode kalibrasi $CAL,ON.
bool sensorsActive();
uint8_t itemsInTransit();

// Statistik waktu task pemilah sejak pemanggilan sebelumnya (lalu direset).
// Periode ideal 5000 us; late = periode - 5000 us.
struct TimingStats {
  uint32_t ticks;        // jumlah tick dalam jendela
  uint32_t maxPeriodUs;  // jarak terlama antar awal tick
  int32_t maxLateUs;     // keterlambatan terburuk terhadap periode 5 ms
  uint32_t maxExecUs;    // waktu eksekusi tick() terlama
  uint32_t lateOver1ms;  // jumlah tick yang terlambat > 1 ms
};
bool takeTimingStats(TimingStats &out);  // false jika task belum berjalan

}  // namespace Sorter
