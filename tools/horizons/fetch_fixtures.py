#!/usr/bin/env python3
"""从 JPL Horizons 抓取对照数据，写入 crates/guanxiang-core/tests/fixtures/horizons/。

用法：python tools/horizons/fetch_fixtures.py

只用标准库。采样时刻由固定种子的伪随机数生成，重复运行得到相同的请求。
生成的文件进 Git，CI 不访问网络。

- geocentric.csv：地心，TT 时刻，2000–2100 年，天体测量 RA/Dec（ICRF）、视 RA/Dec（真赤道真春分点）、距离。
- topocentric.csv：站心，UTC 时刻，1975–2026 年（ΔT 有 IERS 实测值），另含地平坐标（无大气）。

行星取系统质心（与 de440s 一致），避免质心与本体之差（木星可达约 0.06″）混入比较。
"""

import csv
import os
import random
import sys
import time
import urllib.parse
import urllib.request

API = "https://ssd.jpl.nasa.gov/api/horizons.api"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "crates", "guanxiang-core", "tests", "fixtures", "horizons")

# (guanxiang 名称, Horizons COMMAND)
BODIES = [
    ("sun", "10"),
    ("moon", "301"),
    ("mercury", "1"),
    ("venus", "2"),
    ("mars", "4"),
    ("jupiter", "5"),
    ("saturn", "6"),
    ("uranus", "7"),
    ("neptune", "8"),
]
TOPO_BODIES = ["sun", "moon", "venus", "jupiter"]

# (名称, 纬度°, 经度°, 高度 m)
SITES = [
    ("nanshan", 43.4711, 87.1778, 2080.0),
    ("paranal", -24.6272, -70.4044, 2635.0),
    ("tromso", 69.6496, 18.9560, 100.0),
]

GEO_PER_BODY = 15
TOPO_PER_PAIR = 6
JD_2000 = 2451545.0
JD_2100 = 2488069.5


def query(params: dict) -> str:
    base = {
        "format": "text",
        "OBJ_DATA": "'NO'",
        "MAKE_EPHEM": "'YES'",
        "EPHEM_TYPE": "'OBSERVER'",
        "ANG_FORMAT": "'DEG'",
        "EXTRA_PREC": "'YES'",
        "CSV_FORMAT": "'YES'",
        "APPARENT": "'AIRLESS'",
    }
    base.update(params)
    url = API + "?" + urllib.parse.urlencode(base)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=120) as r:
                return r.read().decode("utf-8")
        except Exception as e:  # noqa: BLE001
            if attempt == 3:
                raise
            print(f"  重试（{e}）", file=sys.stderr)
            time.sleep(3)
    raise RuntimeError("unreachable")


def rows(text: str):
    if "$$SOE" not in text:
        raise RuntimeError("Horizons 返回中没有数据：\n" + text[-2000:])
    body = text.split("$$SOE", 1)[1].split("$$EOE", 1)[0]
    for line in body.strip().splitlines():
        yield [c.strip() for c in line.split(",")]


def tlist(values) -> str:
    return " ".join(f"'{v}'" for v in values)


def fetch_geocentric(rng: random.Random):
    out = []
    for name, cmd in BODIES:
        jds = sorted(round(rng.uniform(JD_2000, JD_2100), 6) for _ in range(GEO_PER_BODY))
        print(f"geocentric {name}", file=sys.stderr)
        text = query({
            "COMMAND": f"'{cmd}'",
            "CENTER": "'500@399'",
            "TLIST": tlist(f"{j:.6f}" for j in jds),
            "TLIST_TYPE": "'JD'",
            "TIME_TYPE": "'TT'",
            "CAL_FORMAT": "'JD'",
            "QUANTITIES": "'1,2,20'",
        })
        for r in rows(text):
            # JD, , , RA_icrf, DEC_icrf, RA_app, DEC_app, delta, deldot
            out.append([name, r[0], r[3], r[4], r[5], r[6], r[7]])
    return out


def fetch_topocentric(rng: random.Random):
    out = []
    t0 = 157766400  # 1975-01-01 Unix 秒
    t1 = 1790726400  # 2026-10-01
    for site, lat, lon, h in SITES:
        for name in TOPO_BODIES:
            cmd = dict(BODIES)[name]
            stamps = sorted(rng.randint(t0, t1) for _ in range(TOPO_PER_PAIR))
            cals = [time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(s)) for s in stamps]
            print(f"topocentric {site} {name}", file=sys.stderr)
            text = query({
                "COMMAND": f"'{cmd}'",
                "CENTER": "'coord@399'",
                "COORD_TYPE": "'GEODETIC'",
                "SITE_COORD": f"'{lon},{lat},{h / 1000.0}'",
                "TLIST": tlist(cals),
                "TLIST_TYPE": "'CAL'",
                "TIME_TYPE": "'UT'",
                "TIME_DIGITS": "'SECONDS'",
                "QUANTITIES": "'1,2,4,20'",
            })
            got = list(rows(text))
            assert len(got) == len(cals), (site, name, len(got))
            for cal, r in zip(cals, got):
                # 日期, 太阳/月亮标记, 标记, RA_icrf, DEC_icrf, RA_app, DEC_app, Az, El, delta, deldot
                out.append([site, lat, lon, h, name, cal, r[3], r[4], r[5], r[6], r[7], r[8], r[9]])
    return out


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261105)

    geo = fetch_geocentric(rng)
    with open(os.path.join(OUT, "geocentric.csv"), "w", newline="\n", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["body", "jd_tt", "ra_icrf_deg", "dec_icrf_deg", "ra_app_deg", "dec_app_deg", "delta_au"])
        w.writerows(geo)

    topo = fetch_topocentric(rng)
    with open(os.path.join(OUT, "topocentric.csv"), "w", newline="\n", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["site", "lat_deg", "lon_deg", "height_m", "body", "utc", "ra_icrf_deg", "dec_icrf_deg",
                    "ra_app_deg", "dec_app_deg", "az_deg", "el_deg", "delta_au"])
        w.writerows(topo)

    print(f"geocentric {len(geo)} 行，topocentric {len(topo)} 行", file=sys.stderr)


if __name__ == "__main__":
    main()
