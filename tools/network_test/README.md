# Pengujian jaringan ESP32 ↔ Firebase ↔ aplikasi (data paper)

Cukup **satu board ESP32 klasik** yang tersambung USB ke laptop. Sensor, servo,
konveyor, dan STM32 tidak perlu dipasang: firmware mode uji mensimulasikan
kapasitas tempat sampah, STM32 (virtual), dan event pemilahan, lalu mencatat
setiap request HTTPS sebagai baris CSV.

| Baris log | Isi |
|---|---|
| `NET,epoch_ms,method,node,http_code,duration_ms,rssi_dbm,reused` | satu request HTTPS ke Firebase |
| `CMD,command,issued_at,epoch_ms,delivery_ms` | perintah dari aplikasi terbaca ESP32 |
| `CMDDONE,command,issued_at,epoch_ms,completion_ms,status,written` | status DONE/FAILED tertulis |
| `SRTQ` / `SRTOK` / `SRTDROP` | event pemilahan masuk antrean / tersimpan / dibuang |
| `WIFI,UP\|DOWN,epoch_ms,millis,rssi_dbm` | perubahan koneksi Wi-Fi |

## 1. Persiapan (sekali)

1. **Firebase**: buat project, Realtime Database, dan akun perangkat
   (langkah di [firmware/README.md](../../firmware/README.md#1-siapkan-firebase-sekali-saja)).
2. **Aplikasi**: isi `firebase_config.json`, build APK mode Firebase
   (`.\tools\build_apk.ps1 -Firebase`), lalu pasang di HP.
3. **Firmware**: salin `secrets.example.h` menjadi `secrets.h` (Wi-Fi 2,4 GHz
   dan data Firebase). Di `config.h` ubah `NETWORK_TEST_MODE` menjadi `1`.
4. Upload ke ESP32 (Board: **ESP32 Dev Module**). Cek di Serial Monitor
   muncul `MODE UJI JARINGAN` dan `wifi=ok fb=ok`, lalu **tutup Serial
   Monitor** (port tidak bisa dipakai dua program sekaligus).
5. Di aplikasi, tekan **START** satu kali. Konveyor virtual berjalan dan
   event `TEST #n` dibuat setiap 5 detik.

Catat untuk Section V paper: model HP + versi Android, model router/hotspot,
lokasi, kecepatan internet (mis. dari speedtest), dan region database.

## 2. Menjalankan skenario

Ganti `COM5` dengan port ESP32 kamu (lihat di Arduino IDE → Tools → Port).

| ID | Langkah | Perintah rekam |
|---|---|---|
| **E1** | ESP32 dekat router, biarkan berjalan 30 menit | `python tools/network_test/log_serial.py --port COM5 --out logs/e1.txt --minutes 30` |
| **E2** | Rekam, lalu tekan START/STOP bergantian 30 kali di aplikasi; tunggu status berubah sebelum menekan lagi | `... --out logs/e2.txt` (Ctrl+C setelah selesai) |
| **E3** | Tanpa rekam. Cabut USB ESP32, ukur dengan stopwatch sampai aplikasi menampilkan **Offline**, colok lagi. Ulangi 10 kali dan catat hasilnya | – |
| **E4** | Rekam, tunggu 1 menit, **matikan router/hotspot 1 menit**, nyalakan lagi, tunggu 2 menit, Ctrl+C. Ulangi dengan putus **5 menit** | `... --out logs/e4_1min.txt` lalu `logs/e4_5min.txt` |
| **E5** | Rekam 10 menit di 3 posisi: dekat (RSSI ±−50 dBm), sedang (±−67), jauh (±−80). RSSI tampil di ringkasan perekam | `... --out logs/e5_dekat.txt --minutes 10` (lalu `e5_sedang`, `e5_jauh`) |
| **E6** | Firebase Console → Realtime Database → **Usage**: catat download hari itu dan berapa jam ESP32 menyala | – |

Pastikan aplikasi tetap dalam keadaan START (konveyor virtual berjalan)
selama E1, E4, dan E5, supaya request `POST sortings` ikut terukur.

## 3. Mengolah hasil

```bash
python tools/network_test/analyze_netlog.py E1=logs/e1.txt E2=logs/e2.txt E4-1min=logs/e4_1min.txt E4-5min=logs/e4_5min.txt E5-dekat=logs/e5_dekat.txt E5-sedang=logs/e5_sedang.txt E5-jauh=logs/e5_jauh.txt --out hasil
```

Hasilnya di folder `hasil/`:

- `results.md`: tabel latensi per request (Tabel IV), latensi perintah, putus
  koneksi (Tabel V), pengaruh RSSI, dan porsi tiap jenis request.
- `fig3_cdf.png`: Fig. 3 (CDF latensi request).
- `fig4_rssi.png`: Fig. 4 (latensi dan kegagalan vs RSSI).

Kirim folder `hasil/`, catatan E3 dan E6, serta data testbed untuk dimasukkan
ke Section V–VII paper.

Setelah pengujian selesai, kembalikan `NETWORK_TEST_MODE` ke `0` sebelum
firmware dipakai di alat sungguhan.
