#!/usr/bin/env bash
# 构建鸿蒙 HAP 并自动归档历史版本
#
# 用法：
#   ./scripts/build_hap.sh              # release 构建 + 归档（顶层只留最新版本）
#   ./scripts/build_hap.sh --keep 3    # 顶层额外保留最近 3 个版本
#   ./scripts/build_hap.sh --no-archive # 只构建，不归档
#
# 产物：
#   build/ohos/hap/entry-default-unsigned.hap  →  hap/PTMate-<build>-unsigned.hap
#   并生成同名 .sha256
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ARCHIVE=1
KEEP=1
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP="${2:-1}"; shift ;;
    --no-archive) ARCHIVE=0 ;;
  esac
done

# ---- 工具链环境 ----
DEVECO="${DEVECO_STUDIO_HOME:-D:/DevEco Studio}"
FLUTTER_ROOT="${FLUTTER_HOME:-D:/HarmonyDev/flutter_flutter_341}"

if [ ! -d "$DEVECO/tools/hvigor/bin" ]; then
  echo "找不到 DevEco Studio 工具链：$DEVECO" >&2
  echo "可用 DEVECO_STUDIO_HOME 环境变量指定实际路径。" >&2
  exit 1
fi

# Windows 侧的 node / hvigor 只认反斜杠路径，Git Bash 的 POSIX 路径会让它们找不到 node
DEVECO_WIN=$(cygpath -w "$DEVECO" 2>/dev/null || echo "$DEVECO")
FLUTTER_WIN=$(cygpath -w "$FLUTTER_ROOT" 2>/dev/null || echo "$FLUTTER_ROOT")
export PATH="$DEVECO_WIN\jbr\bin;$DEVECO_WIN\tools\ohpm\bin;$DEVECO_WIN\tools\node;$DEVECO_WIN\tools\hvigor\bin;$FLUTTER_WIN\bin;$PATH"
export DEVECO_SDK_HOME="$DEVECO_WIN\sdk"
# 官方 hvigorw.js 需要 NODE_HOME 才能定位 node
export NODE_HOME="$DEVECO_WIN\tools\node"

# ---- 构建 ----
echo "==> 构建 HAP (release)"
"$FLUTTER_ROOT/bin/flutter.bat" build hap --release

SRC="build/ohos/hap/entry-default-unsigned.hap"
if [ ! -f "$SRC" ]; then
  echo "构建产物缺失：$SRC" >&2
  exit 1
fi

# ---- 取构建号并落到 hap/ ----
BUILD_CODE="$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1 | cut -d+ -f2)"
if [ -z "$BUILD_CODE" ]; then
  echo "无法从 pubspec.yaml 解析构建号" >&2
  exit 1
fi

DEST="hap/PTMate-${BUILD_CODE}-unsigned.hap"
mkdir -p hap
cp "$SRC" "$DEST"

# ---- 生成 sha256 ----
# 格式与仓库既有产物一致：<hash><两个空格><文件名>
# 不依赖 python：Windows 的 python 命令可能是 Microsoft Store 占位符。
HASH="$(sha256sum "$DEST" | cut -d" " -f1)"
printf '%s  %s\n' "$HASH" "$(basename "$DEST")" > "$DEST.sha256"

echo "==> 产物: $DEST"
ls -lh "$DEST" "$DEST.sha256"

# ---- 归档历史版本 ----
if [ "$ARCHIVE" -eq 1 ]; then
  echo "==> 归档历史版本"
  bash scripts/archive_hap.sh --keep "$KEEP"
fi

echo "==> 完成"
