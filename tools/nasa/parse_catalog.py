#!/usr/bin/env python3
"""把 NASA（Espenak & Meeus）五千年日月食星表的网页转成 CSV 对照数据。

来源：
  https://eclipse.gsfc.nasa.gov/SEcat5/SE2001-2100.html
  https://eclipse.gsfc.nasa.gov/LEcat5/LE2001-2100.html

用法：
  python tools/nasa/parse_catalog.py SE2001-2100.html LE2001-2100.html

输出到 crates/guanxiang-core/tests/fixtures/nasa/：
- solar_2001_2100.csv：date, td（食甚，TD）, delta_t, type（如 T、A、H、P、A-、T+）, gamma, magnitude,
  食甚点 lat_deg、lon_deg（NASA 取整到 1°）、sun_alt_deg、width_km、duration_s（中心食在食甚点的持续时间）
- lunar_2001_2100.csv：date, td（食甚，TD）, delta_t, type（N、P、T 及后缀）, gamma, pen_mag, um_mag

NASA 星表用 VSOP87/ELP-2000-82 和自己的 ΔT 模型，秒级差异不一定是错误（见 docs/PLAN.md）。
只用标准库。
"""

import csv
import html
import os
import re
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "crates", "guanxiang-core", "tests", "fixtures", "nasa")
MONTHS = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}

LINE = re.compile(
    r"^\s*(\d{5})\s+(-?\d{4}) (\w{3}) (\d{2})\s+(\d{2}:\d{2}:\d{2})\s+(-?\d+)\s+(-?\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(.*)$"
)


def lines(path):
    text = open(path, encoding="latin-1").read()
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    for raw in text.splitlines():
        m = LINE.match(raw)
        if m:
            yield m


def main() -> None:
    se_path, le_path = sys.argv[1], sys.argv[2]
    os.makedirs(OUT, exist_ok=True)

    with open(os.path.join(OUT, "solar_2001_2100.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write("# NASA Five Millennium Canon of Solar Eclipses, 2001-2100 (eclipse.gsfc.nasa.gov)\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["date", "td", "delta_t", "type", "gamma", "magnitude", "lat_deg", "lon_deg", "sun_alt_deg", "width_km", "duration_s"])
        n = 0
        for m in lines(se_path):
            date = f"{m[2]}-{MONTHS[m[3]]:02d}-{m[4]}"
            rest = m[11].split()
            # rest：Gamma Mag Lat Long ...（QLE 已在第 10 组）
            gamma, mag = rest[0], rest[1]
            lat = float(rest[2][:-1]) * (1 if rest[2][-1] == "N" else -1)
            lon = float(rest[3][:-1]) * (1 if rest[3][-1] == "E" else -1)
            alt = rest[4]
            width = rest[5] if len(rest) > 5 and rest[5].isdigit() else ""
            dur = ""
            for tok in rest[5:]:
                dm = re.fullmatch(r"(\d+)m(\d+)s", tok)
                if dm:
                    dur = str(int(dm[1]) * 60 + int(dm[2]))
            w.writerow([date, m[5], m[6], m[9], gamma, mag, lat, lon, alt, width, dur])
            n += 1
        print(f"solar: {n}", file=sys.stderr)

    with open(os.path.join(OUT, "lunar_2001_2100.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write("# NASA Five Millennium Canon of Lunar Eclipses, 2001-2100 (eclipse.gsfc.nasa.gov)\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["date", "td", "delta_t", "type", "gamma", "pen_mag", "um_mag"])
        n = 0
        for m in lines(le_path):
            date = f"{m[2]}-{MONTHS[m[3]]:02d}-{m[4]}"
            rest = m[11].split()
            # rest：Gamma PenMag UmMag ...（QSE 已在第 10 组）
            gamma, pen, um = rest[0], rest[1], rest[2]
            w.writerow([date, m[5], m[6], m[9], gamma, pen, um])
            n += 1
        print(f"lunar: {n}", file=sys.stderr)


if __name__ == "__main__":
    main()
