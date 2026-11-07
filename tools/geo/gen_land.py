#!/usr/bin/env python3
"""把 Natural Earth 1:110m 陆地轮廓转成 App 用的紧凑 JSON（日月食地图的底图）。

来源（公有领域）：
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson

用法：
  python tools/geo/gen_land.py ne_110m_land.geojson

输出 app/assets/geo/land_110m.json：{"source": ..., "scale": 10, "rings": [[lon, lat, lon, lat, ...], ...]}，
坐标乘 10 取整（0.1°），只保留外环（1:110m 没有需要挖空的湖），相邻重复点去掉。
只用标准库。
"""

import json
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "app", "assets", "geo", "land_110m.json")
SCALE = 10


def main() -> None:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    rings = []
    for feature in data["features"]:
        g = feature["geometry"]
        polys = [g["coordinates"]] if g["type"] == "Polygon" else g["coordinates"]
        for poly in polys:
            flat = []
            last = None
            for lon, lat in poly[0]:
                p = (round(lon * SCALE), round(lat * SCALE))
                if p != last:
                    flat.extend(p)
                    last = p
            if len(flat) >= 8:
                rings.append(flat)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    out = {"source": "Natural Earth 1:110m land (public domain)", "scale": SCALE, "rings": rings}
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")
    n = sum(len(r) // 2 for r in rings)
    print(f"{len(rings)} 个多边形，{n} 个点，{os.path.getsize(OUT)} 字节", file=sys.stderr)


if __name__ == "__main__":
    sys.stderr.reconfigure(encoding="utf-8")
    main()
