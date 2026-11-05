#!/usr/bin/env python3
"""用 Skyfield 生成卫星与太阳、月球接近的对照数据（M6）。

用法（需要 skyfield，不进 CI）：
  python -u tools/skyfield/gen_sat_transits.py data/de440s.bsp [--quick]

  --quick：只算第一颗卫星、第一个测站、1 天，用来估计耗时。

输入：crates/guanxiang-core/tests/fixtures/satellite/omm_iss_css.json（CelesTrak OMM）
输出：crates/guanxiang-core/tests/fixtures/skyfield/sat_approaches.csv

对每颗卫星、每个测站，在根数历元后若干天内：找出过境，过境内每秒计算卫星与日心、月心的角距，
取 < 10° 且目标在地平线上的局部极小；在极小两侧 ±1 秒内以 0.01 秒间隔批量计算一次，
再用抛物线插值得到时刻和角距（精度约 1e-4 秒）。全部批量计算，不逐点调用 Skyfield。

注意：Skyfield 的卫星方向是几何方向（不含光行时和周日光行差），本库包含这两项，
角距会差几角秒、时刻差几毫秒。
"""

import csv
import json
import os
import sys
import time

import numpy as np
import skyfield
from skyfield.api import EarthSatellite, load, load_file, wgs84

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
FIX = os.path.join(ROOT, "crates", "guanxiang-core", "tests", "fixtures")
SITES = [
    ("beijing", 39.9042, 116.4074, 50.0),
    ("nanshan", 43.4711, 87.1778, 2080.0),
    ("kunming", 25.0300, 102.7960, 1990.0),
    ("paranal", -24.6272, -70.4044, 2635.0),
    ("madrid", 40.4168, -3.7038, 650.0),
    ("newyork", 40.7128, -74.0060, 10.0),
]
MAX_SEP_DEG = 10.0


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def separations(sat, topos, earth, body, t):
    """t（向量）时刻卫星与目标的角距（度）和目标高度（度）。"""
    rel = (sat - topos).at(t).position.km
    app = (earth + topos).at(t).observe(body).apparent()
    alt = app.altaz()[0].degrees
    a = rel / np.linalg.norm(rel, axis=0)
    b = app.position.km / np.linalg.norm(app.position.km, axis=0)
    return np.degrees(np.arccos(np.clip((a * b).sum(axis=0), -1, 1))), alt


def main() -> None:
    quick = "--quick" in sys.argv
    eph = load_file(sys.argv[1])
    ts = load.timescale(builtin=True)
    earth, sun, moon = eph["earth"], eph["sun"], eph["moon"]
    with open(os.path.join(FIX, "satellite", "omm_iss_css.json"), encoding="utf-8") as f:
        omms = json.load(f)
    days = 1 if quick else 7
    sites = SITES[:1] if quick else SITES
    if quick:
        omms = omms[:1]

    started = time.time()
    rows = []
    for fields in omms:
        sat = EarthSatellite.from_omm(ts, fields)
        t0 = sat.epoch
        for site, lat, lon, h in sites:
            topos = wgs84.latlon(lat, lon, elevation_m=h)
            rises, sets = [], []
            for day in range(days):
                times, events = sat.find_events(topos, ts.tt_jd(t0.tt + day), ts.tt_jd(t0.tt + day + 1), altitude_degrees=0.0)
                rises += [t for t, e in zip(times, events) if e == 0]
                sets += [t for t, e in zip(times, events) if e == 2]
            n_found = 0
            for r in rises:
                s = next((x for x in sets if x.tt > r.tt), None)
                if s is None or (s.tt - r.tt) * 86400 > 3600:
                    continue
                n = int((s.tt - r.tt) * 86400) + 1
                grid = ts.tt_jd(r.tt + np.arange(n) / 86400.0)
                for bname, body in (("sun", sun), ("moon", moon)):
                    sep, alt = separations(sat, topos, earth, body, grid)
                    idx = [i for i in range(1, n - 1)
                           if sep[i] <= sep[i - 1] and sep[i] < sep[i + 1] and sep[i] < MAX_SEP_DEG and alt[i] > 0]
                    for i in idx:
                        fine = ts.tt_jd(grid.tt[i] + np.arange(-100, 101) * 0.01 / 86400.0)
                        fs, _ = separations(sat, topos, earth, body, fine)
                        k = int(np.clip(np.argmin(fs), 1, len(fs) - 2))
                        y0, y1, y2 = fs[k - 1], fs[k], fs[k + 1]
                        denom = y0 - 2 * y1 + y2
                        off = 0.5 * (y0 - y2) / denom if denom > 0 else 0.0
                        jd = fine.tt[k] + off * 0.01 / 86400.0
                        smin = y1 - 0.25 * (y0 - y2) * off
                        tm = ts.tt_jd(jd)
                        rows.append([fields["NORAD_CAT_ID"], site, lat, lon, h, bname,
                                     f"{jd:.10f}", f"{smin:.7f}", f"{float(tm.delta_t):.6f}"])
                        n_found += 1
            log(f"{fields['OBJECT_NAME']:<14} {site:<8} 过境 {len(rises):>3}  接近 {n_found:>3}  已用 {time.time() - started:6.1f} s")

    if quick:
        log(f"快速模式：共 {len(rows)} 次，用时 {time.time() - started:.1f} s（未写文件）")
        return
    with open(os.path.join(FIX, "skyfield", "sat_approaches.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(f"# skyfield {skyfield.__version__}\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["norad_id", "site", "lat_deg", "lon_deg", "height_m", "body", "jd_tt", "separation_deg", "delta_t_s"])
        w.writerows(rows)
    log(f"共 {len(rows)} 次，用时 {time.time() - started:.1f} s")


if __name__ == "__main__":
    main()
