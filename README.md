# PilahPintar — Monitoring Pemilah Sampah Otomatis

Aplikasi mobile (Flutter + Firebase) untuk memantau dan mengendalikan sistem
pemilah sampah otomatis berbasis IoT di **SMA Negeri 1 Bandung**. Ini prototype
akademik untuk proyek Teknik Komputer.

Aplikasi **tidak punya login, signup, maupun akun pengguna**. Saat dibuka,
aplikasi langsung masuk ke Dashboard.

```
ESP32 (sensor ultrasonik, IoT) ──► Firebase Realtime Database ──► Aplikasi
STM32F411CEU6 (konveyor) ◄── ESP32 ◄── commands/latest ◄── tombol START/STOP
```

## Fitur

| PRD | Implementasi |
|---|---|
| §5 Dashboard | Status sistem (ON/OFF, Connected/Disconnected, RUNNING/STOPPED), kapasitas 4 tempat sampah dengan status Normal/Hampir Penuh/Penuh, tombol START/STOP dengan dialog konfirmasi, statistik hari ini, donut chart dan bar chart, aktivitas terbaru |
| §6 Riwayat | Filter Hari ini / 7 hari / 30 hari / Custom date, grafik volume per kategori, ringkasan total, daftar aktivitas. Ketuk tanggal untuk membuka **Detail Riwayat**, ketuk baris untuk detail satu kejadian |
| §7 Pengaturan | Notifikasi on/off, Almost Full Threshold dan Full Threshold, info sistem, info aplikasi. Tidak ada menu login/logout/profil |
| §8 Notifikasi | Panel notifikasi dengan badge, tandai dibaca / tandai semua dibaca, push notification lokal + snackbar di dalam aplikasi |
| §10 Real-time | Semua data berupa stream. Saat koneksi putus muncul banner `Offline — Last update: 12:43:21` dan nilai ditandai sebagai data terakhir |
| §13 State | Loading, Online, Offline, System OFF, Warning, Full, Error |
| §14 Empty state | "Belum ada data pemilahan.", "Tidak ada notifikasi baru.", "Menunggu koneksi ke perangkat." |
| §15 Prototype data | Mode simulasi (default) dengan data 30 hari yang realistis dan data live yang terus berubah |

## Pasang di HP (APK siap pakai)

[`apk/PilahPintar-firebase-arm64.apk`](apk/PilahPintar-firebase-arm64.apk)
sudah terhubung ke proyek Firebase `espdatabase-94f5b`. APK ini untuk HP
Android 7.0 ke atas (64-bit).

- Unduh file APK ke HP, buka, lalu izinkan **Instal aplikasi tidak dikenal**.
- Jika Play Protect memperingatkan, pilih **Detail lainnya → Tetap instal**.
  Peringatan ini muncul karena APK ditandatangani dengan kunci pengembangan.
- Sebelum ESP32 menyala, Dashboard menampilkan "Menunggu koneksi ke
  perangkat.".

Untuk membuat ulang APK setelah kode diubah, jalankan
`.\tools\build_apk.ps1 -Firebase`. Skrip ini otomatis menimpa file di folder
`apk/`, jadi tinggal commit dan push. Versi APK terlihat di aplikasi
(**Pengaturan → Versi aplikasi**).

## Menjalankan aplikasi (mode simulasi)

Prasyarat: Flutter SDK 3.38 atau lebih baru (diuji dengan Flutter 3.47.6).

```bash
flutter pub get
```

```bash
flutter run
```

Mode simulasi tidak membutuhkan backend. Perilakunya:

- Konveyor yang berjalan memilah sekitar 1 item setiap 3–4 detik. Statistik,
  grafik, dan kapasitas ikut berubah.
- Tempat sampah yang mencapai 100% dikosongkan "petugas" sekitar 25 detik
  kemudian, supaya demo terus berjalan.
- Saat kapasitas melewati threshold, aplikasi membuat notifikasi.
- **Pengaturan → Mode Simulasi** berisi kontrol untuk mendemokan kondisi
  offline (heartbeat dihentikan), gangguan konveyor (state Error), dan
  pengosongan tempat sampah.
- Di Dashboard, ketuk kartu tempat sampah untuk membuka detail. Di sana ada
  tombol **Isi +10%** / **Kosongkan** untuk menguji notifikasi threshold.

Folder `web/` disertakan agar demo juga bisa dibuka di browser
(`flutter run -d chrome`). Push notification hanya muncul di Android dan iOS.

## Struktur proyek

```
lib/
├── main.dart                     # bootstrap: pilih sumber data, notifikasi, Provider
├── app.dart                      # MaterialApp, tema terang/gelap, locale id_ID
├── config/app_config.dart        # nama app, versi, sumber data, batas waktu
├── core/theme/                   # token warna (palet tervalidasi) & tema
├── core/utils/formatters.dart    # format waktu/angka Indonesia
├── models/                       # WasteBin, WasteSorting, SystemStatus,
│                                 # AppNotification, AppSettings, SystemCommand
├── data/
│   ├── trash_repository.dart     # kontrak sumber data
│   ├── mock/                     # simulasi (default)
│   └── firebase/                 # Firebase Realtime Database
├── services/notification_service.dart
├── state/monitoring_controller.dart   # state real-time, deteksi kejadian, START/STOP
├── features/
│   ├── shell/                    # bottom navigation
│   ├── dashboard/                # Dashboard + widget-widgetnya
│   ├── notifications/            # Notification Panel
│   ├── history/                  # Riwayat + Detail Riwayat
│   └── settings/                 # Pengaturan
└── widgets/                      # komponen bersama (kartu, pill status, dialog, chart utils)
firebase/
├── database.rules.json           # security rules Realtime Database
└── seed_data.json                # contoh struktur data (bisa diimpor)
firmware/
├── esp32/PilahPintar_ESP32/      # sketch ESP32 DevKitC V4 (pemilah + gateway IoT)
├── stm32/PilahPintar_STM32/      # sketch STM32 Black Pill (2 konveyor, E-stop)
└── test/                         # uji protokol UART & aturan klasifikasi di PC
tools/build_apk.ps1               # build APK (simulasi / Firebase)
test/                             # unit test & widget test
```

## Mode Firebase

Langkah lengkap (membuat proyek Firebase, akun perangkat ESP32, rules) ada di
[firmware/README.md](firmware/README.md#1-siapkan-firebase-sekali-saja).
Ringkasnya:

1. Salin `firebase_config.example.json` menjadi `firebase_config.json`, lalu
   isi nilainya dari Firebase Console. File ini tidak ikut ter-commit.
2. Opsional: impor `firebase/seed_data.json` lewat Realtime Database →
   **⋮ → Import JSON** untuk mencoba tanpa ESP32.
3. Jalankan atau build dengan konfigurasi tersebut:

   ```bash
   flutter run --dart-define-from-file=firebase_config.json
   ```

   ```powershell
   .\tools\build_apk.ps1 -Firebase
   ```

`tools/build_apk.ps1` memakai toolchain di `%USERPROFILE%\fltools`. Tanpa
`-Firebase`, skrip ini membuat APK mode simulasi; tambahkan `-Universal` untuk
APK semua arsitektur. Sebagai alternatif, `flutterfire configure` boleh dipakai
untuk menimpa `lib/firebase_options.dart`.

Jika Firebase gagal diinisialisasi, aplikasi menampilkan pesan error. Aplikasi
sengaja tidak beralih diam-diam ke data simulasi, supaya tidak ada data palsu
yang terlihat seperti data real-time.

## Firmware ESP32 & STM32

Firmware contoh yang siap di-upload lewat Arduino IDE ada di folder
[`firmware/`](firmware/README.md):

- **ESP32 DevKitC V4**: pemilahan (VL53L1X, sensor induktif, kapasitif,
  soil moisture, 3 servo pendorong), sensor ultrasonik, laporan pemilahan,
  heartbeat, dan meneruskan START/STOP.
- **STM32 Black Pill**: 2 motor konveyor dan perlindungan (tombol darurat).

Panduannya mencakup wiring, protokol UART beserta cara parsing-nya, kalibrasi
pemilah, dan uji bertahap, termasuk mode "STM32 virtual" untuk menguji tanpa
STM32.

## Kontrak data untuk firmware ESP32

| Node | Penulis | Isi |
|---|---|---|
| `system_status` | ESP32, **setiap ±5 detik** (heartbeat) | `system_status` `ON`/`OFF`, `conveyor_status` `RUNNING`/`STOPPED`, `connection_status` `CONNECTED`, `last_updated` (epoch ms, gunakan server timestamp `{".sv":"timestamp"}`), `error` (string kosong bila normal) |
| `bins/<organik\|recyclable\|logam\|anorganik>` | ESP32 | `category`, `capacity_percentage` (0–100), `status`, `last_updated` |
| `sortings/<pushId>` | ESP32, setiap item selesai dipilah | `category`, `timestamp`, `status` `SUCCESS`/`FAILED`, `item` (opsional, mis. "Botol plastik") |
| `commands/latest` | Aplikasi | `command` `START`/`STOP`, `issued_at`, `status` `PENDING`, `source` |
| `notifications/<id>` | Aplikasi | `type`, `message`, `timestamp`, `is_read`, `category` |
| `settings` | Aplikasi | `notification_enabled`, `almost_full_threshold`, `full_threshold` |

Aturan penting untuk firmware:

- **Deteksi offline memakai heartbeat.** Jika `system_status.last_updated` tidak
  berubah selama 15 detik, aplikasi menganggap perangkat offline
  (`AppConfig.deviceStaleAfter`). ESP32 harus memperbarui `last_updated`
  secara berkala walaupun tidak ada perubahan lain.
- **Perintah START/STOP.** ESP32 mendengarkan `commands/latest`. Saat ada
  perintah `PENDING` yang `issued_at`-nya kurang dari 30 detik, ESP32
  meneruskannya ke STM32, menulis `status: "DONE"` (atau `"FAILED"`), lalu
  memperbarui `system_status`. Aplikasi menunggu `system_status` berubah sesuai
  perintah (maksimal 15 detik) sebelum menampilkan hasilnya.
- **Gangguan.** Isi `system_status.error` (mis. `"Konveyor macet"`) dan set
  `conveyor_status: "STOPPED"`. Aplikasi masuk ke state Error dan mengirim
  notifikasi "Sistem berhenti secara tidak normal".
- **Status kapasitas** (`bins/*/status`) hanya bersifat informatif. Aplikasi
  menghitung ulang Normal/Hampir Penuh/Penuh dari threshold di Pengaturan,
  sehingga perubahan threshold langsung berlaku.
- Persentase kapasitas dihitung dari jarak ultrasonik:
  `capacity = (tinggi_kosong − jarak) / (tinggi_kosong − jarak_penuh) × 100`,
  dibatasi 0–100.

## Notifikasi

Aplikasi membuat peringatan saat mendeteksi perubahan data real-time:

1. Kapasitas melewati threshold hampir penuh.
2. Kapasitas melewati threshold penuh.
3. Perangkat berhenti mengirim data (connection lost).
4. Konveyor berhenti tanpa perintah STOP, atau perangkat melaporkan `error`.

Setiap peringatan disimpan di `notifications` dengan ID deterministik. Jadi
beberapa ponsel yang mendeteksi kejadian yang sama tidak membuat entri ganda.
Notifikasi tidak muncul berulang kali karena noise sensor: setelah peringatan
muncul, kapasitas harus turun 3% di bawah threshold sebelum peringatan yang
sama bisa muncul lagi.

**Batasan prototype.** Push notification ditampilkan oleh aplikasi
(`flutter_local_notifications`), sehingga hanya muncul selama aplikasi masih
berjalan, termasuk di background. Push ketika aplikasi ditutup penuh
memerlukan Firebase Cloud Messaging + Cloud Functions yang memantau node
`bins` dan `system_status`. Ini langkah pengembangan berikutnya.

Catatan Android: `flutter_local_notifications` memerlukan *core library
desugaring*. Konfigurasinya sudah ditambahkan di
`android/app/build.gradle.kts`.

## Pengujian

```bash
flutter test
```

Cakupan tes:

- Threshold dan parsing data Firebase.
- Agregasi riwayat (per jam/per hari).
- Controller: notifikasi threshold, alur STOP → OFF/STOPPED, deteksi offline,
  dan gangguan konveyor.
- Widget: app langsung membuka Dashboard tanpa login, dialog konfirmasi
  STOP, dan navigasi.
- Kontrak firmware: JSON persis seperti yang ditulis ESP32 terbaca benar
  (`test/firmware_contract_test.dart`).

Protokol UART firmware diuji terpisah dengan gcc, lihat
[firmware/README.md](firmware/README.md#cara-parsing-kode-yang-sama-di-kedua-board).

## Keamanan (catatan untuk tahap lanjut)

Karena aplikasi tidak memakai login, rules mengizinkan siapa pun yang
mengetahui URL database untuk membaca data dan menulis `commands`,
`settings`, serta `notifications` (dengan validasi format). Node yang ditulis
perangkat (`system_status`, `bins`, `sortings`) mensyaratkan `auth != null`,
jadi ESP32 perlu masuk menggunakan akun perangkat (Email/Password) di Firebase
Auth. Untuk penggunaan di luar prototype, aktifkan **Firebase App Check** agar
hanya aplikasi resmi yang dapat mengirim perintah START/STOP.
