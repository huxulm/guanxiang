#!/usr/bin/env bash
# Linux 包冒烟测试：解压 guanxiang-<版本>-linux-x64.tar.gz，检查动态库都能找到，
# 在 Xvfb 里启动 30 秒，要求一直运行到超时（退出码 124），日志里没有缺符号或未处理的异常，
# 并且应用建立了自己的数据目录（说明 Dart 代码真的跑起来了）。
# 用法：tools/smoke_linux.sh <包路径>。需要 xvfb-run 和 GTK 3 运行库。
set -uo pipefail

pkg=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$pkg" -C "$work"
dir=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -1)
cd "$dir" || exit 1

echo "== 动态库"
# 插件的 .so 没有自己的 RUNPATH，运行时靠主程序的 $ORIGIN/lib 找到 libflutter_linux_gtk.so，这里照样加上 lib/
if LD_LIBRARY_PATH="$PWD/lib" ldd ./guanxiang lib/*.so | grep "not found"; then
  echo "有找不到的动态库"; exit 1
fi

echo "== 启动 30 秒"
data="$HOME/.local/share/dev.huxulm.guanxiang"
rm -rf "$data"
xvfb-run -a timeout 30 ./guanxiang > "$work/run.log" 2>&1
code=$?
cat "$work/run.log"
if [ "$code" -ne 124 ]; then
  echo "程序提前退出，退出码 $code"; exit 1
fi
if grep -Ei "undefined symbol|symbol lookup error|Unhandled Exception|Failed to load" "$work/run.log"; then
  echo "日志里有错误"; exit 1
fi
if [ ! -d "$data" ]; then
  echo "没有建立数据目录 $data"; exit 1
fi
echo "冒烟测试通过（$(lsb_release -ds 2>/dev/null || uname -a)）"
