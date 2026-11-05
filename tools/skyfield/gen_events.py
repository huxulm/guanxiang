#!/usr/bin/env python3
"""用 Skyfield 生成事件时刻对照数据（M2 验收：时刻差 ≤ 5 秒）。

用法（需要 skyfield，不进 CI）：
  python tools/skyfield/gen_events.py data/de440s.bsp

输出到 crates/guanxiang-core/tests/fixtures/skyfield/：
- longitude_events.csv：2000–2100 年八大行星与太阳的合、冲（skyfield.almanac.oppositions_conjunctions），
  以及 2024–2028 年月球与金星、木星、土星的合（同样的视黄经定义）。
- separation_minima.csv：2024–2026 年月球与金星、土星不超过 5° 的角距极小（find_minima）。
- transits.csv：21 世纪水星、金星凌日的凌甚时刻与最小角距（find_minima，地心视位置）。
"""

import csv
import os
import sys
from math import pi

import skyfield
from skyfield import almanac
from skyfield.api import load, load_file
from skyfield.framelib import ecliptic_frame
from skyfield.searchlib import find_discrete, find_minima

FIX = os.path.join(os.path.dirname(__file__), "..", "..", "crates", "guanxiang-core", "tests", "fixtures", "skyfield")

PLANETS = {
    "mercury": "mercury barycenter",
    "venus": "venus barycenter",
    "mars": "mars barycenter",
    "jupiter": "jupiter barycenter",
    "saturn": "saturn barycenter",
    "uranus": "uranus barycenter",
    "neptune": "neptune barycenter",
}

# 21 世纪凌日的大致日期（UT），用于限定 find_minima 的区间
TRANSITS = [
    ("mercury", d) for d in [
        "2003-05-07", "2006-11-08", "2016-05-09", "2019-11-11", "2032-11-13", "2039-11-07", "2049-05-07",
        "2052-11-09", "2062-05-10", "2065-11-11", "2078-11-14", "2085-11-07", "2095-05-08", "2098-11-10",
    ]
] + [("venus", "2004-06-08"), ("venus", "2012-06-06")]


def elongation_deg(earth, sun, target, t):
    e = earth.at(t)
    _, slon, _ = e.observe(sun).apparent().frame_latlon(ecliptic_frame)
    _, tlon, _ = e.observe(target).apparent().frame_latlon(ecliptic_frame)
    d = (tlon.degrees - slon.degrees) % 360.0
    return d if d <= 180.0 else 360.0 - d


def main() -> None:
    eph = load_file(sys.argv[1])
    ts = load.timescale(builtin=True)
    earth, sun, moon = eph["earth"], eph["sun"], eph["moon"]
    os.makedirs(FIX, exist_ok=True)
    note = f"# skyfield {skyfield.__version__}\n"

    with open(os.path.join(FIX, "longitude_events.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["kind", "a", "b", "jd_tt"])

        t0, t1 = ts.tt(2000, 1, 1), ts.tt(2100, 1, 1)
        for name, key in PLANETS.items():
            target = eph[key]
            times, _ = find_discrete(t0, t1, almanac.oppositions_conjunctions(eph, target))
            for t in times:
                kind = "conjunction" if elongation_deg(earth, sun, target, t) < 90.0 else "opposition"
                w.writerow([kind, name, "sun", f"{t.tt:.8f}"])
            print(f"{name}: {len(times)}", file=sys.stderr)

        # 月球与行星的合：视黄经差过零
        m0, m1 = ts.tt(2024, 1, 1), ts.tt(2028, 1, 1)
        for name in ["venus", "jupiter", "saturn"]:
            target = eph[PLANETS[name]]

            def side(t, target=target):
                e = earth.at(t)
                _, mlon, _ = e.observe(moon).apparent().frame_latlon(ecliptic_frame)
                _, plon, _ = e.observe(target).apparent().frame_latlon(ecliptic_frame)
                return ((mlon.radians - plon.radians) / pi % 2.0).astype("int8")

            side.step_days = 1.0
            times, values = find_discrete(m0, m1, side)
            n = 0
            for t, v in zip(times, values):
                if v == 0:  # 1 → 0：黄经差从 2π 侧穿过 0，即合
                    w.writerow(["conjunction", "moon", name, f"{t.tt:.8f}"])
                    n += 1
            print(f"moon-{name}: {n}", file=sys.stderr)

    # 月球与金星、土星的角距极小（2024–2026，≤ 5°）
    with open(os.path.join(FIX, "separation_minima.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["a", "b", "jd_tt", "separation_deg"])
        for name in ["venus", "saturn"]:
            target = eph[PLANETS[name]]

            def msep(t, target=target):
                e = earth.at(t)
                return e.observe(moon).apparent().separation_from(e.observe(target).apparent()).degrees

            msep.step_days = 1.0
            times, values = find_minima(ts.tt(2024, 1, 1), ts.tt(2027, 1, 1), msep, epsilon=1e-3 / 86400)
            # 容差很小时 find_minima 会对同一个极小返回一串几乎相同的点，按 0.01 天合并
            merged = []
            for jd, v in sorted(zip(times.tt, values)):
                if merged and jd - merged[-1][0] < 0.01:
                    if v < merged[-1][1]:
                        merged[-1] = (jd, v)
                else:
                    merged.append((jd, v))
            for jd, v in merged:
                if v <= 5.0:
                    w.writerow(["moon", name, f"{jd:.8f}", f"{v:.9f}"])

    with open(os.path.join(FIX, "transits.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["planet", "jd_tt_greatest", "min_separation_arcsec"])
        for name, date in TRANSITS:
            target = eph[PLANETS[name]]
            y, mo, d = map(int, date.split("-"))

            def sep(t, target=target):
                e = earth.at(t)
                return e.observe(target).apparent().separation_from(e.observe(sun).apparent()).degrees

            sep.step_days = 0.05
            times, values = find_minima(ts.utc(y, mo, d - 1), ts.utc(y, mo, d + 2), sep, epsilon=1e-3 / 86400)
            # 区间边缘可能出现伪极小，取角距最小的一个
            i = min(range(len(times)), key=lambda k: values[k])
            w.writerow([name, f"{times[i].tt:.8f}", f"{values[i] * 3600:.4f}"])
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
