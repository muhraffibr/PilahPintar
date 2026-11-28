"""Rekam output Serial ESP32 ke file teks untuk pengujian jaringan.

Contoh:
    python tools/network_test/log_serial.py --port COM5 --out logs/e1.txt --minutes 30

Berhenti otomatis setelah --minutes, atau tekan Ctrl+C. Semua baris disimpan
apa adanya; ringkasan jumlah baris NET/CMD/SRT ditampilkan setiap 10 detik.
"""
import argparse
import time
from pathlib import Path

import serial


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", required=True, help="port Serial ESP32, mis. COM5")
    ap.add_argument("--out", required=True, help="file log tujuan, mis. logs/e1.txt")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--minutes", type=float, default=0, help="lama rekam (0 = sampai Ctrl+C)")
    args = ap.parse_args()

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    counts = {"NET": 0, "CMD": 0, "CMDDONE": 0, "SRTOK": 0, "SRTDROP": 0, "WIFI": 0}
    start = time.time()
    last_report = start
    last_rssi = "-"

    with serial.Serial(args.port, args.baud, timeout=1) as port, out.open("a", encoding="utf-8") as f:
        print(f"Merekam {args.port} -> {out} (Ctrl+C untuk berhenti)")
        try:
            while True:
                raw = port.readline()
                if raw:
                    line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                    f.write(line + "\n")
                    tag = line.split(",", 1)[0]
                    if tag in counts:
                        counts[tag] += 1
                        if tag == "NET":
                            parts = line.split(",")
                            if len(parts) >= 7:
                                last_rssi = parts[6]
                    elif line.startswith("["):
                        print(line)
                now = time.time()
                if now - last_report >= 10:
                    last_report = now
                    f.flush()
                    summary = " ".join(f"{k}={v}" for k, v in counts.items())
                    print(f"[{(now - start) / 60:5.1f} mnt] {summary} rssi={last_rssi} dBm")
                if args.minutes and now - start >= args.minutes * 60:
                    break
        except KeyboardInterrupt:
            pass
    print(f"Selesai. Tersimpan di {out}")


if __name__ == "__main__":
    main()
