/*
 * Konfigurasi firmware ESP32 PilahPintar.
 * Board: ESP32 klasik (ESP32-DevKitC V4, modul WROOM-32U).
 * Sesuaikan pin, ukuran tempat sampah, dan geometri konveyor dengan alat Anda.
 *
 * Batasan pin ESP32 klasik:
 *   - GPIO 6–11 dipakai flash: JANGAN dipakai.
 *   - GPIO 34, 35, 36, 39 hanya input dan TIDAK punya pull-up internal.
 *   - GPIO 0, 2, 5, 12, 15 adalah pin strapping (memengaruhi boot): dibiarkan kosong.
 *   - ADC2 tidak bisa dibaca saat Wi-Fi aktif, jadi sensor analog memakai ADC1 (GPIO 32–39).
 */
#pragma once

// uint64 untuk timestamp milidetik di ArduinoJson (harus sebelum include ArduinoJson).
#define ARDUINOJSON_USE_LONG_LONG 1

#if __has_include("secrets.h")
#include "secrets.h"
#else
#warning "secrets.h belum ada: salin secrets.example.h menjadi secrets.h lalu isi Wi-Fi & Firebase."
#include "secrets.example.h"
#endif

// ---------------------------------------------------------------------------
// UART2 ke STM32 (silang: TX ESP32 -> RX STM32, RX ESP32 <- TX STM32, GND bersama)
// ---------------------------------------------------------------------------
#define STM_UART_RX_PIN 16  // ke PA2 (TX) STM32
#define STM_UART_TX_PIN 17  // ke PA3 (RX) STM32
#define STM_UART_BAUD 115200

// ---------------------------------------------------------------------------
// Sensor ultrasonik HY-SRF05 / HC-SR04 — satu per tempat sampah, VCC 5 V.
// PENTING: pin ECHO bertegangan 5 V. Pakai pembagi tegangan
// (ECHO -> 1 kΩ -> pin ESP32 -> 2 kΩ -> GND).
// ---------------------------------------------------------------------------
#define BIN_ORGANIK_TRIG 4
#define BIN_ORGANIK_ECHO 18
#define BIN_RECYCLABLE_TRIG 13
#define BIN_RECYCLABLE_ECHO 19
#define BIN_LOGAM_TRIG 14
#define BIN_LOGAM_ECHO 32
#define BIN_ANORGANIK_TRIG 23
#define BIN_ANORGANIK_ECHO 33

// Jarak sensor ke DASAR tempat sampah saat kosong, dan ke GARIS PENUH (cm).
// Kapasitas = (kosong - jarak) / (kosong - penuh) x 100%.
#define BIN_EMPTY_DISTANCE_CM 40.0f
#define BIN_FULL_DISTANCE_CM 5.0f

// ---------------------------------------------------------------------------
// Zona deteksi di konveyor bawah (cara kalibrasi: firmware/README.md bagian 6)
// ---------------------------------------------------------------------------
// Sharp IR GP2Y0A21YK0F (VCC 5 V, output analog 0,4–3,1 V aman untuk ADC).
// Pemasangan diatur SHARP_SIDE_MOUNT di bawah. Pasang kapasitor 10 µF
// di dekat VCC–GND sensor (arus LED-nya berdenyut dan membuat output berisik).
#define SHARP_PIN 39  // SENSOR_VN (ADC1)

// LDR + laser pointer (deteksi KERTAS di stasiun recyclable): laser dan LDR
// berdampingan di dinding sisi sensor, setinggi ±15 mm (di bawah sinar Sharp IR),
// sedikit sebelum servo recyclable. Kertas putih memantulkan laser kuat ke LDR.
// Modul LDR (LM393) VCC 3V3, pakai output digital DO; setel potensiometer saat $CAL,ON
// agar kertas = terang, sedangkan kresek/plastik gelap/sabuk kosong = gelap.
#define USE_LDR 1
#define LDR_PIN 21
#define LDR_BRIGHT_LEVEL LOW  // level DO saat pantulan kuat (modul umum: LOW)

// Raindrop sensor module TIDAK dipasang. Biarkan 0 (GPIO 22 diabaikan).
// Isi 1 jika modul raindrop (VCC 3V3, DO LOW saat basah) ditambahkan.
#define USE_RAINDROP 0
#define RAINDROP_PIN 22
#define RAINDROP_WET_LEVEL LOW

// Proximity 12 V lewat optocoupler PC817 + resistor pull-up 10 kΩ ke 3V3.
// Output PC817 LOW = ada benda. Pull-up eksternal WAJIB (GPIO 34/35 tanpa pull-up).
#define INDUCTIVE_PIN 34   // LJ12A3-4-Z/BX (NPN, jarak deteksi 4 mm)
// Proximity kapasitif LJC18A3-H-Z/BY (PNP). Isi 0 jika sensor dilepas:
// GPIO 35 yang mengambang membaca nilai acak.
#define USE_CAPACITIVE 1
#define CAPACITIVE_PIN 35

// Capacitive soil moisture, VCC 3V3. Makin basah, nilai ADC makin KECIL.
#define SOIL_PIN 36  // SENSOR_VP (ADC1)

// Sinyal servo crank slider. Daya servo dari LM2596 kedua (6 V), GND disatukan.
#define SERVO_ORGANIK_PIN 25
#define SERVO_LOGAM_PIN 26
#define SERVO_RECYCLABLE_PIN 27

// --- Geometri konveyor bawah (ukur dengan penggaris & stopwatch) ---
// Kecepatan sabuk (mm/detik): tandai sabuk, ukur jarak tempuhnya dalam 10 detik.
// Ukur ulang setiap kali MOTOR_B_DUTY di firmware STM32 diubah.
#define BELT_SPEED_MM_S 100.0f
// Jarak dari titik tengah zona sensor ke titik tengah tiap pendorong (mm).
// Urutan sepanjang sabuk: logam, organik, recyclable, lalu ujung sabuk.
#define PUSHER_LOGAM_DISTANCE_MM 150
#define PUSHER_ORGANIK_DISTANCE_MM 300
#define PUSHER_RECYCLABLE_DISTANCE_MM 450
// Jarak ke ujung sabuk: sampah anorganik tidak didorong, jatuh di sini.
#define BELT_END_DISTANCE_MM 600

// --- Mode pemilahan ---
// 1 = SATU SENSOR, SATU SERVO. Setiap sensor dipasang tepat sebelum servonya;
//     begitu sensor itu mendeteksi sampah, servonya mendorong:
//       stasiun 1  induktif                    -> servo logam       (GPIO 26)
//       stasiun 2  soil moisture / kapasitif   -> servo organik     (GPIO 25)
//       stasiun 3  Sharp IR (botol) / LDR terang (kertas) -> servo recyclable (GPIO 27)
//       stasiun 4  ujung sabuk, tanpa sensor: anorganik & sampah lain yang
//                  tidak terdeteksi stasiun 1–3
//     Benda rendah yang lewat Sharp IR tanpa didorong dicatat anorganik dan
//     jatuh di ujung sabuk. Urutan stasiun di sabuk harus seperti di atas:
//     logam paling depan, supaya kaleng sudah terdorong sebelum sampai ke
//     sensor kapasitif dan sensor kelembapan di stasiun organik (kaleng memicu
//     kapasitif, dan sering basah oleh sisa minuman).
// 0 = semua sensor di satu zona, kategori ditentukan aturan sort_rules.c,
//     servo dijadwalkan dengan PUSHER_*_DISTANCE_MM.
#define SORT_MODE_PER_SENSOR 1
// Jarak dari sensor stasiun ke tengah servonya (mm), searah gerak sabuk.
// 0 = sensor tepat di depan pendorong (servo langsung bergerak saat terdeteksi).
#define STATION_ORGANIK_SENSOR_TO_PUSHER_MM 40
#define STATION_LOGAM_SENSOR_TO_PUSHER_MM 40
#define STATION_RECYCLABLE_SENSOR_TO_PUSHER_MM 40
// Sensor harus aktif minimal selama ini agar dianggap ada sampah (anti derau).
#define STATION_MIN_ACTIVE_MS 20
// Sensor tambahan untuk stasiun organik (1 = ikut memicu servo organik).
#define STATION_ORGANIK_USE_RAINDROP 1
// Kapasitif menangkap organik yang kurang basah untuk soil moisture. Setel
// potensiometer sensor kapasitif agar botol plastik kosong TIDAK memicunya
// (botol harus lolos ke Sharp IR). Butuh USE_CAPACITIVE 1.
#define STATION_ORGANIK_USE_CAPACITIVE 1
// 1 = LDR + laser terang (kertas) ikut memicu servo recyclable. Butuh USE_LDR 1.
#define STATION_RECYCLABLE_USE_LDR 1

// --- Sharp IR ---
// 1 = DIPASANG DI SAMPING (dinding sisi sensor), menghadap menyeberangi sabuk,
//     setinggi BOTTLE_MIN_HEIGHT_MM (±45 mm) di atas sabuk dan MUNDUR ±10 cm
//     dari permukaan dalam dinding (di dalam kotak berlubang), karena
//     GP2Y0A21 tidak akurat di bawah 10 cm. Hanya benda yang lebih tinggi dari
//     posisi sensor yang memotong sinarnya -> dianggap botol (recyclable).
//     Benda rendah lewat di bawah sinar: tidak terdeteksi, tidak tercatat.
// 0 = dipasang di atas sabuk menghadap ke bawah dan mengukur tinggi benda.
#define SHARP_SIDE_MOUNT 1
// Mode samping: jarak terbaca saat tidak ada benda (ke dinding seberang), mm.
// Isi dengan nilai "sharp=" saat $CAL,ON dan sabuk kosong. Harus <= 800 mm;
// jika dinding seberang lebih jauh, pasang pelat pemantul di seberang sensor.
#define SHARP_SIDE_EMPTY_DISTANCE_MM 300
// Mode samping: sinar dianggap terpotong jika jarak lebih pendek dari
// SHARP_SIDE_EMPTY_DISTANCE_MM dikurangi nilai ini (mm), untuk meredam derau.
#define SHARP_SIDE_TRIGGER_MM 40
// Mode atas: jarak sensor ke permukaan sabuk kosong (mm). Baca nilai "sharp=" saat $CAL,ON.
// GP2Y0A21 hanya akurat 100–800 mm: benda tertinggi harus tetap >= 100 mm dari sensor.
#define SHARP_BELT_DISTANCE_MM 200
// Benda dianggap ada jika lebih tinggi dari ini di atas sabuk (mm). Sharp IR
// lebih berisik daripada sensor ToF, jadi batasnya lebih besar.
#define SHARP_MIN_HEIGHT_MM 15
// Konversi tegangan -> jarak: jarak_cm = A * V^-B (kurva datasheet GP2Y0A21).
// Bisa disesuaikan dari pengukuran dengan penggaris saat $CAL,ON.
#define SHARP_CURVE_A 27.86f
#define SHARP_CURVE_B 1.15f

// --- Deteksi satu item ---
// Item selesai lewat jika semua sensor tidak aktif selama ini (ms).
// Jarak antar sampah di sabuk harus lebih panjang dari zona sensor + jarak ini.
#define ITEM_GAP_MS 150
// Sensor yang aktif terus lebih lama dari ini dianggap tersangkut dan diabaikan
// sampai normal kembali.
#define ITEM_MAX_MS 5000
// Item dianggap gagal jika jadwal dorongnya sudah lewat lebih dari ini (ms).
#define PUSH_LATE_TOLERANCE_MS 150

// --- Aturan klasifikasi (sort_rules.h). WAJIB dikalibrasi dengan $CAL,ON ---
// Soil moisture <= nilai ini dianggap basah (organik).
#define SOIL_WET_RAW 2200
// 1 = benda non-logam yang memicu sensor kapasitif dianggap organik
// (hanya berpengaruh jika USE_CAPACITIVE 1).
#define CAPACITIVE_MEANS_ORGANIC 1
// Benda setinggi ini atau lebih dianggap botol (recyclable).
#define BOTTLE_MIN_HEIGHT_MM 45
// Aturan berbasis LDR + laser (nyalakan setelah potensiometer LDR dikalibrasi):
// 1 = benda tinggi yang memantulkan laser kuat dianggap styrofoam (anorganik).
#define STYROFOAM_BY_LDR 0
// 1 = benda pendek (<= PAPER_MAX_HEIGHT_MM) yang memantulkan laser kuat dianggap kertas.
#define PAPER_BY_LDR 0
#define PAPER_MAX_HEIGHT_MM 25

// --- Servo crank slider (MG996R) ---
#define SERVO_HOME_DEG 0     // pendorong mundur penuh
#define SERVO_PUSH_DEG 180   // pendorong maju penuh
#define SERVO_PUSH_MS 500    // waktu minimal fase maju
#define SERVO_RETURN_MS 500  // waktu minimal fase mundur
// Kecepatan putar servo (derajat/detik). 0 = secepat servo (±0,5 dtk untuk 180°).
// Turunkan (mis. 360) jika sampah terlempar terlalu keras.
#define SERVO_SPEED_DEG_S 0
#define SERVO_MIN_US 500     // lebar pulsa untuk 0°
#define SERVO_MAX_US 2400    // lebar pulsa untuk 180°

// Servo dinyalakan bergiliran agar arus puncak tidak melebihi kemampuan LM2596:
//  - Satu servo hanya diberi sinyal PWM saat pendorongnya bekerja, lalu
//    dilepas lagi setelah kembali ke posisi awal (tidak menarik arus tahan).
//  - Saat ESP32 menyala, servo dibawa ke posisi awal satu per satu.
//  - Dua servo tidak pernah mulai bergerak pada saat yang sama; servo kedua
//    menunggu minimal SERVO_START_GAP_MS (harus < PUSH_LATE_TOLERANCE_MS).
// Pemetaan sensor -> pendorong (lihat sort_rules.c):
//   induktif -> logam | soil moisture basah / kapasitif -> organik |
//   Sharp IR benda tinggi -> recyclable | tidak ada yang cocok -> anorganik (ujung sabuk)
#define SERVO_DETACH_WHEN_IDLE 1
#define SERVO_STARTUP_STAGGER_MS 600  // waktu tiap servo menuju posisi awal saat boot
#define SERVO_START_GAP_MS 120

// ---------------------------------------------------------------------------
// Task pemilah (FreeRTOS)
//   Wi-Fi dan lwIP Arduino-ESP32 berjalan di core 0. loop() (HTTPS ke Firebase,
//   ultrasonik) berjalan di core 1 dengan prioritas 1. Task pemilah dipasang di
//   core 1 dengan prioritas 20: di atas loop() dan di atas task
//   "arduino_events" (prioritas 19, juga di core 1), sehingga jaringan tidak
//   bisa menunda tick pemilah 5 ms.
// SORTER_JITTER_LOG 1 = cetak baris CSV "JIT" tiap SORTER_JITTER_LOG_MS berisi
//   periode terburuk, keterlambatan terburuk, dan waktu eksekusi tick terburuk.
// ---------------------------------------------------------------------------
#define SORTER_TASK_CORE 1
#define SORTER_TASK_PRIORITY 20
#define SORTER_JITTER_LOG 1
#define SORTER_JITTER_LOG_MS 10000

// ---------------------------------------------------------------------------
// Interval (ms)
// ---------------------------------------------------------------------------
#define HEARTBEAT_INTERVAL_MS 5000      // system_status.last_updated (app: offline jika > 15 dtk)
#define COMMAND_POLL_INTERVAL_MS 1000   // cek commands/latest
#define BIN_MEASURE_INTERVAL_MS 150     // ukur 1 sensor tiap 150 ms (4 sensor = 0,6 dtk)
#define BIN_REPORT_INTERVAL_MS 10000    // kirim kapasitas minimal tiap 10 dtk
#define BIN_REPORT_DELTA_PCT 2.0f       // atau segera jika berubah >= 2%
#define BIN_JUMP_PCT 5.0f               // perubahan >= ini langsung dipakai tanpa perataan
#define SETTINGS_POLL_INTERVAL_MS 60000 // baca threshold dari aplikasi
#define STM_PING_INTERVAL_MS 1000       // ESP32 -> STM32 "$PING"
#define STM_LINK_TIMEOUT_MS 3000        // STM32 dianggap putus jika tidak ada pesan
#define COMMAND_ACK_TIMEOUT_MS 3000     // tunggu $ACK dari STM32
#define COMMAND_MAX_AGE_MS 30000        // abaikan perintah aplikasi yang lebih tua

// 1 = baris yang diketik di Serial Monitor (USB) diproses seolah dari STM32.
// Berguna untuk menguji ESP32 + aplikasi sebelum STM32 tersambung.
#define DEBUG_INJECT_FROM_USB 1

// ---------------------------------------------------------------------------
// Mode uji jaringan (data paper): cukup board ESP32, tanpa sensor/servo/STM32.
//   - Pemilah (sorter.cpp) dimatikan; kapasitas tempat sampah disimulasikan.
//   - STM32 virtual langsung aktif (sama dengan mengetik $SIM,ON).
//   - Saat konveyor (virtual) berjalan, satu event pemilahan "TEST #n" dibuat
//     setiap TEST_EVENT_INTERVAL_MS.
//   - Setiap request HTTPS, perintah, event, dan status Wi-Fi dicatat sebagai
//     baris CSV (NET, CMD, CMDDONE, SRTQ, SRTOK, SRTDROP, WIFI).
// Rekam & olah lognya dengan tools/network_test (lihat README di folder itu).
// ---------------------------------------------------------------------------
#ifndef NETWORK_TEST_MODE
#define NETWORK_TEST_MODE 1
#endif
#define TEST_EVENT_INTERVAL_MS 5000
#ifndef NET_LOG
#define NET_LOG NETWORK_TEST_MODE  // 1 = cetak baris CSV pengujian
#endif
