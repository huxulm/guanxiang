#!/usr/bin/env bash
# 把 `flutter build linux --release` 的产物打成 guanxiang-<版本>-linux-amd64.deb。
# 用法（在仓库根目录）：tools/package_linux.sh [输出目录]，默认 app/build/linux/dist；最后一行输出包路径。
# 需要 dpkg-deb（Debian/Ubuntu 自带）。
#
# 安装位置：
#   /opt/guanxiang/                         Flutter bundle（程序、lib/、data/）
#   /usr/bin/guanxiang                      指向 /opt/guanxiang/guanxiang 的符号链接
#   /usr/share/applications/dev.huxulm.guanxiang.desktop
#   /usr/share/icons/hicolor/*/apps/dev.huxulm.guanxiang.{png,svg}
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/app"
version=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$app/pubspec.yaml")
[ -n "$version" ] || { echo "读不到 pubspec.yaml 的版本号" >&2; exit 1; }
bundle="$app/build/linux/x64/release/bundle"
[ -x "$bundle/guanxiang" ] || { echo "找不到 $bundle/guanxiang，先运行 flutter build linux --release" >&2; exit 1; }
packaging="$app/linux/packaging"

out=$(mkdir -p "${1:-$app/build/linux/dist}" && cd "${1:-$app/build/linux/dist}" && pwd)
name="guanxiang-$version-linux-amd64"
stage="$app/build/linux/deb/$name"
rm -rf "$stage"
mkdir -p "$stage/DEBIAN" "$stage/opt/guanxiang" "$stage/usr/bin" \
  "$stage/usr/share/applications" "$stage/usr/share/icons" "$stage/usr/share/doc/guanxiang"

cp -a "$bundle/." "$stage/opt/guanxiang/"
ln -s /opt/guanxiang/guanxiang "$stage/usr/bin/guanxiang"
install -m 644 "$packaging/dev.huxulm.guanxiang.desktop" "$stage/usr/share/applications/"
cp -a "$packaging/icons/hicolor" "$stage/usr/share/icons/"
cat > "$stage/usr/share/doc/guanxiang/copyright" <<'EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: guanxiang
Source: https://guanx.huxulm.dev

Files: *
Copyright: Huxulm
Comment: 第三方组件（Flutter、Dart 包、Rust crate）及数据来源的许可证见应用内“关于 → 许可证”。
EOF

# 目录 755、文件 644、可执行文件和 .so 755
find "$stage" -type d -exec chmod 755 {} +
find "$stage" -type f -exec chmod 644 {} +
chmod 755 "$stage/opt/guanxiang/guanxiang"
find "$stage/opt/guanxiang/lib" -name '*.so' -exec chmod 755 {} +

size=$(du -sk --exclude=DEBIAN "$stage" | cut -f1)
cat > "$stage/DEBIAN/control" <<EOF
Package: guanxiang
Version: $version
Architecture: amd64
Maintainer: Huxulm
Installed-Size: $size
Depends: libc6 (>= 2.35), libstdc++6, libgtk-3-0t64 | libgtk-3-0, libegl1
Recommends: libgl1-mesa-dri, geoclue-2.0
Section: science
Priority: optional
Homepage: https://guanx.huxulm.dev
Description: 观象：天文事件搜索 / astronomical event search
 离线计算日月食、行星凌日、合冲、月掩星，以及国际空间站、天宫等卫星的
 凌日凌月预报。观测太阳必须使用合格的太阳滤光膜（ISO 12312-2）。
 .
 Offline search for eclipses, planetary transits, conjunctions, lunar
 occultations and satellite transits of the Sun and Moon. Always use a
 certified solar filter (ISO 12312-2) when observing the Sun.
EOF

dpkg-deb --root-owner-group -Zxz --build "$stage" "$out/$name.deb" > /dev/null
echo "$out/$name.deb"
