/*
 * CONTOH kredensial. Salin file ini menjadi "secrets.h" (di folder yang sama)
 * lalu isi nilainya. secrets.h tidak ikut ter-commit ke git.
 */
#pragma once

// Wi-Fi 2.4 GHz (ESP32 tidak mendukung 5 GHz)
#define WIFI_SSID "nama-wifi"
#define WIFI_PASSWORD "password-wifi"

// Firebase Console -> Project settings -> General -> Web API Key
#define FIREBASE_API_KEY "AIza-ganti-dengan-api-key"

// Firebase Console -> Realtime Database -> URL di bagian atas (tanpa "/" di akhir)
#define FIREBASE_DATABASE_URL "https://nama-proyek-default-rtdb.asia-southeast1.firebasedatabase.app"

// Akun khusus perangkat: Firebase Console -> Authentication -> Users -> Add user
#define FIREBASE_DEVICE_EMAIL "esp32@pilahpintar.id"
#define FIREBASE_DEVICE_PASSWORD "ganti-password-perangkat"
