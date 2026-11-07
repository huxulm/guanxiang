#!/usr/bin/env python3
"""从 NASA 日月食沙罗序列目录生成 Rust 常量表（序列号、首次日月食的朔望月序号、次数）。

来源：
  https://eclipse.gsfc.nasa.gov/LEsaros/LEsaroscat.html
  https://eclipse.gsfc.nasa.gov/SEsaros/SEsaroscat.html

用法：
  python tools/nasa/gen_saros_table.py LEsaroscat.html SEsaroscat.html

输出 crates/guanxiang-core/src/events/saros/table.rs（LUNAR、SOLAR 两张表），只收 1899–2101 年间有食的序列。
朔望月序号与 NASA 星表的 Luna Num 相同：2000-01-06 的朔为 0；月食（望）在第 N 个朔望月里，日食就在第 N 个朔。
同一序列相邻两次相隔 223 个朔望月。生成后用 parse_catalog.py 输出的 21 世纪星表核对每次日月食的序列号，
不一致就报错。
只用标准库。
"""

import csv
import html
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "crates", "guanxiang-core", "src", "events", "saros", "table.rs")
FIXTURES = os.path.join(ROOT, "crates", "guanxiang-core", "tests", "fixtures", "nasa")
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


def luna(y: int, m: int, d: int, phase: float) -> int:
    """这一天的朔（phase = 0）或望（phase = 0.5）所在的朔望月序号。平朔公式离 2000 年越远误差越大
    （几个世纪内远小于半个月），所以只用于 1000–3000 年的日期。"""
    assert 1000 <= y <= 3000, y
    return round((jd(y, m, d) + 0.5 - JDE0) / SYNODIC - phase)


def table(catalog: str, fixture: str, phase: float):
    text = open(catalog, encoding="latin-1").read()
    text = html.unescape(re.sub(r"<[^>]+>", "", text))
    series = []
    for raw in text.splitlines():
        r = ROW.match(raw)
        if not r:
            continue
        s, count = int(r[1]), int(r[2])
        y0, y1 = int(r[3]), int(r[6])
        # 日食目录每张分表的第一行重复上一张的最后一个序列（25、50、75…）
        if not (y0 <= 2101 and y1 >= 1899) or any(x[0] == s for x in series):
            continue
        # 用离 2000 年较近的一端推算，另一端只在公式适用时核对
        if abs(y0 - 2000) <= abs(y1 - 2000):
            first = luna(y0, MONTHS[r[4]], int(r[5]), phase)
        else:
            first = luna(y1, MONTHS[r[7]], int(r[8]), phase) - 223 * (count - 1)
        if 1000 <= y0 and y1 <= 3000:
            last = luna(y1, MONTHS[r[7]], int(r[8]), phase)
            assert last - first == 223 * (count - 1), (s, first, last, count)
        series.append((s, first, count))
    assert series, f"{catalog} 没有解析到任何序列"

    # 核对 21 世纪的每次日月食
    by_luna = {}
    for s, first, count in series:
        for i in range(count):
            by_luna.setdefault(first + 223 * i, []).append(s)
    with open(os.path.join(FIXTURES, fixture), encoding="utf-8") as f:
        rows = [r for r in csv.DictReader(line for line in f if not line.startswith("#"))]
    for r in rows:
        got = by_luna.get(int(r["luna"]), [])
        assert got == [int(r["saros"])], (fixture, r["date"], r["luna"], r["saros"], got)
    print(f"{fixture}：{len(series)} 个序列，核对 {len(rows)} 次", file=sys.stderr)
    return series


def main() -> None:
    sys.stderr.reconfigure(encoding="utf-8")
    lunar = table(sys.argv[1], "lunar_2001_2100.csv", 0.5)
    solar = table(sys.argv[2], "solar_2001_2100.csv", 0.0)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="\n", encoding="utf-8") as f:
        f.write("//! 由 `tools/nasa/gen_saros_table.py` 从 NASA 日月食沙罗目录生成，不要手改。\n")
        for name, what, rows in [("LUNAR", "月食", lunar), ("SOLAR", "日食", solar)]:
            f.write(f"\n/// 1899–2101 年间有{what}的沙罗序列：(序列号, 首次{what}的朔望月序号, {what}次数)。\n")
            f.write("/// 朔望月序号与 NASA 的 Luna Num 相同（2000-01-06 的朔为 0）。\n")
            f.write(f"pub(super) const {name}: &[(u16, i32, u16)] = &[\n")
            for s, first, count in rows:
                f.write(f"    ({s}, {first}, {count}),\n")
            f.write("];\n")


if __name__ == "__main__":
    main()
