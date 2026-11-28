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
| **ESP32-DevKitC V4 (WROOM-32U)** | Pemilah: Sharp IR, LDR + laser, sensor induktif, kapasitif, soil moisture, 3 servo pendorong (bergiliran). Gateway IoT: ultrasonik 4 tempat sampah, laporan pemilahan, heartbeat, meneruskan START/STOP dari aplikasi | [`esp32/PilahPintar_ESP32`](esp32/PilahPintar_ESP32) |
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
   `esp32@pilahpintar.id`. Akun ini hanya dipakai ESP32; aplikasi tidak
   memakai login.
5. **Daftarkan UID akun ESP32.** Salin kolom **User UID** akun tadi di
   **Authentication → Users**, lalu di **Realtime Database → Data** tambahkan:

   ```
   devices/<UID akun ESP32>: true
   ```

   (klik **+** di root, isi *Key* `devices`, lalu tambahkan anak dengan *Key*
   = UID dan *Value* `true`.) Hanya akun yang terdaftar di sini yang boleh
   menulis data alat. Jika memakai `firebase/seed_data.json`, ganti
   `GANTI_DENGAN_UID_ESP32` sebelum impor.
6. **Project settings (⚙) → General**:
   - Catat **Web API Key**.
   - Di *Your apps*, klik ikon **Android**, isi package name
     `id.sch.sman1bandung.trash_monitor`, lalu **Register app**. Catat
     **App ID** dan **Project number** (= *messaging sender ID*). File
     `google-services.json` tidak perlu diunduh.
7. Catat **URL database** di halaman Realtime Database, misalnya
   `https://nama-proyek-default-rtdb.asia-southeast1.firebasedatabase.app`.

### Aplikasi ke mode Firebase

1. Salin `firebase_config.example.json` (di root proyek) menjadi
   `firebase_config.json`, lalu isi nilai dari langkah di atas.
2. Build APK mode Firebase:

   ```powershell
   .\tools\build_apk.ps1 -Firebase
   ```

3. Pasang `PilahPintar-1.0.0-firebase-arm64.apk` di HP. Aplikasi langsung
   membuka Dashboard tanpa login. Sebelum ESP32 menyala, Dashboard akan
   menampilkan **"Menunggu koneksi ke perangkat."**.

### Siapa boleh apa (database.rules.json)

| Node | Aplikasi / siapa pun (tanpa login) | ESP32 (`/devices/<uid>`) |
|---|---|---|
| Semua data (baca) | baca | baca |
| `system_status`, `bins`, `sortings` | ditolak | tulis |
| `commands/latest` | tulis (format divalidasi) | tulis (format divalidasi) |
| `settings`, `notifications` | tulis (format divalidasi) | tulis (format divalidasi) |
| `devices` | baca | baca |

Semua aturan `.validate` (format, rentang threshold, kategori) berlaku. Karena
aplikasi tidak memakai login, siapa pun yang mengetahui URL database dapat
membaca data dan mengirim perintah START/STOP dengan format yang benar. Risiko
ini dikurangi oleh validasi rules, dialog konfirmasi di aplikasi, dan
keselamatan di STM32 (tombol darurat dengan reset lokal). Untuk penggunaan di
luar prototype, tambahkan Firebase App Check atau login.

**Uji di Rules Playground** (Realtime Database → Rules → *Rules Playground*).
Untuk "ESP32", centang *Authenticated*, pilih provider *password*, dan isi UID
yang sudah didaftarkan di `/devices`. Untuk "akun lain", pakai UID acak.

| # | Tipe | Lokasi | Data | Auth | Harus |
|---|---|---|---|---|---|
| 1 | read | `/system_status` | – | tidak login | diizinkan |
| 2 | set | `/commands/latest` | `{"command":"START","issued_at":1759556601000,"status":"PENDING","source":"x"}` | tidak login | diizinkan |
| 3 | set | `/commands/latest` | `{"command":"JALAN","issued_at":1759556601000,"status":"PENDING"}` | tidak login | ditolak (validasi) |
| 4 | set | `/settings` | `{"notification_enabled":true,"almost_full_threshold":70,"full_threshold":90}` | tidak login | diizinkan |
| 5 | set | `/settings` | `{"notification_enabled":true,"almost_full_threshold":90,"full_threshold":80}` | tidak login | ditolak (validasi) |
| 6 | update | `/system_status` | `{"system_status":"ON"}` | tidak login | ditolak |
| 7 | update | `/system_status` | `{"system_status":"ON"}` | akun lain | ditolak |
| 8 | update | `/system_status` | `{"system_status":"ON"}` | ESP32 | diizinkan |
| 9 | update | `/commands/latest` | `{"status":"FAILED","reason":"LOCAL_RESET"}` | ESP32 | diizinkan |
| 10 | set | `/devices/<uid>` | `true` | ESP32 | ditolak |

Untuk #6–#9, node tujuan harus sudah berisi data (impor seed data dulu).

---

## 2. Rangkaian

Semua pin bisa diubah di `config.h` masing-masing board. Batasan ESP32 klasik:
GPIO 6–11 dipakai flash, GPIO 34/35/36/39 hanya input tanpa pull-up internal,
GPIO 0/2/5/12/15 pin strapping (dibiarkan kosong), dan sensor analog harus di
ADC1 (GPIO 32–39) karena ADC2 tidak bisa dibaca saat Wi-Fi aktif.

### Daya dan tombol darurat

```
PSU 12 V 5 A ─ sekring 5 A ─┬─ LM2596 #1 → 5 V ─┬─ ESP32 (pin 5V), STM32 (pin 5V), 4 ultrasonik, Sharp IR, laser
                            │                    └─ (pin 3V3 ESP32 → soil moisture, modul LDR)
                            ├─ sensor induktif & kapasitif (12 V langsung)
                            └─ E-stop kontak NC1 ─┬─ L298N (+12 V motor)
                                                  └─ LM2596 #2 → 6 V → 3 servo (+ kapasitor 1000 µF)
E-stop kontak NC2: PB12 STM32 ↔ GND
Tombol RESET (push button NO): PA0 STM32 ↔ GND (paralel dengan tombol KEY Black Pill)
Semua GND disatukan.
```

- Tombol E-stop jenis jamur **latching** (putar untuk melepas) dengan **dua
  kontak NC**. NC1 memutus kabel **+12 V** aktuator, bukan GND. NC2
  memberi tahu STM32.
- **Reset lokal** (`REQUIRE_LOCAL_RESET 1`, bawaan): setelah tombol darurat
  dilepas atau arus berlebih, START dari aplikasi ditolak
  (`$NAK,START,LOCAL_RESET`, aplikasi menampilkan "Reset tombol di mesin
  diperlukan") sampai tombol **RESET** di mesin ditekan. RESET hanya menghapus
  gangguan; konveyor tetap diam sampai START dari aplikasi. Pasang push button
  NO (warna biru/hitam, bukan merah) di panel mesin antara **PA0** dan **GND**.
  Untuk uji di meja cukup tekan tombol **KEY** bawaan Black Pill (juga PA0).
- **Setel tegangan buck dengan multimeter sebelum memasang beban**: LM2596 #1 ke
  5,0 V, LM2596 #2 ke 6,0 V. Modul baru bisa saja keluar 12 V dan merusak servo.
- LM2596 servo praktisnya kuat ±2 A. Firmware menyalakan servo bergiliran
  (`SERVO_DETACH_WHEN_IDLE`, `SERVO_START_GAP_MS`) agar arus puncaknya tidak
  melebihi itu. Jika modul panas, tambahkan heatsink pada IC LM2596.

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
| Sharp IR GP2Y0A21YK0F | **39** (VN), VCC **5V** | `SHARP_SIDE_MOUNT 1`: di dinding sisi sensor, setinggi ±45 mm di atas sabuk, **mundur ±10 cm** dari permukaan dalam dinding (dalam kotak berlubang), menghadap menyeberangi sabuk. Kapasitor 10 µF di VCC–GND sensor |
| Modul LDR (DO) + laser pointer | **21**, VCC **3V3** | Stasiun recyclable, dinding sisi sensor, setinggi ±15 mm. Laser dan LDR berdampingan, LDR menangkap pantulan dari kertas. Beri tudung agar cahaya ruangan tidak masuk. Setel potensiometer saat `$CAL,ON` |
| (Raindrop sensor) | 22 | Tidak dipasang (`USE_RAINDROP 0`) |
| Induktif LJ12A3-4-Z/BX (NPN) | **34** lewat PC817 | Jarak deteksi hanya 4 mm: pasang di dinding penyempit, rata dengan permukaan dinding, tepat di lintasan sampah. Jangan di bawah sabuk |
| Kapasitif LJC18A3-H-Z/BY (PNP) | **35** lewat PC817 | Di dinding penyempit, stasiun organik. Setel potensiometer agar botol plastik kosong tidak terdeteksi |
| Capacitive soil moisture | **36** (VP), VCC **3V3** | Di bagian yang pasti disentuh sampah |
| Servo pendorong organik | **25** | Daya dari LM2596 #2 (6 V) |
| Servo pendorong logam | **26** | Daya dari LM2596 #2 (6 V) |
| Servo pendorong recyclable | **27** | Daya dari LM2596 #2 (6 V) |

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
| PA0 | — | Tombol RESET (NO) ke GND; INPUT_PULLUP, debounce 50 ms (`PIN_LOCAL_RESET`) |
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
          pemilah    sharp_ir=ok item_di_sabuk=1
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
7. `REQUIRE_LOCAL_RESET` sudah aktif. Setelah E-stop dilepas, tekan tombol
   KEY/RESET (PA0) sebelum START. Isi 0 untuk kembali ke perilaku lama
   (START dari aplikasi sekaligus mereset gangguan).

---

## 4. Protokol UART ESP32 ↔ STM32 & cara parsing

### Format frame

```
$TIPE,field1,field2*CS\n
```

- Diawali `$` dan diakhiri `\n`. Field dipisah koma.
- `CS` = XOR semua byte di antara `$` dan `*`, ditulis dua digit hex.
  Contoh: XOR dari `CMD,START` = `0x26` → frame `$CMD,START*26`.
- Checksum **wajib** (`PP_ALLOW_NO_CHECKSUM 0` di kedua board). Frame tanpa
  `*CS` atau dengan checksum salah dibuang, sehingga derau motor pada kabel
  UART tidak bisa menjalankan perintah yang rusak. Semua pengirim memakai
  `pp_build()`, yang selalu menambahkan checksum.
- Pengecualian hanya konsol USB ESP32 (Serial Monitor), supaya perintah
  seperti `$CAL,ON` atau `$STS,RUN,0` bisa diketik manual. Terminal USB-TTL
  yang tersambung ke UART STM32 harus mengetik checksum, misalnya
  `$CMD,START*26`, `$CMD,STOP*7E`, `$PING*10`.

### Daftar pesan

| Arah | Frame | Arti |
|---|---|---|
| ESP32 → STM32 | `$CMD,START` | Jalankan konveyor. Gangguan link putus ikut direset; tombol darurat dan arus berlebih hanya bisa direset dengan tombol RESET lokal |
| ESP32 → STM32 | `$CMD,STOP` | Hentikan konveyor |
| ESP32 → STM32 | `$PING` | Tanda ESP32 hidup, dikirim tiap 1 detik. Tanpa ini selama 5 detik, STM32 menghentikan konveyor |
| STM32 → ESP32 | `$ACK,START` / `$ACK,STOP` | Perintah dijalankan |
| STM32 → ESP32 | `$NAK,START,ESTOP` | Ditolak: tombol darurat masih ditekan |
| STM32 → ESP32 | `$NAK,START,LOCAL_RESET` | Ditolak: gangguan terkunci, tekan tombol RESET di mesin |
| STM32 → ESP32 | `$STS,RUN,0` | Status tiap 1 detik: `RUN`/`STOP`, lalu kode gangguan |
| STM32 → ESP32 | `$SRT,logam,OK,Kaleng minuman` | Opsional, jika pemilahan dilakukan STM32 |

Kode gangguan: `0` normal · `1` arus berlebih · `2` macet ·
`3` tombol darurat · `4` STM32 kehilangan sinyal ESP32 · `5` tombol darurat
sudah dilepas, menunggu RESET lokal. ESP32 mengubah kode ini menjadi teks di
`system_status.error`, misalnya "Tombol darurat ditekan". Alasan `$NAK`
diteruskan ke `commands/latest/reason` (`ESTOP`, `LOCAL_RESET`), ditambah alasan
dari ESP32 sendiri: `STM_OFFLINE`, `NO_REPLY`, `EXPIRED`, `UNKNOWN`.
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

Salinan STM32 harus identik; uji juga dengan
`firmware/stm32/PilahPintar_STM32/pp_protocol.c` sebagai pengganti file kedua.

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

Perintah yang lebih tua dari 30 detik diabaikan (`FAILED`, reason `EXPIRED`),
supaya ESP32 yang baru menyala tidak menjalankan perintah lama. Jika STM32
membalas `$NAK`, ESP32 menulis `status=FAILED` beserta `reason` (mis.
`LOCAL_RESET`) dan aplikasi langsung menampilkan pesannya tanpa menunggu batas
waktu. Aplikasi menunggu
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
klasifikasi). Pemilah berjalan sebagai task FreeRTOS sendiri di **core 1**
dengan prioritas 20 (`SORTER_TASK_CORE`, `SORTER_TASK_PRIORITY`) dan memeriksa
sensor tiap 5 ms. Wi-Fi dan lwIP Arduino-ESP32 berjalan di core 0, sedangkan
`loop()` (HTTPS ke Firebase) berjalan di core 1 dengan prioritas 1, jadi request
jaringan yang memblok tidak bisa menunda tick pemilah.

Bukti di pengujian: dalam mode normal, ESP32 mencetak satu baris CSV tiap
10 detik (`SORTER_JITTER_LOG 1`):

```
JIT,epoch_ms,millis,ticks,max_period_us,max_late_us,max_exec_us,late_over_1ms
```

`max_late_us` = selisih terburuk periode terhadap 5000 µs, `max_exec_us` =
waktu eksekusi `tick()` terlama, `late_over_1ms` = jumlah tick yang terlambat
lebih dari 1 ms. Rekam selama Wi-Fi sibuk (heartbeat, polling perintah,
laporan pemilahan) untuk menunjukkan jitter tetap kecil. Pemilah hanya bekerja saat STM32
melaporkan konveyor berjalan.

Ada dua mode, dipilih dengan `SORT_MODE_PER_SENSOR` di `config.h`.

### Mode satu sensor, satu servo (`SORT_MODE_PER_SENSOR 1`, bawaan)

Setiap servo punya sensor sendiri yang dipasang tepat **sebelum** servonya,
dengan urutan di sepanjang sabuk:

```
corong → [induktif]→servo logam → [soil moisture + kapasitif]→servo organik
       → [Sharp IR + LDR/laser]→servo recyclable → ujung sabuk (anorganik & lainnya)
```

| Stasiun | Sensor pemicu | Servo | Syarat |
|---|---|---|---|
| 1 | Induktif LJ12A3-4-Z | Logam, GPIO 26 | aktif ≥ `STATION_MIN_ACTIVE_MS` |
| 2 | Soil moisture (≤ `SOIL_WET_RAW`) atau kapasitif | Organik, GPIO 25 | aktif ≥ `STATION_MIN_ACTIVE_MS` |
| 3 | Sharp IR (samping, setinggi ±45 mm) **atau** LDR + laser terang (±15 mm) | Recyclable, GPIO 27 | sinar Sharp terpotong (botol) atau pantulan laser kuat (kertas), ≥ `STATION_MIN_ACTIVE_MS` |
| 4 | Tidak ada sensor (ujung sabuk) | tidak ada | anorganik & sampah lain yang tidak terdeteksi; jatuh di ujung sabuk, **tidak tercatat** di aplikasi |

Semua sensor dipasang di **satu sisi**, yaitu dinding tempat crank slider
berada. Dinding penyempit harus mengarahkan setiap sampah agar bergesekan
dengan dinding sisi sensor; tempat sampah ada di sisi seberang.

Servo bergerak pada `saat terdeteksi + STATION_*_SENSOR_TO_PUSHER_MM ÷
BELT_SPEED_MM_S`. Isi jarak itu dengan jarak sensor ke tengah pendoronginya;
isi `0` jika sensor tepat di depan pendorong. Servo tetap bergerak
bergiliran. Stasiun logam sengaja paling depan: kaleng sudah terdorong
sebelum sampai ke sensor kapasitif dan sensor kelembapan di stasiun organik
(`STATION_ORGANIK_USE_CAPACITIVE 1`). Setel potensiometer sensor kapasitif
supaya botol plastik kosong tidak memicunya. LDR + laser dipasang di stasiun
recyclable untuk kertas (`STATION_RECYCLABLE_USE_LDR 1`); setel potensiometer
modul LDR agar kertas putih = `ldr=1`, sedangkan kresek dan sabuk kosong = `ldr=0`.

Saat `$CAL,ON`, setiap deteksi mencetak `[STASIUN] ...` dan baris
`CSV,servo,lama_ms,tinggi_mm,ldr,induktif,kapasitif,soil,raindrop`.

### Mode zona gabungan (`SORT_MODE_PER_SENSOR 0`): alur satu item

1. Item masuk zona sensor: salah satu sensor aktif (Sharp IR melihat benda,
   induktif/kapasitif LOW, soil moisture ≤ `SOIL_WET_RAW`, atau raindrop basah).
2. Selama di zona, ciri dikumpulkan: tinggi maksimum dari Sharp IR, pantulan
   laser dari LDR, induktif, kapasitif, raindrop, dan soil moisture terendah.
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
| 2 | Soil moisture ≤ `SOIL_WET_RAW` atau raindrop basah | organik |
| 3 | Tinggi ≥ `BOTTLE_MIN_HEIGHT_MM` dan LDR terang (`STYROFOAM_BY_LDR 1`) | anorganik (styrofoam) |
| 3 | Tinggi ≥ `BOTTLE_MIN_HEIGHT_MM` | recyclable (botol) |
| 4 | Kapasitif aktif (`CAPACITIVE_MEANS_ORGANIC 1`) | organik |
| 5 | Tinggi ≤ `PAPER_MAX_HEIGHT_MM` dan LDR terang (`PAPER_BY_LDR 1`) | recyclable (kertas) |
| 6 | Selain itu | anorganik (residu) |

Aturan styrofoam dan kertas **mati secara bawaan** (`0`), karena ambang LDR
hanya bisa disetel di alat Anda (potensiometer modul LDR). Sebelum
dikalibrasi, kertas akan masuk anorganik.

### Cek sensor soil moisture saja

Sketch [`esp32/SoilMoistureTest`](esp32/SoilMoistureTest/SoilMoistureTest.ino)
hanya butuh board ESP32 dan sensor soil (VCC 3V3, GND, AOUT ke GPIO 36),
tanpa Wi-Fi atau sensor lain. Buka di Arduino IDE, pilih board **ESP32 Dev
Module**, upload, lalu buka Serial Monitor 115200 baud:

```
raw=2874 (2861-2890)  2342 mV  basah   1%  kering            | sesi min=2860 maks=2890
raw=1612 (1598-1630)  1325 mV  basah  93%  BASAH -> organik  | sesi min=1598 maks=2890
```

- Tempelkan sensor ke sampah kering, ketik `k` + Enter. Lalu tempelkan ke
  sisa makanan basah, ketik `b` + Enter. Sketch menyarankan nilai
  `SOIL_WET_RAW` untuk `config.h`.
- Peringatan `!!` muncul jika kabel AOUT lepas (nilai melompat-lompat), AOUT
  tersambung ke GND (~0), atau sensor diberi 5 V (mentok 4095).
- Ketik `p` untuk tampilan grafik di **Tools → Serial Plotter**.

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
   [CAL] sharp=302mm (kosong) 980mV | ldr=0 induktif=0 kapasitif=0 soil=2875 raindrop=0
   ```

   Saat sabuk kosong, isi `SHARP_SIDE_EMPTY_DISTANCE_MM` dengan nilai `sharp=`
   (mode samping; mode atas: `SHARP_BELT_DISTANCE_MM`). Lewatkan botol: harus
   muncul `TERPOTONG`; kresek pipih: tetap `kosong`. Lalu
   pastikan induktif dan kapasitif 0. Letakkan kertas putih di
   bawah laser lalu putar potensiometer modul LDR sampai `ldr=1`; dengan
   kresek atau plastik bening harus kembali `ldr=0`. Jika jarak Sharp IR
   meleset dari penggaris, sesuaikan `SHARP_CURVE_A` / `SHARP_CURVE_B`.
4. **Kumpulkan data**: lewatkan 10–20 sampel per kategori melalui zona sensor
   (dengan konveyor berjalan, atau digeser dengan tangan saat konveyor diam).
   Untuk setiap item muncul baris:

   ```
   CSV,420,62,0,0,0,2810,0,recyclable,Botol (tinggi)
   ```

   Kolomnya: lama di zona (ms), tinggi (mm), LDR terang, induktif,
   kapasitif, soil terendah, raindrop, kategori, alasan. Salin semua baris `CSV,` ke
   Excel, lalu tentukan ambang yang paling memisahkan kategori, misalnya
   tinggi botol vs gelas plastik. **Pakai sampel yang berbeda** untuk uji akurasi
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
   Checksum wajib: ketik `$CMD,START*26` (bukan `$CMD,START`).
3. Lepas kabel PB12 (atau tekan E-stop): motor berhenti dan muncul
   `$STS,STOP,3`. Pasang lagi: muncul `$STS,STOP,5` dan `$CMD,START*26` dibalas
   `$NAK,START,LOCAL_RESET`. Tekan tombol KEY/RESET (PA0): muncul
   `$STS,STOP,0`, motor tetap diam, lalu `$CMD,START*26` diterima.
4. Tanpa `$PING*10`, motor berhenti setelah 5 detik dengan `$STS,STOP,4`. Ini
   memang perilaku keamanannya. Untuk uji lebih lama, ketik `$PING` berkala
   atau set `LINK_TIMEOUT_MS 0` sementara.

**Tahap 4: semua tersambung.** Ketik `$SIM,OFF` di Serial Monitor ESP32,
sambungkan UART, lalu uji START/STOP dari aplikasi, pemilahan dengan sabuk
berjalan, dan tombol darurat. Saat E-stop ditekan, aplikasi menampilkan
"Tombol darurat ditekan" dan item yang masih di sabuk dilaporkan gagal. Setelah
E-stop dilepas, START dari aplikasi harus menampilkan "Reset tombol di mesin
diperlukan" sampai tombol RESET ditekan.

---

## 9. Masalah umum

| Gejala | Penyebab & solusi |
|---|---|
| Aplikasi tetap "Menunggu koneksi ke perangkat." | ESP32 belum pernah menulis `system_status`. Lihat Serial Monitor: Wi-Fi gagal? Login Firebase gagal (`fb=belum`)? |
| `Login Firebase gagal (... 400 ...)` | Email/password akun perangkat salah, atau Email/Password belum di-enable di Authentication |
| `PATCH 401` / `Permission denied` | Rules belum dipublish, ESP32 belum login, atau UID akun ESP32 belum ada di `/devices` |
| Aplikasi "Offline" padahal ESP32 menyala | Heartbeat gagal terkirim, cek pesan `[FB] heartbeat gagal`. Pastikan Wi-Fi 2,4 GHz |
| Error "STM32 tidak merespons" | Kabel TX/RX tertukar, GND tidak tersambung, atau baud rate berbeda |
| Kapasitas selalu 0% atau 100% | Kalibrasi `BIN_EMPTY_DISTANCE_CM` / `BIN_FULL_DISTANCE_CM`; lihat nilai `jarak=` di Serial Monitor |
| Kapasitas tidak muncul ("Data unavailable") | Sensor tidak terbaca (`sensor belum terbaca`), periksa wiring dan pembagi tegangan ECHO |
| Perintah START "FAILED" | STM32 tidak membalas `$ACK` dalam 3 detik (`NO_REPLY`), tombol darurat aktif (`ESTOP`), atau menunggu reset lokal (`LOCAL_RESET`) |
| Aplikasi selalu "Tombol darurat ditekan" | Tombol E-stop belum terpasang atau kontak NC2 putus. Periksa kabel PB12–GND; lepaskan tombol (putar), tekan RESET (PA0), lalu START |
| "Reset tombol di mesin diperlukan" | Gangguan tombol darurat/arus berlebih masih terkunci. Pastikan sabuk aman, tekan tombol RESET (PA0) di mesin, lalu START |
| `[STM] frame ditolak (kode 2)` | Frame UART tanpa checksum atau checksum salah. Periksa GND bersama dan jauhkan kabel UART dari kabel motor |
| `sharp_ir=GAGAL` / `sharp=--` terus | Cek VCC 5 V, GND, dan kabel output ke GPIO 39. Pastikan sensor ≥ 10 cm dari sabuk (di bawah 10 cm kurvanya berbalik) |
| `[CAL] ldr=1` terus | Putar potensiometer modul LDR sampai 0 saat tidak ada benda; pastikan tudung LDR menghalangi cahaya ruangan |
| `[CAL] induktif=1` / `kapasitif=1` terus padahal tidak ada benda | Resistor pull-up 10 kΩ belum dipasang, atau sensor mendeteksi rangka besi di dekatnya |
| `sensor aktif terus > 5000 ms` | Ada sampah tersangkut, sisa makanan menempel di sensor soil, atau ambang salah. Sensor itu diabaikan sampai normal kembali |
| `terlambat ... ke pendorong` | Item baru selesai diklasifikasi setelah lewat pendorong. Jauhkan pendorong organik dari zona sensor, perlambat sabuk, atau perkecil `ITEM_GAP_MS` |
| Pendorong mendorong terlalu cepat / terlambat | `BELT_SPEED_MM_S` atau jarak pendorong salah. Ukur ulang (bagian 6) |
| `pendorong ... masih bergerak, item terlewat` | Dua item untuk pendorong yang sama terlalu dekat. Perbaiki singulation atau percepat servo |
| ESP32 restart saat servo bergerak (`Brownout detector was triggered`) | Servo masih mengambil daya dari jalur ESP32. Pakai LM2596 kedua (6 V) terpisah, kapasitor 1000 µF, dan biarkan `SERVO_DETACH_WHEN_IDLE 1` |

**Catatan keamanan prototype.** ESP32 memakai HTTPS tanpa verifikasi
sertifikat (`setInsecure()`). Untuk tahap lanjut, pasang root CA Google
dengan `client_.setCACert(...)` di `firebase_rtdb.cpp`.
