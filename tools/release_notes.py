#!/usr/bin/env python3
"""Release 说明：每个版本一份 docs/releases/v<版本>.md，随版本号一起提交；
GitHub Release 的正文以它为准（release.yml 发布后会从标签对应的提交里读出来写回 Release）。

用法（在仓库根目录）：
  python tools/release_notes.py new 0.1.11     从 TEMPLATE.md 生成 docs/releases/v0.1.11.md，
                                              “已知限制”预先填上一版的内容
  python tools/release_notes.py check 0.1.11   检查文件存在、没有遗留的 {{...}} 占位符、
                                              版本号与 app/pubspec.yaml 一致
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / "docs" / "releases"


def path_of(version: str) -> Path:
    return DIR / f"v{version}.md"


def read(p: Path) -> str:
    # 按字节读写，Windows 上也保持 LF
    return p.read_bytes().decode("utf-8")


def version_key(p: Path):
    return tuple(int(x) for x in p.stem[1:].split("."))


def previous_limits(version: str) -> str | None:
    """上一版（按版本号排序）的“已知限制”一节。"""
    older = sorted(
        (p for p in DIR.glob("v*.md") if version_key(p) < tuple(int(x) for x in version.split("."))),
        key=version_key,
    )
    if not older:
        return None
    m = re.search(r"## 已知限制\n\n(.*?)\n\n\*\*", read(older[-1]), re.S)
    return m.group(1).strip() if m else None


def new(version: str) -> None:
    p = path_of(version)
    if p.exists():
        sys.exit(f"{p.relative_to(ROOT).as_posix()} 已存在")
    text = read(DIR / "TEMPLATE.md").replace("{{VERSION}}", version)
    limits = previous_limits(version)
    if limits:
        text = re.sub(r"\{\{TODO: 从上一版的“已知限制”复制过来[^}]*\}\}", lambda _: limits, text)
    p.write_bytes(text.encode("utf-8"))
    print(f"已生成 {p.relative_to(ROOT).as_posix()}，填写“更新”一节，核对“已知限制”")


def check(version: str) -> None:
    p = path_of(version)
    if not p.exists():
        sys.exit(f"缺少 {p.relative_to(ROOT).as_posix()}：先运行 python tools/release_notes.py new {version}")
    text = read(p)
    left = re.findall(r"\{\{[^}]*\}\}", text)
    if left:
        sys.exit(f"{p.relative_to(ROOT).as_posix()} 还有未填写的占位符：{left}")
    pubspec = read(ROOT / "app" / "pubspec.yaml")
    m = re.search(r"^version: *([0-9.]+)", pubspec, re.M)
    if not m or m.group(1) != version:
        sys.exit(f"app/pubspec.yaml 的版本是 {m.group(1) if m else '?'}，不是 {version}")
    if f"观象 {version}" not in text:
        sys.exit(f"{p.relative_to(ROOT).as_posix()} 的标题里没有版本号 {version}")
    print(f"{p.relative_to(ROOT).as_posix()} 可以发布")


def main() -> None:
    # Windows 控制台默认 GBK，统一输出 UTF-8
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    if len(sys.argv) != 3 or sys.argv[1] not in ("new", "check"):
        sys.exit(__doc__)
    cmd, version = sys.argv[1], sys.argv[2].removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit(f"版本号格式应为 0.1.11，收到 {version}")
    {"new": new, "check": check}[cmd](version)


if __name__ == "__main__":
    main()
