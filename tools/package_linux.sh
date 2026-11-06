#!/usr/bin/env bash
# 把 `flutter build linux --release` 的产物打成 guanxiang-<版本>-linux-x64.tar.gz。
# 用法（在仓库根目录）：tools/package_linux.sh [输出目录]，默认 app/build/linux/dist。
# 包里是一个 guanxiang-<版本>-linux-x64/ 目录：解压后运行其中的 ./guanxiang。
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
app="$root/app"
version=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' "$app/pubspec.yaml")
[ -n "$version" ] || { echo "读不到 pubspec.yaml 的版本号" >&2; exit 1; }
bundle="$app/build/linux/x64/release/bundle"
[ -x "$bundle/guanxiang" ] || { echo "找不到 $bundle/guanxiang，先运行 flutter build linux --release" >&2; exit 1; }

out=$(mkdir -p "${1:-$app/build/linux/dist}" && cd "${1:-$app/build/linux/dist}" && pwd)
name="guanxiang-$version-linux-x64"
stage="$app/build/linux/stage"
rm -rf "$stage" && mkdir -p "$stage/$name"
cp -a "$bundle/." "$stage/$name/"
tar -C "$stage" -czf "$out/$name.tar.gz" "$name"
echo "$out/$name.tar.gz"
