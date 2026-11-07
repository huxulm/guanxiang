#!/usr/bin/env python3
"""用 Skyfield 生成日月出没、晨昏蒙影和月相的对照数据。

定义与 guanxiang-core 的 events::almanac 相同（也与 USNO 相同）：
- 日出日落、月出月落：中心站心几何高度 = −(34′ + 视半径)，太阳半径 695700 km、月球 1737.4 km；
- 民用/航海/天文晨昏：太阳中心几何高度 −6°/−12°/−18°。
高度用 Skyfield 的站心视位置（observe().apparent().altaz()，不含折射），交点用 find_discrete 求。

用法（需要 skyfield，不进 CI）：
  python tools/skyfield/gen_almanac.py data/de440s.bsp

输出到 crates/guanxiang-core/tests/fixtures/skyfield/：
- almanac_events.csv：5 个地点、2026 年每月 1 日和 15 日（UTC 0 时起 24 小时）的全部出没和晨昏；
  记录 Skyfield 的 ΔT，测试按同一 ΔT 计算。
- moon_phase.csv：同样时刻的月球照亮比例和日月视黄经差（地心）。
- sublunar.csv：月下点（地心视位置在 ITRS 中的球面纬度和经度，不含极移），取 2025–2029 年
  几次月食前后每小时一个时刻；记录 Skyfield 的 ΔT。月食可见区域图用它。
"""

import csv
import os
import sys
import numpy as np

import skyfield
from skyfield import almanac
from skyfield.api import load, load_file, wgs84
from skyfield.framelib import itrs
from skyfield.searchlib import find_discrete

FIX = os.path.join(os.path.dirname(__file__), "..", "..", "crates", "guanxiang-core", "tests", "fixtures", "skyfield")

SITES = [
    # 名称、纬度、经度、海拔（m）
    ("beijing", 39.9042, 116.4074, 44.0),
    ("sydney", -33.8688, 151.2093, 58.0),
    ("quito", -0.1807, -78.4678, 2850.0),
    ("reykjavik", 64.1466, -21.9426, 20.0),
    # 北极圈内：有极昼、极夜，晨昏可能整天都不发生
    ("tromso", 69.6492, 18.9553, 10.0),
]

REFRACTION = 34.0 / 60.0
SUN_RADIUS_KM = 695_700.0
MOON_RADIUS_KM = 1_737.4

# (天体, 阈值类型, 上升事件, 下降事件)；阈值为数字时是固定高度（度），为半径时按上边缘
CRITERIA = [
    ("sun", SUN_RADIUS_KM, "sunrise", "sunset"),
    ("sun", -6.0, "civil_dawn", "civil_dusk"),
    ("sun", -12.0, "nautical_dawn", "nautical_dusk"),
    ("sun", -18.0, "astronomical_dawn", "astronomical_dusk"),
    ("moon", MOON_RADIUS_KM, "moonrise", "moonset"),
]


def main() -> None:
    eph = load_file(sys.argv[1])
    ts = load.timescale(builtin=True)
    earth = eph["earth"]
    bodies = {"sun": eph["sun"], "moon": eph["moon"]}
    os.makedirs(FIX, exist_ok=True)
    note = f"# skyfield {skyfield.__version__}\n"

    days = [(m, d) for m in range(1, 13) for d in (1, 15)]

    with open(os.path.join(FIX, "almanac_events.csv"), "w", newline="") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["site", "lat_deg", "lon_deg", "height_m", "start_jd_tt", "end_jd_tt", "delta_t_s", "kind", "jd_tt"])
        for site, lat, lon, h in SITES:
            observer = earth + wgs84.latlon(lat, lon, elevation_m=h)
            for month, day in days:
                t0 = ts.utc(2026, month, day)
                t1 = ts.utc(2026, month, day + 1)
                for body, horizon, rising, setting in CRITERIA:
                    target = bodies[body]

                    def above(t, target=target, horizon=horizon, body=body):
                        alt, _, dist = observer.at(t).observe(target).apparent().altaz()
                        if body == "sun" and horizon < 0:
                            h0 = horizon
                        else:
                            h0 = -(REFRACTION + np.degrees(np.arcsin(horizon / dist.km)))
                        return alt.degrees > h0

                    above.step_days = 1.0 / 144.0  # 10 分钟
                    times, ups = find_discrete(t0, t1, above)
                    for t, up in zip(times, ups):
                        w.writerow([site, lat, lon, h, f"{t0.tt:.8f}", f"{t1.tt:.8f}", f"{float(t0.delta_t):.6f}",
                                    rising if up else setting, f"{t.tt:.8f}"])

    with open(os.path.join(FIX, "moon_phase.csv"), "w", newline="") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["jd_tt", "illuminated_fraction", "longitude_difference_deg"])
        for month, day in days:
            for hour in (0, 12):
                t = ts.utc(2026, month, day, hour)
                k = almanac.fraction_illuminated(eph, "moon", t)
                phase = almanac.moon_phase(eph, t).degrees
                w.writerow([f"{t.tt:.8f}", f"{float(k):.10f}", f"{float(phase):.8f}"])

    with open(os.path.join(FIX, "sublunar.csv"), "w", newline="") as f:
        f.write(note)
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["jd_tt", "delta_t_s", "lat_deg", "lon_deg"])
        # 几次月食的食甚日期（UTC），每次前后各 4 小时
        for y, mo, d, h in [(2025, 9, 7, 18), (2026, 3, 3, 11), (2028, 12, 31, 17), (2029, 6, 26, 3)]:
            for dh in range(-4, 5):
                t = ts.utc(y, mo, d, h + dh)
                lat, lon, _ = earth.at(t).observe(eph["moon"]).apparent().frame_latlon(itrs)
                w.writerow([f"{t.tt:.8f}", f"{float(t.delta_t):.6f}", f"{lat.degrees:.8f}", f"{lon.degrees:.8f}"])


if __name__ == "__main__":
    main()
