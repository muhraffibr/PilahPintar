/*
 * Konfigurasi firmware STM32 PilahPintar (STM32F411CEU6 "Black Pill").
 * Sesuaikan dengan driver motor & rangkaian Anda.
 */
#pragma once

// ---------------------------------------------------------------------------
// UART ke ESP32 — USART2 (PA2 = TX, PA3 = RX). GND harus tersambung.
// (Serial bawaan Black Pill = USART1 PA9/PA10, tetap bebas untuk debug.)
// ---------------------------------------------------------------------------
#define PIN_ESP_RX PA3  // dari TX ESP32 (GPIO17)
#define PIN_ESP_TX PA2  // ke RX ESP32 (GPIO16)
#define ESP_BAUD 115200

// ---------------------------------------------------------------------------
// Dua motor konveyor lewat satu L298N.
//   Motor A = konveyor atas (singulation), Motor B = konveyor bawah (sensor).
//   Lepas jumper ENA/ENB di modul L298N agar PWM bisa mengatur kecepatan.
//   PWM -> ENA/ENB, IN -> arah putar. Isi -1 jika driver tidak memakai pin arah.
//   PB6 dan PB9 sama-sama TIM4, jadi frekuensi PWM keduanya sama.
// ---------------------------------------------------------------------------
#define PIN_MOTOR_A_PWM PB6   // ENA
#define PIN_MOTOR_A_IN1 PB7   // IN1
#define PIN_MOTOR_A_IN2 PB8   // IN2
#define PIN_MOTOR_B_PWM PB9   // ENB
#define PIN_MOTOR_B_IN1 PB13  // IN3
#define PIN_MOTOR_B_IN2 PB14  // IN4
#define MOTOR_PWM_FREQ_HZ 20000  // di atas pendengaran, motor tidak berdengung
// Kecepatan kerja 0–255. Konveyor bawah dibuat lebih cepat dari konveyor atas
// supaya jarak antar sampah bertambah saat pindah sabuk (membantu singulation).
// Jika MOTOR_B_DUTY diubah, ukur ulang BELT_SPEED_MM_S di config.h ESP32.
#define MOTOR_A_DUTY 180
#define MOTOR_B_DUTY 220
#define MOTOR_RAMP_MS 800  // waktu naik dari 0 ke kecepatan kerja (soft start)

// ---------------------------------------------------------------------------
// Tombol darurat: kontak NC kedua tombol E-stop antara PB12 dan GND.
//   Tertutup = LOW (aman); ditekan atau kabel putus = HIGH (berhenti).
//   Kontak NC pertama memutus +12 V aktuator secara langsung (lihat README).
// Setelah tombol dilepas, konveyor tetap berhenti sampai ada START baru
// (reset manual). Selama tombol belum terpasang, START ditolak
// ($NAK,START,ESTOP); untuk uji di meja, sambungkan PB12 ke GND.
// ---------------------------------------------------------------------------
#define USE_ESTOP 1
#define PIN_ESTOP PB12
#define ESTOP_DEBOUNCE_MS 20  // abaikan gangguan listrik sesaat pada kabel tombol

// ---------------------------------------------------------------------------
// Sensor arus motor (opsional), mis. ACS712 di pin analog.
// Konveyor berhenti dengan kode gangguan 1 jika nilai ADC melewati batas
// selama CURRENT_TRIP_MS.
// ---------------------------------------------------------------------------
#define USE_CURRENT_SENSE 0
#define PIN_CURRENT PA1
#define CURRENT_LIMIT_RAW 3000  // ADC 12-bit (0–4095); kalibrasi di alat Anda
#define CURRENT_TRIP_MS 300

// ---------------------------------------------------------------------------
// Keamanan & status
// ---------------------------------------------------------------------------
// Konveyor berhenti (gangguan 4) jika tidak ada pesan dari ESP32 selama ini.
// ESP32 mengirim "$PING" tiap 1 dtk. Isi 0 untuk menonaktifkan.
#define LINK_TIMEOUT_MS 5000
#define STATUS_INTERVAL_MS 1000  // kirim "$STS" ke ESP32
#define PIN_LED PC13             // LED biru Black Pill (aktif LOW)
