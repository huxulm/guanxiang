#!/usr/bin/env python3
"""从 NASA 月食沙罗序列目录生成 Rust 常量表（序列号、首次月食的朔望月序号、月食次数）。

来源：
  https://eclipse.gsfc.nasa.gov/LEsaros/LEsaroscat.html

用法：
  python tools/nasa/gen_saros_table.py LEsaroscat.html

输出 crates/guanxiang-core/src/events/saros/table.rs，只收 1899–2101 年间有月食的序列。
朔望月序号与 NASA 星表的 Luna Num 相同：2000-01-06 的朔为 0，望月在第 N 个朔望月里。
同一序列相邻两次月食相隔 223 个朔望月。生成后用 lunar_2001_2100.csv（parse_catalog.py 的输出）
核对每次月食的序列号，不一致就报错。
只用标准库。
"""

import csv
import html
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "crates", "guanxiang-core", "src", "events", "saros", "table.rs")
FIXTURE = os.path.join(ROOT, "crates", "guanxiang-core", "tests", "fixtures", "nasa", "lunar_2001_2100.csv")
MONTHS = {m: i + 1 for i, m in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split())}

ROW = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+[\d.]+\s+(-?\d+) (\w{3}) (\d{2})\s+(-?\d+) (\w{3}) (\d{2})\s"
)

# Meeus 49.1：朔望月平均长度和 k = 0 的平朔（2000-01-06）
JDE0 = 2451550.09766
SYNODIC = 29.530588861


def jd(y: int, m: int, d: int) -> float:
    """日历日期 0 时的儒略日；1582-10-15 之前按儒略历（NASA 星表的约定）。"""
    if m <= 2:
        y, m = y - 1, m + 12
    gregorian = (y, m, d) >= (1582, 10, 15)
    b = 0
    if gregorian:
        a = y // 100
        b = 2 - a + a // 4
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d + b - 1524.5


def luna(y: int, m: int, d: int) -> int:
    """这一天的望月所在的朔望月序号。平朔公式离 2000 年越远误差越大（几个世纪内远小于半个月），
    所以只用于 1000–3000 年的日期。"""
    assert 1000 <= y <= 3000, y
    return round((jd(y, m, d) + 0.5 - JDE0) / SYNODIC - 0.5)


def main() -> None:
    sys.stderr.reconfigure(encoding="utf-8")
    text = open(sys.argv[1], encoding="latin-1").read()
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    series = []
    for raw in text.splitlines():
        r = ROW.match(raw)
        if not r:
            continue
        s, count = int(r[1]), int(r[2])
        y0, y1 = int(r[3]), int(r[6])
        if not (y0 <= 2101 and y1 >= 1899):
            continue
        # 用离 2000 年较近的一端推算，另一端只在公式适用时核对
        if abs(y0 - 2000) <= abs(y1 - 2000):
            first = luna(y0, MONTHS[r[4]], int(r[5]))
        else:
            first = luna(y1, MONTHS[r[7]], int(r[8])) - 223 * (count - 1)
        if 1000 <= y0 and y1 <= 3000:
            last = luna(y1, MONTHS[r[7]], int(r[8]))
            assert last - first == 223 * (count - 1), (s, first, last, count)
        series.append((s, first, count))
    assert series, "没有解析到任何序列"

    # 核对 21 世纪的每次月食
    by_luna = {}
    for s, first, count in series:
        for i in range(count):
            by_luna.setdefault(first + 223 * i, []).append(s)
    with open(FIXTURE, encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(line for line in f if not line.startswith("#"))]
    for r in rows:
        got = by_luna.get(int(r["luna"]), [])
        assert got == [int(r["saros"])], (r["date"], r["luna"], r["saros"], got)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("//! 由 `tools/nasa/gen_saros_table.py` 从 NASA 月食沙罗目录生成，不要手改。\n\n")
        f.write("/// 1899–2101 年间有月食的沙罗序列：(序列号, 首次月食的朔望月序号, 月食次数)。\n")
        f.write("/// 朔望月序号与 NASA 的 Luna Num 相同（2000-01-06 的朔为 0）。\n")
        f.write("pub(super) const LUNAR: &[(u16, i32, u16)] = &[\n")
        for s, first, count in series:
            f.write(f"    ({s}, {first}, {count}),\n")
        f.write("];\n")
    print(f"{len(series)} 个序列，核对 {len(rows)} 次月食", file=sys.stderr)


if __name__ == "__main__":
    main()
