#!/usr/bin/env python3
"""用 Skyfield 生成月掩星对照数据（M5 验收：至少 20 次，时刻差 ≤ 5 秒）。

用法（需要 skyfield，不进 CI）：
  python tools/skyfield/gen_occultations.py data/de440s.bsp

恒星参数从 crates/guanxiang-core/src/stars_table.rs 读取，保证与本库输入相同。
掩始、掩终定义为月面边缘（k = 0.2725076）经过目标中心，站心视位置，不考虑是否在地平线上。
做法：每天算一次地心角距，找出 < 1.6° 的极小；在其 ±0.3 天内以 3 分钟步长用 find_discrete 求解。
每个事件记录 Skyfield 在该时刻使用的 ΔT，测试时按同一 ΔT 计算。

输出：crates/guanxiang-core/tests/fixtures/skyfield/occultations.csv
"""

import csv
import os
import re
import sys

import numpy as np
import skyfield
from skyfield.api import Angle, Star, load, load_file, wgs84
from skyfield.searchlib import find_discrete

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "crates", "guanxiang-core", "tests", "fixtures", "skyfield", "occultations.csv")
TABLE = os.path.join(ROOT, "crates", "guanxiang-core", "src", "stars_table.rs")

MOON_RADIUS_KM = 0.2725076 * 6378.137
STARS = [65474, 80763, 49669, 21421]  # 角宿一、心宿二、轩辕十四、毕宿五
PLANETS = {"venus": "venus barycenter", "mars": "mars barycenter", "jupiter": "jupiter barycenter", "saturn": "saturn barycenter"}
SITES = [
    ("nanshan", 43.4711, 87.1778, 2080.0),
    ("paranal", -24.6272, -70.4044, 2635.0),
    ("tromso", 69.6496, 18.9560, 100.0),
]
JD0, JD1 = 2460310.5, 2462867.5  # 2024-01-01 至 2031-01-01（TT）


def load_stars(ts):
    text = open(TABLE, encoding="utf-8").read()
    out = {}
    for m in re.finditer(
        r"hip: (\d+),.*?ra_deg: ([-\d.]+), dec_deg: ([-\d.]+), parallax_mas: ([-\d.]+), pm_ra_mas: ([-\d.]+), pm_dec_mas: ([-\d.]+)",
        text,
    ):
        hip = int(m[1])
        if hip in STARS:
            out[hip] = Star(
                ra=Angle(degrees=float(m[2])),
                dec=Angle(degrees=float(m[3])),
                parallax_mas=max(float(m[4]), 1e-6),
                ra_mas_per_year=float(m[5]),
                dec_mas_per_year=float(m[6]),
                epoch=ts.tt_jd(2448349.0625),
            )
    return out


def main() -> None:
    eph = load_file(sys.argv[1])
    ts = load.timescale(builtin=True)
    earth, moon = eph["earth"], eph["moon"]
    stars = load_stars(ts)
    targets = [(f"HIP {h}", stars[h]) for h in STARS] + [(n, eph[k]) for n, k in PLANETS.items()]

    days = ts.tt_jd(np.arange(JD0, JD1, 1.0))
    rows = []
    for name, target in targets:
        e = earth.at(days)
        geo = e.observe(moon).apparent().separation_from(e.observe(target).apparent()).degrees
        minima = [i for i in range(1, len(geo) - 1) if geo[i] <= geo[i - 1] and geo[i] < geo[i + 1] and geo[i] < 1.6 + 6.5]
        # 每天一点只能粗略定位，阈值放宽到 8° 后再在窗口内精确判断
        for site, lat, lon, h in SITES:
            obs = earth + wgs84.latlon(lat, lon, elevation_m=h)

            def inside(t, target=target, obs=obs):
                a = obs.at(t)
                m = a.observe(moon).apparent()
                s = a.observe(target).apparent()
                sm = np.arcsin(MOON_RADIUS_KM / m.distance().km)
                return m.separation_from(s).radians < sm

            inside.step_days = 0.002
            for i in minima:
                t0 = days.tt[i]
                times, values = find_discrete(ts.tt_jd(t0 - 1.3), ts.tt_jd(t0 + 1.3), inside, epsilon=1e-3 / 86400)
                pending = None
                for t, v in zip(times, values):
                    if v:
                        pending = t
                    elif pending is not None:
                        if JD0 <= pending.tt < JD1:
                            rows.append([site, lat, lon, h, name, f"{pending.tt:.9f}", f"{t.tt:.9f}", f"{float(pending.delta_t):.6f}"])
                        pending = None
        print(f"{name}: {sum(1 for r in rows if r[4] == name)}", file=sys.stderr)

    rows.sort(key=lambda r: (r[4], r[0], r[5]))
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write(f"# skyfield {skyfield.__version__}\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["site", "lat_deg", "lon_deg", "height_m", "target", "jd_tt_disappearance", "jd_tt_reappearance", "delta_t_s"])
        w.writerows(rows)
    print(f"共 {len(rows)} 次", file=sys.stderr)


if __name__ == "__main__":
    main()
