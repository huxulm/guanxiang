#!/usr/bin/env python3
"""用 Skyfield 生成 IAU 2006/2000A 视位置对照数据。

Horizons 的视位置基于 IAU76/80（加 EOP 改正），与 IAU 2006/2000A 有约 0.05″ 的春分点差，
2027 年以后差异还会随时间增大（见 docs/PLAN.md M1 记录），所以视位置的 0.1″ 验收以 Skyfield 为准。

用法（需要 skyfield，不进 CI）：
  pip install skyfield
  python tools/skyfield/gen_fixtures.py data/de440s.bsp

输出到 crates/guanxiang-core/tests/fixtures/skyfield/：
- geocentric.csv：与 Horizons 地心样本相同的天体和 TT 时刻。
- topocentric.csv：站心，2000–2100 年；记录 Skyfield 使用的 ΔT，测试时按同一 ΔT 计算。
  Skyfield 默认不含极移，与本库一致。
"""

import csv
import os
import random
import sys

import skyfield
from skyfield.api import load, load_file, wgs84

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
FIX = os.path.join(ROOT, "crates", "guanxiang-core", "tests", "fixtures")

NAMES = {
    "sun": "sun",
    "moon": "moon",
    "mercury": "mercury barycenter",
    "venus": "venus barycenter",
    "mars": "mars barycenter",
    "jupiter": "jupiter barycenter",
    "saturn": "saturn barycenter",
    "uranus": "uranus barycenter",
    "neptune": "neptune barycenter",
}
SITES = [
    ("nanshan", 43.4711, 87.1778, 2080.0),
    ("paranal", -24.6272, -70.4044, 2635.0),
    ("tromso", 69.6496, 18.9560, 100.0),
]
TOPO_PER_PAIR = 5
JD_2000 = 2451545.0
JD_2100 = 2488069.5


def main() -> None:
    eph = load_file(sys.argv[1])
    ts = load.timescale(builtin=True)
    earth = eph["earth"]
    out_dir = os.path.join(FIX, "skyfield")
    os.makedirs(out_dir, exist_ok=True)
    header_note = f"# skyfield {skyfield.__version__}"

    # 地心：沿用 Horizons 样本的时刻
    with open(os.path.join(FIX, "horizons", "geocentric.csv"), encoding="utf-8") as f:
        samples = [(r["body"], float(r["jd_tt"])) for r in csv.DictReader(f)]
    with open(os.path.join(out_dir, "geocentric.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(header_note + "\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["body", "jd_tt", "ra_app_deg", "dec_app_deg", "distance_km"])
        for body, jd in samples:
            t = ts.tt_jd(jd)
            app = earth.at(t).observe(eph[NAMES[body]]).apparent()
            ra, dec, dist = app.radec(epoch="date")
            w.writerow([body, f"{jd:.6f}", f"{ra._degrees:.10f}", f"{dec.degrees:.10f}", f"{dist.km:.4f}"])

    # 站心
    rng = random.Random(20261106)
    with open(os.path.join(out_dir, "topocentric.csv"), "w", newline="\n", encoding="utf-8") as f:
        f.write(header_note + "\n")
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["site", "lat_deg", "lon_deg", "height_m", "body", "jd_tt", "delta_t_s",
                    "ra_app_deg", "dec_app_deg", "az_deg", "alt_deg", "distance_km"])
        for site, lat, lon, h in SITES:
            observer = earth + wgs84.latlon(lat, lon, elevation_m=h)
            for body in NAMES:
                for _ in range(TOPO_PER_PAIR):
                    jd = round(rng.uniform(JD_2000, JD_2100), 6)
                    t = ts.tt_jd(jd)
                    app = observer.at(t).observe(eph[NAMES[body]]).apparent()
                    ra, dec, dist = app.radec(epoch="date")
                    alt, az, _ = app.altaz()
                    w.writerow([site, lat, lon, h, body, f"{jd:.6f}", f"{float(t.delta_t):.6f}",
                                f"{ra._degrees:.10f}", f"{dec.degrees:.10f}",
                                f"{az.degrees:.10f}", f"{alt.degrees:.10f}", f"{dist.km:.4f}"])
    print("done", file=sys.stderr)


if __name__ == "__main__":
    main()
