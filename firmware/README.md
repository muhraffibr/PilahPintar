# Integrasi ESP32 + STM32 dengan Aplikasi PilahPintar

Panduan ini menjelaskan cara menyambungkan ESP32 dan STM32 ke aplikasi,
serta cara data di-*parsing* di setiap tahap.

```
 Aplikasi (HP) ◄──── internet ────► Firebase Realtime Database ◄──── Wi-Fi/HTTPS ────► ESP32 (DevKitC V4)
                                                                                        │  UART 115200
                                                                                        ▼
                                                                                 STM32 Black Pill ──► L298N ──► 2 motor konveyor
```

| Perangkat | Tugas | Firmware |
|---|---|---|
| **ESP32-DevKitC V4 (WROOM-32U)** | Pemilah: VL53L1X, sensor induktif, kapasitif, soil moisture, 3 servo pendorong. Gateway IoT: ultrasonik 4 tempat sampah, laporan pemilahan, heartbeat, meneruskan START/STOP dari aplikasi | [`esp32/PilahPintar_ESP32`](esp32/PilahPintar_ESP32) |
| **STM32F411CEU6** | 2 motor konveyor (soft start), perlindungan (tombol darurat, arus berlebih, link putus) | [`stm32/PilahPintar_STM32`](stm32/PilahPintar_STM32) |

Aplikasi **tidak** berbicara langsung dengan ESP32. Keduanya hanya membaca
dan menulis Firebase. Jadi ESP32 dan HP tidak perlu berada di Wi-Fi yang sama.

---

## 1. Siapkan Firebase (sekali saja)

1. Buka [Firebase Console](https://console.firebase.google.com/) → **Add project**.
2. **Build → Realtime Database → Create database**. Pilih lokasi
   *Singapore (asia-southeast1)* dan *Start in locked mode*.
3. Tab **Rules**: tempel isi [`../firebase/database.rules.json`](../firebase/database.rules.json),
   lalu **Publish**.
4. **Build → Authentication → Get started → Email/Password → Enable**.
   Lalu di tab **Users → Add user**, buat akun khusus perangkat, misalnya
   `esp32@pilahpintar.id`. Akun ini hanya dipakai ESP32; pengguna aplikasi
   tetap tidak perlu login.
5. **Project settings (⚙) → General**:
   - Catat **Web API Key**.
   - Di *Your apps*, klik ikon **Android**, isi package name
     `id.sch.sman1bandung.trash_monitor`, lalu **Register app**. Catat
     **App ID** dan **Project number** (= *messaging sender ID*). File
     `google-services.json` tidak perlu diunduh.
6. Catat **URL database** di halaman Realtime Database, misalnya
   `https://nama-proyek-default-rtdb.asia-southeast1.firebasedatabase.app`.

### Aplikasi ke mode Firebase

1. Salin `firebase_config.example.json` (di root proyek) menjadi
   `firebase_config.json`, lalu isi nilai dari langkah di atas.
2. Build APK mode Firebase:

   ```powershell
   .\tools\build_apk.ps1 -Firebase
   ```

3. Pasang `PilahPintar-1.0.0-firebase-arm64.apk` di HP. Sebelum ESP32 menyala,
   Dashboard akan menampilkan **"Menunggu koneksi ke perangkat."**.

---

## 2. Rangkaian

Semua pin bisa diubah di `config.h` masing-masing board. Batasan ESP32 klasik:
GPIO 6–11 dipakai flash, GPIO 34/35/36/39 hanya input tanpa pull-up internal,
GPIO 0/2/5/12/15 pin strapping (dibiarkan kosong), dan sensor analog harus di
ADC1 (GPIO 32–39) karena ADC2 tidak bisa dibaca saat Wi-Fi aktif.

### Daya dan tombol darurat

```
PSU 12 V 5 A ─ sekring 5 A ─┬─ LM2596 → 5 V ─┬─ ESP32 (pin 5V), STM32 (pin 5V), 4 ultrasonik
                            │                 └─ (pin 3V3 ESP32 → VL53L1X, soil moisture)
                            ├─ sensor induktif & kapasitif (12 V langsung)
                            └─ E-stop kontak NC1 ─┬─ L298N (+12 V motor)
                                                  └─ XL4015 → 6 V → 3 servo (+ kapasitor 1000 µF)
E-stop kontak NC2: PB12 STM32 ↔ GND
Semua GND disatukan.
```

- Tombol E-stop jenis jamur **latching** (putar untuk melepas) dengan **dua
  kontak NC**. NC1 memutus kabel **+12 V** aktuator, bukan GND. NC2
  memberi tahu STM32.
- **Setel tegangan buck dengan multimeter sebelum memasang beban**: LM2596 ke
  5,0 V, XL4015 ke 6,0 V. XL4015 baru bisa saja keluar 12 V dan merusak servo.

### ESP32 ↔ STM32 (UART)

| ESP32 | STM32 Black Pill | Keterangan |
|---|---|---|
| GPIO **17** (TX2) | **PA3** (RX USART2) | data ESP32 → STM32 |
| GPIO **16** (RX2) | **PA2** (TX USART2) | data STM32 → ESP32 |
| **GND** | **GND** | wajib, tanpa ini data rusak |

Kedua board memakai logika 3,3 V, jadi bisa disambung langsung tanpa
level shifter. Kabel TX selalu disilang ke RX.

### Sensor pemilah dan servo (di ESP32)

| Komponen | Pin ESP32 | Catatan |
|---|---|---|
| VL53L1X | SDA **21**, SCL **22**, VIN **3V3** | ±15 cm di atas sabuk, menghadap ke bawah. Kabel I2C maksimal ±30 cm |
| Induktif LJ18A3-8-Z/BX (NPN) | **34** lewat PC817 | Di bawah sabuk, pada alas bukan logam |
| Kapasitif LJC18A3-H-Z/BY (PNP) | **35** lewat PC817 | Di dinding penyempit |
| Capacitive soil moisture | **36** (VP), VCC **3V3** | Di bagian yang pasti disentuh sampah |
| Servo pendorong organik | **25** | Daya dari XL4015 6 V |
| Servo pendorong logam | **26** | Daya dari XL4015 6 V |
| Servo pendorong recyclable | **27** | Daya dari XL4015 6 V |

Sensor proximity 12 V **tidak boleh** disambung langsung ke ESP32. Pakai
optocoupler PC817 (pin 1 anoda, 2 katoda, 3 emitor, 4 kolektor):

```
Induktif (NPN):  12V ─[1 kΩ]─ PC817 pin1;  PC817 pin2 ─ kabel HITAM induktif
Kapasitif (PNP): kabel HITAM kapasitif ─[1 kΩ]─ PC817 pin1;  PC817 pin2 ─ GND
Sisi ESP32 (keduanya): 3V3 ─[10 kΩ]─┬─ GPIO 34 / 35
                                    PC817 pin4;  PC817 pin3 ─ GND
Kabel sensor: COKELAT → 12 V, BIRU → GND
```

Saat sensor mendeteksi benda, GPIO bernilai **LOW**. Resistor 10 kΩ wajib,
karena GPIO 34/35 tidak punya pull-up internal; tanpa resistor, pin
mengambang dan pemilah membaca benda palsu.

Pasang **semua sensor berdekatan dalam satu zona deteksi** (sebaiknya ≤ 6 cm)
sebelum pendorong pertama. Urutan tempat sampah sepanjang sabuk: organik,
logam, recyclable, lalu ujung sabuk untuk anorganik (tanpa pendorong).

### Sensor ultrasonik (di ESP32)

| Tempat sampah | TRIG | ECHO |
|---|---|---|
| Organik | GPIO 4 | GPIO 18 |
| Recyclable | GPIO 13 | GPIO 19 |
| Logam | GPIO 14 | GPIO 32 |
| Anorganik | GPIO 23 | GPIO 33 |

- **ECHO HY-SRF05/HC-SR04 bertegangan 5 V**, sedangkan pin ESP32 hanya tahan
  3,3 V. Pasang pembagi tegangan (ECHO → 1 kΩ → pin ESP32 → 2 kΩ → GND).
- Pasang sensor di tutup tempat sampah, menghadap ke bawah. Ukur jarak sensor
  ke dasar (kosong) dan ke garis "penuh", lalu isi `BIN_EMPTY_DISTANCE_CM` dan
  `BIN_FULL_DISTANCE_CM` di `config.h`.

### Motor konveyor dan tombol darurat (di STM32)

| STM32 | L298N | Fungsi |
|---|---|---|
| PB6 (PWM 20 kHz) | ENA | Kecepatan motor A, konveyor atas |
| PB7 / PB8 | IN1 / IN2 | Arah motor A |
| PB9 (PWM 20 kHz) | ENB | Kecepatan motor B, konveyor bawah |
| PB13 / PB14 | IN3 / IN4 | Arah motor B |
| PB12 | — | Kontak NC2 E-stop ke GND |
| GND | GND | Satukan dengan GND catu motor |

Lepas jumper ENA/ENB di modul L298N. Kecepatan diatur `MOTOR_A_DUTY` dan
`MOTOR_B_DUTY`; konveyor bawah sengaja lebih cepat supaya jarak antar sampah
bertambah saat pindah sabuk. Opsional: sensor arus ACS712 di PA1
(`USE_CURRENT_SENSE 1`).

---

## 3. Upload firmware

### ESP32 DevKitC V4 (Arduino IDE)

1. **Library Manager** → pasang:
   - **ArduinoJson** (Benoit Blanchon) versi 7.x
   - **VL53L1X** (Pololu). Bukan "SparkFun VL53L1X", karena nama fungsinya berbeda.
   - **ESP32Servo** (Kevin Harrington)
2. Buka `esp32/PilahPintar_ESP32/PilahPintar_ESP32.ino`.
3. Salin `secrets.example.h` menjadi `secrets.h` di folder yang sama, lalu isi
   Wi-Fi (2,4 GHz) dan data Firebase. `secrets.h` tidak ikut ter-commit.
4. **Tools**:
   - Board: **ESP32 Dev Module**
   - Flash Size: **4MB (32Mb)**
   - Partition Scheme: **Default 4MB with spiffs**. Jika muncul "Sketch too
     big", pilih **Huge APP (3MB No OTA/1MB SPIFFS)**.
5. Upload. Jika upload macet di "Connecting...", tahan tombol **BOOT** di board
   sampai upload mulai.
6. Buka **Serial Monitor** pada **115200 baud**, line ending **Newline**.
   Setiap 10 detik akan muncul status seperti ini:

   ```
   [INFO] wifi=ok fb=ok stm=ok sistem=ON konveyor=RUN antrean=0
          organik    jarak=26.4 cm  kapasitas=39.4%
          ...
          pemilah    vl53l1x=ok item_di_sabuk=1
   ```

### STM32 Black Pill (Arduino IDE + STM32duino)

1. **Tools → Board → STM32 MCU based boards → Generic STM32F4 series**.
2. **Board part number: BlackPill F411CE**.
3. **Upload method**: *STM32CubeProgrammer (DFU)*. Masuk mode DFU dengan
   menahan **BOOT0**, menekan **NRST**, lalu melepas BOOT0. Bisa juga lewat
   *SWD* memakai ST-Link. STM32CubeProgrammer harus sudah terpasang.
4. Buka `stm32/PilahPintar_STM32/PilahPintar_STM32.ino` → Upload.
5. LED biru (PC13): kedip lambat = siaga, menyala = konveyor berjalan, kedip
   cepat = gangguan.
6. `USE_ESTOP` sudah aktif. Selama tombol E-stop belum terpasang, START
   ditolak dengan `$NAK,START,ESTOP`. Untuk uji di meja, sambungkan PB12 ke GND
   dengan kabel jumper.

---

## 4. Protokol UART ESP32 ↔ STM32 & cara parsing

### Format frame

```
$TIPE,field1,field2*CS\n
```

- Diawali `$` dan diakhiri `\n`. Field dipisah koma.
- `CS` = XOR semua byte di antara `$` dan `*`, ditulis dua digit hex.
  Contoh: XOR dari `CMD,START` = `0x26` → frame `$CMD,START*26`.
- Checksum boleh dihilangkan, sehingga Anda bisa mengetik `$STS,RUN,0` langsung
  di Serial Monitor. Jika checksum ada, nilainya wajib benar.

### Daftar pesan

| Arah | Frame | Arti |
|---|---|---|
| ESP32 → STM32 | `$CMD,START` | Jalankan konveyor (sekaligus mereset gangguan) |
| ESP32 → STM32 | `$CMD,STOP` | Hentikan konveyor |
| ESP32 → STM32 | `$PING` | Tanda ESP32 hidup, dikirim tiap 1 detik. Tanpa ini selama 5 detik, STM32 menghentikan konveyor |
| STM32 → ESP32 | `$ACK,START` / `$ACK,STOP` | Perintah dijalankan |
| STM32 → ESP32 | `$NAK,START,ESTOP` | Perintah ditolak beserta alasannya |
| STM32 → ESP32 | `$STS,RUN,0` | Status tiap 1 detik: `RUN`/`STOP`, lalu kode gangguan |
| STM32 → ESP32 | `$SRT,logam,OK,Kaleng minuman` | Opsional, jika pemilahan dilakukan STM32 |

Kode gangguan: `0` normal · `1` arus berlebih · `2` macet ·
`3` tombol darurat · `4` STM32 kehilangan sinyal ESP32. ESP32 mengubah kode
ini menjadi teks di `system_status.error`, misalnya "Tombol darurat ditekan".
Jika STM32 tidak mengirim apa pun selama 3 detik, ESP32 melaporkan
"STM32 tidak merespons".

### Cara parsing (kode yang sama di kedua board)

`pp_protocol.c` / `.h` identik di kedua folder firmware. Parsing dilakukan
**byte per byte**, sehingga tidak memblok dan tahan terhadap noise:

```
'$' → mulai frame baru (sisa frame lama dibuang)
byte biasa → simpan ke buffer (maks. 96 karakter)
'\n' → pisahkan "*CS", cek checksum, pecah per koma → pp_msg_t
```

Pemakaian di `loop()`:

```cpp
pp_reader_t reader;               // pp_reader_init(&reader) di setup()

while (port.available()) {
  pp_msg_t msg;
  if (pp_reader_feed(&reader, port.read(), &msg) == PP_MSG) {
    if (pp_is(&msg, "STS")) {
      bool jalan = strcmp(pp_field(&msg, 0), "RUN") == 0;
      int gangguan = atoi(pp_field(&msg, 1));
      // ...
    }
  }
}
```

Mengirim frame:

```cpp
const char *f[] = {"START"};
char buf[64];
size_t n = pp_build(buf, sizeof buf, "CMD", f, 1);   // "$CMD,START*26\n"
Serial2.write((const uint8_t *)buf, n);
```

Uji protokol dan aturan klasifikasi di PC tanpa board:

```bash
gcc -std=c99 -Wall -o test_protocol firmware/test/test_protocol.c firmware/esp32/PilahPintar_ESP32/pp_protocol.c
```

```bash
gcc -std=c99 -Wall -o test_sort_rules firmware/test/test_sort_rules.c firmware/esp32/PilahPintar_ESP32/sort_rules.c
```

---

## 5. Data ESP32 ↔ Firebase & cara parsing

ESP32 memakai **REST API** Firebase lewat HTTPS (`firebase_rtdb.cpp`) dan
**ArduinoJson** untuk membuat dan membaca JSON. Setiap path ditambah
`.json?auth=<token>`. Token didapat dari login akun perangkat dan diperbarui
otomatis setiap jam.

| Node | Operasi ESP32 | Kapan | Contoh JSON |
|---|---|---|---|
| `system_status` | `PATCH` | tiap 5 dtk + saat status berubah | `{"system_status":"ON","conveyor_status":"RUNNING","connection_status":"CONNECTED","last_updated":{".sv":"timestamp"},"error":""}` |
| `bins` | `PATCH` multi-path | tiap 10 dtk, atau segera jika berubah ≥ 2% | `{"organik/capacity_percentage":64.8,"organik/status":"NORMAL","organik/last_updated":{".sv":"timestamp"}, ...}` |
| `sortings` | `POST` (push ID otomatis) | setiap item dipilah | `{"category":"logam","status":"SUCCESS","item":"Logam (induktif)","timestamp":1759556601000}` |
| `commands/latest` | `GET` tiap 1 dtk, lalu `PATCH {"status":...}` | — | dibaca: `{"command":"START","issued_at":1759556600000,"status":"PENDING"}` |
| `settings` | `GET` tiap 60 dtk | — | `{"almost_full_threshold":70,"full_threshold":90,...}` |

`{".sv":"timestamp"}` diganti oleh server Firebase menjadi waktu server
(epoch milidetik), sehingga jam ESP32 dan jam HP tidak perlu sama persis.
Laporan pemilahan memakai waktu NTP saat kejadian. Jika Wi-Fi putus, laporan
disimpan di antrean (16 item) dan dikirim setelah koneksi pulih.

### Alur START / STOP

```
Aplikasi            Firebase                     ESP32                      STM32
   │ tekan START       │                            │                          │
   ├─ set ───────────► commands/latest {PENDING}    │                          │
   │                   │ ◄──── GET (tiap 1 dtk) ────┤                          │
   │                   │ ◄──── PATCH status=ACK ────┤                          │
   │                   │                            ├──── $CMD,START ────────► │ motor soft start
   │                   │                            │ ◄─── $ACK,START ─────────┤
   │                   │ ◄──── PATCH status=DONE ───┤                          │
   │                   │ ◄──── system_status ON/RUNNING                        │
   │ ◄── stream ───────┤                            │                          │
   │ "Sistem berjalan — konveyor RUNNING."           │                          │
```

Perintah yang lebih tua dari 30 detik diabaikan (`FAILED`), supaya ESP32 yang
baru menyala tidak menjalankan perintah lama. Aplikasi menunggu
`system_status` berubah paling lama 15 detik.

Cara ESP32 mem-*parsing* perintah (potongan `handleCommandJson`):

```cpp
JsonDocument doc;
deserializeJson(doc, body);                     // body = respons GET
const char *status  = doc["status"]  | "";
const char *command = doc["command"] | "";
uint64_t issuedAt   = doc["issued_at"] | (uint64_t)0;
if (strcmp(status, "PENDING") == 0) { /* teruskan ke STM32 */ }
```

### Laporan pemilahan

Setiap hasil dari pemilah (bagian 6) dikirim lewat `laporkanPemilahan()`.
Fungsi ini juga bisa dipanggil sendiri, atau lewat pesan `$SRT` dari STM32 /
Serial Monitor:

```cpp
laporkanPemilahan(KATEGORI_LOGAM, true, "Kaleng minuman");
laporkanPemilahan(KATEGORI_ANORGANIK, false);   // gagal dipilah
```

Kategori harus salah satu dari `organik`, `recyclable`, `logam`, atau
`anorganik`, karena aplikasi memakai kunci yang sama.

---

## 6. Logika pemilahan & kalibrasi

Pemilahan ada di `sorter.cpp` (alur dan waktu) dan `sort_rules.c` (aturan
klasifikasi). Pemilah berjalan sebagai task FreeRTOS sendiri di core 0
dan memeriksa sensor tiap 5 ms, sehingga tetap tepat waktu walaupun `loop()`
sedang menunggu HTTPS ke Firebase. Pemilah hanya bekerja saat STM32
melaporkan konveyor berjalan.

### Alur satu item

1. Item masuk zona sensor: salah satu sensor aktif (VL53L1X melihat benda,
   induktif/kapasitif LOW, atau soil moisture ≤ `SOIL_WET_RAW`).
2. Selama di zona, ciri dikumpulkan: tinggi dan pantulan maksimum dari
   VL53L1X, induktif, kapasitif, dan nilai soil moisture terendah.
3. Setelah semua sensor tidak aktif selama `ITEM_GAP_MS` (150 ms), item
   diklasifikasi.
4. Pendorong digerakkan saat item tepat di depannya:
   `waktu = tengah item di zona + jarak pendorong ÷ BELT_SPEED_MM_S`.
   Anorganik tidak didorong dan jatuh di ujung sabuk.
5. Hasil dikirim ke aplikasi. Kolom `item` berisi alasan klasifikasi, misalnya
   "Logam (induktif)" atau "Botol (tinggi)".

Sampah yang tidak terbaca sensor mana pun ikut jatuh di ujung sabuk ke
tempat sampah anorganik.

### Aturan klasifikasi (`sort_rules.c`)

Aturan pertama yang cocok dipakai:

| Urutan | Syarat | Kategori |
|---|---|---|
| 1 | Induktif aktif | logam |
| 2 | Soil moisture ≤ `SOIL_WET_RAW` | organik |
| 3 | Tinggi ≥ `BOTTLE_MIN_HEIGHT_MM` dan pantulan ≥ `STYROFOAM_MIN_SIGNAL_MCPS` | anorganik (styrofoam) |
| 3 | Tinggi ≥ `BOTTLE_MIN_HEIGHT_MM` | recyclable (botol) |
| 4 | Kapasitif aktif (`CAPACITIVE_MEANS_ORGANIC 1`) | organik |
| 5 | Tinggi ≤ `PAPER_MAX_HEIGHT_MM` dan pantulan ≥ `PAPER_MIN_SIGNAL_MCPS` | recyclable (kertas) |
| 6 | Selain itu | anorganik (residu) |

Aturan styrofoam dan kertas **mati secara bawaan** (nilai `0.0f`), karena
ambang pantulannya hanya bisa ditentukan dari data alat Anda. Sebelum
dikalibrasi, kertas akan masuk anorganik.

### Langkah kalibrasi

1. **Ukur geometri** dan isi di `config.h` ESP32:
   - `BELT_SPEED_MM_S`: tandai sabuk bawah, jalankan konveyor, ukur jarak
     tempuhnya dalam 10 detik lalu bagi 10. Ukur ulang setiap kali
     `MOTOR_B_DUTY` di STM32 diubah.
   - `PUSHER_*_DISTANCE_MM` dan `BELT_END_DISTANCE_MM`: jarak dari tengah zona
     sensor ke tengah tiap pendorong dan ke ujung sabuk.
2. **Uji pendorong**: ketik `$TES,0`, `$TES,1`, `$TES,2` di Serial Monitor.
   Setel `SERVO_HOME_DEG` / `SERVO_PUSH_DEG` sampai crank slider mundur dan
   maju penuh tanpa menabrak.
3. **Mode kalibrasi**: ketik `$CAL,ON`. Tiap 250 ms muncul nilai mentah:

   ```
   [CAL] tof=148mm (tinggi 2mm) sinyal=9.84 | induktif=0 kapasitif=0 soil=2875
   ```

   Saat sabuk kosong, isi `TOF_BELT_DISTANCE_MM` dengan nilai `tof=`, dan
   pastikan induktif/kapasitif 0.
4. **Kumpulkan data**: lewatkan 10–20 sampel per kategori melalui zona sensor
   (dengan konveyor berjalan, atau digeser dengan tangan saat konveyor diam).
   Untuk setiap item muncul baris:

   ```
   CSV,420,62,7.15,0,0,2810,recyclable,Botol (tinggi)
   ```

   Kolomnya: lama di zona (ms), tinggi (mm), pantulan (MCPS), induktif,
   kapasitif, soil terendah, kategori, alasan. Salin semua baris `CSV,` ke
   Excel, lalu tentukan ambang yang paling memisahkan kategori, misalnya
   pantulan kertas vs kresek. **Pakai sampel yang berbeda** untuk uji akurasi
   100 sampel nanti.
5. Isi ambang di `config.h`, upload ulang, lalu ketik `$CAL,OFF`.

Setiap item juga mencetak `[ITEM] ... keputusan N ms setelah item lewat`,
yang bisa dipakai sebagai data uji waktu deteksi (FR-01).

### Kecepatan servo

`SERVO_SPEED_DEG_S 0` membuat servo bergerak secepat kemampuannya (±0,5 dtk
untuk 180°). Jika sampah terlempar terlalu keras atau crank slider
menghentak, isi misalnya `240` (180° dalam 0,75 dtk) atau `180` (1 dtk).
Satu siklus maju-mundur jadi lebih lama, jadi pastikan pendorong sudah
kembali sebelum item berikutnya untuk pendorong yang sama tiba.

---

## 7. Cara aplikasi mem-parsing data

Aplikasi berlangganan setiap node secara real-time (`onValue`) di
`lib/data/firebase/firebase_trash_repository.dart`, lalu mengubah JSON
menjadi model Dart:

| Node | Model | File |
|---|---|---|
| `system_status` | `SystemStatus.fromMap` | `lib/models/system_status.dart` |
| `bins/*` | `WasteBin.tryFromMap` | `lib/models/waste_bin.dart` |
| `sortings/*` | `WasteSorting.tryFromMap` | `lib/models/waste_sorting.dart` |
| `commands/latest` | `CommandRecord.tryFromMap` | `lib/models/system_command.dart` |
| `settings` | `AppSettings.fromMap` | `lib/models/app_settings.dart` |

Parsing dibuat toleran (`lib/models/parsing.dart`):

- Angka boleh `int`, `double`, atau string.
- Timestamp boleh dalam detik atau milidetik.
- Kategori menerima alias bahasa Inggris (`metal`, `organic`, `residual`).
- `error` kosong dianggap normal.

Data yang tidak lengkap dilewati, bukan membuat aplikasi crash.
[`test/firmware_contract_test.dart`](../test/firmware_contract_test.dart)
memastikan JSON persis seperti yang dikirim firmware terbaca dengan benar.

Aplikasi menganggap perangkat **offline** jika `system_status.last_updated`
lebih tua dari 15 detik. Karena itu heartbeat 5 detik di ESP32 wajib ada.

---

## 8. Uji bertahap (disarankan)

**Tahap 1: ESP32 + aplikasi, tanpa STM32.**

1. Upload firmware ESP32 dan buka Serial Monitor.
2. Ketik `$SIM,ON`. ESP32 kini membalas perintah seolah STM32 tersambung
   ("STM32 virtual").
3. Di aplikasi: Dashboard menjadi **ONLINE**. Tekan START/STOP; status harus
   berubah dalam 1–2 detik.
4. Ketik `$SRT,recyclable,OK,Botol plastik`. Item ini harus muncul di
   Aktivitas Terbaru dan statistik bertambah.
5. Tutup sensor ultrasonik dengan tangan; kartu kapasitas harus naik.

**Tahap 2: pemilah di meja, tanpa STM32.**

1. Ketik `$CAL,ON`. Gerakkan kaleng, sisa makanan, dan botol di bawah zona
   sensor dengan tangan; baris `[ITEM]` dan `CSV,` harus muncul dengan
   kategori yang masuk akal.
2. Ketik `$TES,0`, `$TES,1`, `$TES,2`; ketiga pendorong harus maju lalu
   mundur.
3. Ketik `$SIM,ON` lalu tekan START di aplikasi. Pemilah kini aktif seolah
   sabuk berjalan: lewatkan sampah dengan tangan, dan pendorong yang sesuai
   bergerak setelah jeda jarak ÷ kecepatan sabuk. Hasilnya muncul di aplikasi.

**Tahap 3: STM32 sendiri.**

1. Sambungkan adaptor USB-TTL ke PA2/PA3 dan buka terminal serial 115200.
   Sambungkan PB12 ke GND (atau pasang tombol E-stop).
2. Ketik `$CMD,START`; kedua motor berputar perlahan naik (soft start) dan
   STM32 membalas `$ACK,START`, lalu `$STS,RUN,0` tiap detik.
3. Lepas kabel PB12 (atau tekan E-stop): motor berhenti dan muncul
   `$STS,STOP,3`. Pasang lagi: motor **tetap** berhenti sampai `$CMD,START`.
4. Tanpa `$PING`, motor berhenti setelah 5 detik dengan `$STS,STOP,4`. Ini
   memang perilaku keamanannya. Untuk uji lebih lama, ketik `$PING` berkala
   atau set `LINK_TIMEOUT_MS 0` sementara.

**Tahap 4: semua tersambung.** Ketik `$SIM,OFF` di Serial Monitor ESP32,
sambungkan UART, lalu uji START/STOP dari aplikasi, pemilahan dengan sabuk
berjalan, dan tombol darurat. Saat E-stop ditekan, aplikasi menampilkan
"Tombol darurat ditekan" dan item yang masih di sabuk dilaporkan gagal.

---

## 9. Masalah umum

| Gejala | Penyebab & solusi |
|---|---|
| Aplikasi tetap "Menunggu koneksi ke perangkat." | ESP32 belum pernah menulis `system_status`. Lihat Serial Monitor: Wi-Fi gagal? Login Firebase gagal (`fb=belum`)? |
| `Login Firebase gagal (... 400 ...)` | Email/password akun perangkat salah, atau Email/Password belum di-enable di Authentication |
| `PATCH 401` / `Permission denied` | Rules belum dipublish, atau ESP32 belum login |
| Aplikasi "Offline" padahal ESP32 menyala | Heartbeat gagal terkirim, cek pesan `[FB] heartbeat gagal`. Pastikan Wi-Fi 2,4 GHz |
| Error "STM32 tidak merespons" | Kabel TX/RX tertukar, GND tidak tersambung, atau baud rate berbeda |
| Kapasitas selalu 0% atau 100% | Kalibrasi `BIN_EMPTY_DISTANCE_CM` / `BIN_FULL_DISTANCE_CM`; lihat nilai `jarak=` di Serial Monitor |
| Kapasitas tidak muncul ("Data unavailable") | Sensor tidak terbaca (`sensor belum terbaca`), periksa wiring dan pembagi tegangan ECHO |
| Perintah START "FAILED" | STM32 tidak membalas `$ACK` dalam 3 detik, atau tombol darurat aktif (`NAK,START,ESTOP`) |
| Aplikasi selalu "Tombol darurat ditekan" | Tombol E-stop belum terpasang atau kontak NC2 putus. Periksa kabel PB12–GND; lepaskan tombol (putar), lalu tekan START |
| `VL53L1X tidak terdeteksi` | Cek VIN 3V3, GND, SDA 21, SCL 22. Pastikan library **VL53L1X by Pololu** |
| `[CAL] induktif=1` / `kapasitif=1` terus padahal tidak ada benda | Resistor pull-up 10 kΩ belum dipasang, atau sensor mendeteksi rangka besi di dekatnya |
| `sensor aktif terus > 5000 ms` | Ada sampah tersangkut, sisa makanan menempel di sensor soil, atau ambang salah. Sensor itu diabaikan sampai normal kembali |
| `terlambat ... ke pendorong` | Item baru selesai diklasifikasi setelah lewat pendorong. Jauhkan pendorong organik dari zona sensor, perlambat sabuk, atau perkecil `ITEM_GAP_MS` |
| Pendorong mendorong terlalu cepat / terlambat | `BELT_SPEED_MM_S` atau jarak pendorong salah. Ukur ulang (bagian 6) |
| `pendorong ... masih bergerak, item terlewat` | Dua item untuk pendorong yang sama terlalu dekat. Perbaiki singulation atau percepat servo |
| ESP32 restart saat servo bergerak (`Brownout detector was triggered`) | Servo masih mengambil daya dari jalur ESP32. Pakai XL4015 6 V terpisah dan kapasitor 1000 µF |

**Catatan keamanan prototype.** ESP32 memakai HTTPS tanpa verifikasi
sertifikat (`setInsecure()`). Untuk tahap lanjut, pasang root CA Google
dengan `client_.setCACert(...)` di `firebase_rtdb.cpp`.
