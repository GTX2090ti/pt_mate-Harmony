#!/usr/bin/env bash
# 鸿蒙 HAP 本地产物归档
#
# 作用：把 hap/ 根目录下的历史版本产物移到 hap/archive/，只让当前最新版本
# 留在顶层，方便一眼看到「现在装哪个」。
#
# 用法：
#   ./scripts/archive_hap.sh            # 归档所有非最新版本
#   ./scripts/archive_hap.sh --keep 3   # 顶层额外保留最近 3 个版本
#
# 说明：
# - 只处理 hap/ 顶层；archive/ 内部不再递归处理
# - 不删除任何文件，只做移动
# - 已归档的同名文件会被跳过（不会覆盖）
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HAP_DIR="$REPO_ROOT/hap"
ARCHIVE_DIR="$HAP_DIR/archive"

KEEP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)
      KEEP="${2:-1}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "未知参数: $1（用 --help 查看用法）" >&2
      exit 1
      ;;
  esac
done

if [ ! -d "$HAP_DIR" ]; then
  echo "跳过：$HAP_DIR 不存在"
  exit 0
fi

mkdir -p "$ARCHIVE_DIR"

# 取出顶层所有 PTMate-<build>-*.hap，按构建号倒序（数字比较，避免 99 排在 9 前面）
mapfile -t ALL < <(
  find "$HAP_DIR" -maxdepth 1 -type f -name 'PTMate-*.hap' -printf '%f\n' |
    sed -E 's/^PTMate-([0-9]+)-.*\.hap$/\1 &/' |
    sort -t' ' -k1,1nr |
    cut -d' ' -f2-
)

if [ "${#ALL[@]}" -eq 0 ]; then
  echo "hap/ 下没有可归档的 HAP"
  exit 0
fi

# 顶层保留最近 KEEP 个版本，其余移入 archive/
MOVED=0
SKIPPED=0
INDEX=0
for name in "${ALL[@]}"; do
  INDEX=$((INDEX + 1))
  src="$HAP_DIR/$name"
  # 同名的 .sha256 一起处理
  extra=""
  if [ -f "$HAP_DIR/${name}.sha256" ]; then
    extra="$HAP_DIR/${name}.sha256"
  fi

  if [ "$INDEX" -le "$KEEP" ]; then
    continue
  fi

  dst="$ARCHIVE_DIR/$name"
  if [ -e "$dst" ]; then
    echo "跳过（已存在）: $name"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  mv "$src" "$dst"
  [ -n "$extra" ] && mv "$extra" "$ARCHIVE_DIR/${name}.sha256"
  MOVED=$((MOVED + 1))
  echo "归档: $name"
done

LATEST="${ALL[0]}"
echo "---"
echo "顶层保留 ${KEEP} 个版本，最新为: $LATEST"
echo "已归档 ${MOVED} 个，跳过 ${SKIPPED} 个（同名已存在）"
if [ -d "$ARCHIVE_DIR" ]; then
  echo "归档目录: $ARCHIVE_DIR（$(find "$ARCHIVE_DIR" -maxdepth 1 -type f -name '*.hap' | wc -l | tr -d ' ') 个包）"
fi
