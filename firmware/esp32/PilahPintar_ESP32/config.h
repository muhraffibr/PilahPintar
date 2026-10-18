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
// VL53L1X (I2C, VIN ke 3V3), dipasang ±15 cm di atas sabuk menghadap ke bawah.
#define TOF_SDA_PIN 21
#define TOF_SCL_PIN 22

// Proximity 12 V lewat optocoupler PC817 + resistor pull-up 10 kΩ ke 3V3.
// Output PC817 LOW = ada benda. Pull-up eksternal WAJIB (GPIO 34/35 tanpa pull-up).
#define INDUCTIVE_PIN 34   // LJ18A3-8-Z/BX (NPN)
#define CAPACITIVE_PIN 35  // LJC18A3-H-Z/BY (PNP)

// Capacitive soil moisture, VCC 3V3. Makin basah, nilai ADC makin KECIL.
#define SOIL_PIN 36  // SENSOR_VP (ADC1)

// Sinyal servo crank slider. Daya servo dari XL4015 6 V, GND disatukan.
#define SERVO_ORGANIK_PIN 25
#define SERVO_LOGAM_PIN 26
#define SERVO_RECYCLABLE_PIN 27

// --- Geometri konveyor bawah (ukur dengan penggaris & stopwatch) ---
// Kecepatan sabuk (mm/detik): tandai sabuk, ukur jarak tempuhnya dalam 10 detik.
// Ukur ulang setiap kali MOTOR_B_DUTY di firmware STM32 diubah.
#define BELT_SPEED_MM_S 100.0f
// Jarak dari titik tengah zona sensor ke titik tengah tiap pendorong (mm).
// Urutan sepanjang sabuk: organik, logam, recyclable, lalu ujung sabuk.
#define PUSHER_ORGANIK_DISTANCE_MM 150
#define PUSHER_LOGAM_DISTANCE_MM 300
#define PUSHER_RECYCLABLE_DISTANCE_MM 450
// Jarak ke ujung sabuk: sampah anorganik tidak didorong, jatuh di sini.
#define BELT_END_DISTANCE_MM 600

// --- VL53L1X ---
// Jarak sensor ke permukaan sabuk kosong (mm). Baca nilai "tof=" saat $CAL,ON.
#define TOF_BELT_DISTANCE_MM 150
// Benda dianggap ada jika lebih tinggi dari ini di atas sabuk (mm).
#define TOF_MIN_HEIGHT_MM 8

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
// 1 = benda non-logam yang memicu sensor kapasitif dianggap organik.
#define CAPACITIVE_MEANS_ORGANIC 1
// Benda setinggi ini atau lebih dianggap botol (recyclable).
#define BOTTLE_MIN_HEIGHT_MM 45
// Benda tinggi dengan pantulan >= nilai ini dianggap styrofoam (anorganik). 0 = mati.
#define STYROFOAM_MIN_SIGNAL_MCPS 0.0f
// Benda pendek dengan pantulan >= PAPER_MIN_SIGNAL dianggap kertas (recyclable). 0 = mati.
#define PAPER_MAX_HEIGHT_MM 25
#define PAPER_MIN_SIGNAL_MCPS 0.0f

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
