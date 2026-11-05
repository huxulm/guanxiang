"""生成 App 内的 Rust 依赖许可声明（M7）。

Flutter 会自动收集 Dart 包和引擎的许可证，但不知道 Rust 依赖。本脚本用 `cargo metadata`
找出桥接库 `rust_lib_guanxiang` 在 Android、Windows、Linux 上的运行时依赖（不含构建、开发依赖），
读取各 crate 源码目录里的许可证文件，相同文本合并，写成 `app/assets/licenses/rust.txt`。

用法（仓库根目录）：py -3 tools/licenses/gen_rust_notices.py

输出格式：每条以一行 `@@ crate1 版本, crate2 版本, …` 开头，后面是许可证全文；
Dart 端（`lib/src/licenses.dart`）按这个格式注册到 LicenseRegistry。
"""

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app" / "assets" / "licenses" / "rust.txt"
TARGETS = [
    "aarch64-linux-android",
    "x86_64-linux-android",
    "x86_64-pc-windows-msvc",
    "x86_64-unknown-linux-gnu",
]
LICENSE_FILE = re.compile(r"^(LICEN[CS]E|COPYING|NOTICE|UNLICENSE)([-_.].*)?$", re.I)

# 只写了 SPDX 表达式、没有附带许可证文件、依赖集中也没有同一表达式的文本时使用
FALLBACK = {
    "MIT": (
        "MIT License\n\n"
        "Permission is hereby granted, free of charge, to any person obtaining a copy of this "
        "software and associated documentation files (the \"Software\"), to deal in the Software "
        "without restriction, including without limitation the rights to use, copy, modify, merge, "
        "publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons "
        "to whom the Software is furnished to do so, subject to the following conditions:\n\n"
        "The above copyright notice and this permission notice shall be included in all copies or "
        "substantial portions of the Software.\n\n"
        "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, "
        "INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR "
        "PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE "
        "FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR "
        "OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER "
        "DEALINGS IN THE SOFTWARE.\n"
    ),
}

# MPL-2.0 要求告知源码获取方式；本项目未修改这些 crate
MPL_NOTE = "本应用未修改以下 MPL-2.0 组件，源码可从 crates.io 或其仓库获得：\n"


def metadata(target):
    out = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--locked", "--filter-platform", target],
        cwd=ROOT,
        capture_output=True,
        check=True,
    ).stdout
    return json.loads(out)


def runtime_deps(meta):
    nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
    pkgs = {p["id"]: p for p in meta["packages"]}
    root = next(p["id"] for p in meta["packages"] if p["name"] == "rust_lib_guanxiang")
    seen, stack = set(), [root]
    while stack:
        i = stack.pop()
        if i in seen:
            continue
        seen.add(i)
        for d in nodes[i]["deps"]:
            if any(k["kind"] is None for k in d["dep_kinds"]):
                stack.append(d["pkg"])
    return [pkgs[i] for i in seen if pkgs[i]["source"]]  # 去掉本仓库的 crate


def file_texts(pkg):
    d = Path(pkg["manifest_path"]).parent
    if pkg.get("license_file"):
        files = [d / pkg["license_file"]]
    else:
        files = sorted(f for f in d.iterdir() if f.is_file() and LICENSE_FILE.match(f.name))
    return [f.read_text(encoding="utf-8", errors="replace").strip() + "\n" for f in files]


def license_texts(pkg, by_spdx):
    texts = file_texts(pkg)
    if texts:
        return texts
    lic = pkg.get("license") or ""
    # 先用依赖集中许可证表达式完全相同的另一个 crate 附带的文本（如 anise 用 hifitime 的 MPL-2.0）
    if lic in by_spdx:
        return [by_spdx[lic]]
    key = next((k for k in FALLBACK if k in lic), None)
    if key is None:
        sys.exit(f"{pkg['name']} {pkg['version']} 没有许可证文件，许可证 {lic!r} 也找不到文本")
    return [FALLBACK[key]]


def main():
    pkgs = {}
    for t in TARGETS:
        for p in runtime_deps(metadata(t)):
            pkgs[(p["name"], p["version"])] = p

    by_spdx = {}
    for p in pkgs.values():
        texts = file_texts(p)
        if len(texts) == 1 and p.get("license"):
            by_spdx.setdefault(p["license"], texts[0])

    groups = {}  # 文本哈希 → (文本, [crate])
    mpl = []
    for (name, version), p in sorted(pkgs.items()):
        if "MPL" in (p.get("license") or ""):
            repo = p.get("repository") or f"https://crates.io/crates/{name}"
            mpl.append(f"  {name} {version}：{repo}")
        for text in license_texts(p, by_spdx):
            h = hashlib.sha256(text.encode()).hexdigest()
            groups.setdefault(h, (text, []))[1].append(f"{name} {version}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", encoding="utf-8", newline="\n") as f:
        if mpl:
            f.write("@@ MPL-2.0 源码\n" + MPL_NOTE + "\n".join(mpl) + "\n\n")
        for text, crates in sorted(groups.values(), key=lambda g: g[1][0]):
            f.write("@@ " + ", ".join(crates) + "\n")
            f.write(text.replace("\r\n", "\n"))
            f.write("\n")
    size = OUT.stat().st_size / 1024
    print(f"{len(pkgs)} 个 crate，{len(groups)} 份不同的许可证文本 → {OUT.relative_to(ROOT)}（{size:.0f} KB）")


if __name__ == "__main__":
    main()
