"""Olah log pengujian jaringan ESP32 menjadi tabel dan grafik untuk paper.

Setiap file log diberi label lewat bentuk LABEL=PATH. Label menentukan skenario:
  E1...  latensi request (Tabel IV, Fig. 3)
  E2...  latensi perintah (Tabel IV)
  E4...  putus koneksi (Tabel V)
  E5...  kekuatan sinyal (Fig. 4), satu file per posisi, mis. E5-dekat, E5-sedang, E5-jauh

Contoh:
    python tools/network_test/analyze_netlog.py E1=logs/e1.txt E2=logs/e2.txt ^
        E4-1min=logs/e4_1min.txt E4-5min=logs/e4_5min.txt ^
        E5-dekat=logs/e5_dekat.txt E5-sedang=logs/e5_sedang.txt E5-jauh=logs/e5_jauh.txt ^
        --out hasil

Hasil di folder --out: results.md (tabel siap salin), fig3_cdf.png, fig4_rssi.png.
"""
import argparse
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402

MAIN_REQUESTS = [
    ("PATCH", "system_status"),
    ("PATCH", "bins"),
    ("POST", "sortings"),
    ("GET", "commands/latest"),
]


def parse(path):
    """Kembalikan dict tag -> list baris (list field) dari satu file log."""
    rows = defaultdict(list)
    for line in Path(path).read_text(encoding="utf-8", errors="replace").splitlines():
        parts = line.strip().split(",")
        tag = parts[0]
        if tag in ("NET", "CMD", "CMDDONE", "SRTQ", "SRTOK", "SRTDROP", "WIFI"):
            rows[tag].append(parts)
    return rows


def net_records(rows):
    out = []
    for p in rows["NET"]:
        if len(p) < 8:
            continue
        try:
            out.append({
                "epoch": int(p[1]), "method": p[2], "node": p[3], "code": int(p[4]),
                "ms": int(p[5]), "rssi": int(p[6]), "reused": p[7] == "1",
            })
        except ValueError:
            continue
    return out


def ok(code):
    return 200 <= code < 300


def stats(values):
    v = np.asarray(values, dtype=float)
    if v.size == 0:
        return None
    return {
        "n": int(v.size), "mean": v.mean(), "sd": v.std(ddof=1) if v.size > 1 else 0.0,
        "median": float(np.median(v)), "p95": float(np.percentile(v, 95)),
        "min": v.min(), "max": v.max(),
    }


def fmt_row(name, s, extra=""):
    if s is None:
        return f"| {name} | - | - | - | - | 0 |{extra}"
    return (f"| {name} | {s['mean']:.0f} | {s['sd']:.0f} | {s['median']:.0f} | "
            f"{s['p95']:.0f} | {s['n']} |{extra}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logs", nargs="+", help="LABEL=PATH")
    ap.add_argument("--out", default="hasil")
    args = ap.parse_args()

    data = {}
    for item in args.logs:
        label, _, path = item.partition("=")
        if not path:
            ap.error(f"format harus LABEL=PATH: {item}")
        data[label] = parse(path)

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.family": "Times New Roman", "font.size": 8})
    md = ["# Hasil pengujian jaringan", ""]

    # ---- E1: latensi per jenis request + volume -------------------------------------
    e1 = [r for label, rows in data.items() if label.upper().startswith("E1") for r in net_records(rows)]
    md += ["## E1 - Latensi request (ms), hanya request yang berhasil", "",
           "| Request | Mean | SD | Median | P95 | n | Gagal (%) |", "|---|---|---|---|---|---|---|"]
    for method, node in MAIN_REQUESTS:
        recs = [r for r in e1 if r["method"] == method and r["node"] == node]
        good = [r["ms"] for r in recs if ok(r["code"])]
        fail = 100.0 * (len(recs) - len(good)) / len(recs) if recs else 0.0
        md.append(fmt_row(f"{method} {node}", stats(good), f" {fail:.1f} |"))
    reused = [r["ms"] for r in e1 if ok(r["code"]) and r["reused"]]
    fresh = [r["ms"] for r in e1 if ok(r["code"]) and not r["reused"]]
    md += ["", "Koneksi TLS dipakai ulang vs koneksi baru (semua jenis request):", "",
           "| Koneksi | Mean | SD | Median | P95 | n |", "|---|---|---|---|---|---|",
           fmt_row("Dipakai ulang", stats(reused)), fmt_row("Baru (handshake TLS)", stats(fresh))]
    if e1:
        hours = (max(r["epoch"] for r in e1) - min(r["epoch"] for r in e1)) / 3.6e6
        if hours > 0:
            md += ["", f"Durasi E1: {hours * 60:.1f} menit, {len(e1)} request "
                       f"({len(e1) / hours:.0f} request/jam, setara {len(e1) / hours * 24:.0f} request/hari)."]
            per_node = defaultdict(int)
            for r in e1:
                per_node[f"{r['method']} {r['node']}"] += 1
            md += ["", "| Request | Jumlah | Porsi (%) |", "|---|---|---|"]
            for k, v in sorted(per_node.items(), key=lambda kv: -kv[1]):
                md.append(f"| {k} | {v} | {100 * v / len(e1):.1f} |")

    # Fig. 3: CDF latensi per jenis request
    fig, ax = plt.subplots(figsize=(3.4, 2.3), dpi=300)
    styles = ["-", "--", "-.", ":"]
    for (method, node), ls in zip(MAIN_REQUESTS, styles):
        v = np.sort([r["ms"] for r in e1 if r["method"] == method and r["node"] == node and ok(r["code"])])
        if v.size:
            ax.plot(v, np.arange(1, v.size + 1) / v.size, ls, color="black", lw=0.9, label=f"{method} {node}")
    ax.set_xlabel("Request latency (ms)")
    ax.set_ylabel("Cumulative probability")
    ax.set_ylim(0, 1.01)
    ax.grid(True, lw=0.3, color="0.8")
    ax.legend(frameon=False, fontsize=7, loc="lower right")
    fig.tight_layout()
    fig.savefig(out / "fig3_cdf.png")
    plt.close(fig)

    # ---- E2: latensi perintah -------------------------------------------------------
    deliver, complete = [], []
    for label, rows in data.items():
        if not label.upper().startswith("E2"):
            continue
        deliver += [int(p[4]) for p in rows["CMD"] if len(p) >= 5 and int(p[4]) >= 0]
        complete += [int(p[4]) for p in rows["CMDDONE"] if len(p) >= 7 and p[5] == "DONE" and p[6] == "1"]
    md += ["", "## E2 - Latensi perintah (ms)", "",
           "| Metrik | Mean | SD | Median | P95 | n |", "|---|---|---|---|---|---|",
           fmt_row("Command delivery", stats(deliver)), fmt_row("Command completion", stats(complete))]

    # ---- E4: putus koneksi ----------------------------------------------------------
    md += ["", "## E4 - Putus koneksi", "",
           "| Log | Event dibuat | Tersimpan | Dibuang | Loss (%) | Putus Wi-Fi (s) | Pulih (s) | Delay maks event (s) |",
           "|---|---|---|---|---|---|---|---|"]
    for label, rows in data.items():
        if not label.upper().startswith("E4"):
            continue
        made, saved, dropped = len(rows["SRTQ"]), len(rows["SRTOK"]), len(rows["SRTDROP"])
        loss = 100.0 * dropped / made if made else 0.0
        downs, recoveries = [], []
        wifi = [(p[1], int(p[2])) for p in rows["WIFI"] if len(p) >= 3 and p[2].isdigit()]
        nets = sorted(net_records(rows), key=lambda r: r["epoch"])
        down_at = None
        for state, t in wifi:
            if state == "DOWN":
                down_at = t
            elif state == "UP":
                if down_at:
                    downs.append((t - down_at) / 1000)
                first_ok = next((r["epoch"] for r in nets if r["epoch"] >= t and ok(r["code"])), None)
                if first_ok:
                    recoveries.append((first_ok - t) / 1000)
                down_at = None
        delays = [int(p[3]) for p in rows["SRTOK"] if len(p) >= 4 and int(p[3]) >= 0]
        md.append(
            f"| {label} | {made} | {saved} | {dropped} | {loss:.1f} | "
            f"{', '.join(f'{d:.0f}' for d in downs) or '-'} | "
            f"{', '.join(f'{r:.1f}' for r in recoveries) or '-'} | "
            f"{max(delays) / 1000:.1f} |" if delays else
            f"| {label} | {made} | {saved} | {dropped} | {loss:.1f} | "
            f"{', '.join(f'{d:.0f}' for d in downs) or '-'} | "
            f"{', '.join(f'{r:.1f}' for r in recoveries) or '-'} | - |")

    # ---- E5: kekuatan sinyal --------------------------------------------------------
    e5 = []
    for label, rows in data.items():
        if not label.upper().startswith("E5"):
            continue
        recs = net_records(rows)
        if not recs:
            continue
        good = [r["ms"] for r in recs if ok(r["code"])]
        e5.append({
            "label": label, "rssi": float(np.mean([r["rssi"] for r in recs])),
            "median": float(np.median(good)) if good else float("nan"),
            "q1": float(np.percentile(good, 25)) if good else float("nan"),
            "q3": float(np.percentile(good, 75)) if good else float("nan"),
            "p95": float(np.percentile(good, 95)) if good else float("nan"),
            "fail": 100.0 * (len(recs) - len(good)) / len(recs), "n": len(recs),
        })
    if e5:
        e5.sort(key=lambda x: -x["rssi"])
        md += ["", "## E5 - Kekuatan sinyal", "",
               "| Posisi | RSSI rata-rata (dBm) | Median (ms) | P95 (ms) | Gagal (%) | n |", "|---|---|---|---|---|---|"]
        for x in e5:
            md.append(f"| {x['label']} | {x['rssi']:.0f} | {x['median']:.0f} | {x['p95']:.0f} | {x['fail']:.1f} | {x['n']} |")
        fig, ax = plt.subplots(figsize=(3.4, 2.3), dpi=300)
        rssi = [x["rssi"] for x in e5]
        med = [x["median"] for x in e5]
        err = [[x["median"] - x["q1"] for x in e5], [x["q3"] - x["median"] for x in e5]]
        ax.errorbar(rssi, med, yerr=err, fmt="o-", color="black", ms=3, lw=0.9, capsize=2,
                    label="Median latency (IQR)")
        ax.set_xlabel("Mean RSSI (dBm)")
        ax.set_ylabel("Request latency (ms)")
        ax.grid(True, lw=0.3, color="0.8")
        ax2 = ax.twinx()
        ax2.plot(rssi, [x["fail"] for x in e5], "s--", color="0.45", ms=3, lw=0.9, label="Failure rate")
        ax2.set_ylabel("Failed requests (%)")
        ax2.set_ylim(bottom=0)
        lines = ax.get_legend_handles_labels()[0] + ax2.get_legend_handles_labels()[0]
        labels = ax.get_legend_handles_labels()[1] + ax2.get_legend_handles_labels()[1]
        ax.legend(lines, labels, frameon=False, fontsize=7, loc="upper right")
        fig.tight_layout()
        fig.savefig(out / "fig4_rssi.png")
        plt.close(fig)

    (out / "results.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    print("\n".join(md))
    print(f"\nTersimpan di {out.resolve()}")


if __name__ == "__main__":
    main()
