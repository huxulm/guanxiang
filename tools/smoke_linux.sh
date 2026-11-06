#!/usr/bin/env bash
# Linux .deb 冒烟测试（在 CI 里运行，会用 sudo 安装和卸载）：
# 1. 用 apt 安装 guanxiang-<版本>-linux-amd64.deb（顺带检查 Depends 在本系统上能满足）；
# 2. 检查 .desktop 文件、图标和动态库；
# 3. 在 Xvfb 里从 PATH 启动 guanxiang 30 秒，要求运行到超时（退出码 124）、日志里没有缺库、缺符号
#    或未处理的异常，并且应用建立了自己的数据目录（说明 Dart 代码真的跑起来了）；
# 4. 卸载，确认文件都删干净。
# 用法：tools/smoke_linux.sh <deb 路径>。需要 xvfb-run、desktop-file-validate。
set -uo pipefail

deb=$(realpath "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "失败：$*"; exit 1; }

echo "== 包信息"
dpkg-deb --info "$deb" || fail "不是有效的 deb"
dpkg-deb --contents "$deb" | awk '{print $6}' | grep -E '^\./(usr|opt/guanxiang/[^/]*$)' | head -40

echo "== 安装"
sudo apt-get install -y -q "$deb" || fail "apt 安装失败（依赖不满足？）"
[ "$(readlink -f "$(command -v guanxiang)")" = /opt/guanxiang/guanxiang ] || fail "PATH 里的 guanxiang 不指向 /opt/guanxiang/guanxiang"

echo "== 桌面文件与图标"
desktop=/usr/share/applications/dev.huxulm.guanxiang.desktop
desktop-file-validate "$desktop" || fail ".desktop 文件不合规范"
for f in /usr/share/icons/hicolor/256x256/apps/dev.huxulm.guanxiang.png /usr/share/icons/hicolor/scalable/apps/dev.huxulm.guanxiang.svg; do
  [ -s "$f" ] || fail "缺图标 $f"
done

echo "== 动态库"
# 插件的 .so 没有自己的 RUNPATH，运行时靠主程序的 $ORIGIN/lib 找到 libflutter_linux_gtk.so，这里照样加上 lib/
if LD_LIBRARY_PATH=/opt/guanxiang/lib ldd /opt/guanxiang/guanxiang /opt/guanxiang/lib/*.so | grep "not found"; then
  fail "有找不到的动态库"
fi

echo "== 启动 30 秒"
data="$HOME/.local/share/dev.huxulm.guanxiang"
rm -rf "$data"
(cd "$work" && xvfb-run -a timeout 30 guanxiang > "$work/run.log" 2>&1)
code=$?
cat "$work/run.log"
[ "$code" -eq 124 ] || fail "程序提前退出，退出码 $code"
if grep -Ei "undefined symbol|symbol lookup error|cannot open shared object|Unhandled Exception|Failed to load" "$work/run.log"; then
  fail "日志里有错误"
fi
[ -d "$data" ] || fail "没有建立数据目录 $data"

echo "== 卸载"
sudo apt-get remove -y -q guanxiang || fail "卸载失败"
[ ! -e /opt/guanxiang ] && [ ! -e /usr/bin/guanxiang ] && [ ! -e "$desktop" ] || fail "卸载后还有残留文件"

echo "冒烟测试通过（$(lsb_release -ds 2>/dev/null || uname -a)）"
