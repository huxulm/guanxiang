#!/usr/bin/env python3
"""把 Windows 构建目录打成免安装 zip（解压后是一个 Guanxiang 文件夹）。

用法（在仓库根目录）：
  python tools/package_windows.py app/build/windows/x64/runner/Release guanxiang-<版本>-windows-x64.zip

release.yml 的 windows 任务用它；本机打包也可以用。只用标准库。
"""

import os
import sys
import zipfile


def main() -> None:
    release_dir, zip_path = sys.argv[1], sys.argv[2]
    if not os.path.isfile(os.path.join(release_dir, "guanxiang.exe")):
        sys.exit(f"{release_dir} 里没有 guanxiang.exe，先运行 flutter build windows --release")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, _, names in os.walk(release_dir):
            for n in sorted(names):
                full = os.path.join(root, n)
                z.write(full, os.path.join("Guanxiang", os.path.relpath(full, release_dir)))
    print(zip_path)


if __name__ == "__main__":
    main()
