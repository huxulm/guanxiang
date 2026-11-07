#!/usr/bin/env bash
# 把文件上传到 GitHub Release（已存在则覆盖）。GitHub API 偶尔返回 500，失败时重试。
# 用法：GH_TOKEN=... bash tools/release_upload.sh <标签> <文件>...
# release.yml 的 android、windows、linux 任务用它。
set -euo pipefail

tag=$1
shift
for f in "$@"; do
  for i in 1 2 3 4; do
    gh release upload "$tag" "$f" --clobber -R "$GITHUB_REPOSITORY" && break
    [ "$i" -lt 4 ] || exit 1
    echo "上传 $f 失败，15 秒后重试（第 $i 次）"
    sleep 15
  done
done
