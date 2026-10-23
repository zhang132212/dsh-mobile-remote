#!/usr/bin/env bash
# tools/ios-ci 公共日志工具（被各脚本 source）。
# 目标环境是 GitHub macOS runner 的 /bin/bash 3.2：不要用数组、mapfile、
# ${var^^} 等 bash 4 语法；所有脚本保持 POSIX 风格。
set -uo pipefail

: "${CI_OUT:?CI_OUT 未设置（应指向 <workspace>/ci-out）}"
BUILD_LOG="${BUILD_LOG:-$CI_OUT/build.log}"
export BUILD_LOG
mkdir -p "$CI_OUT"

# 统一从仓库根目录执行（workflow 默认 cwd 已经是 workspace，这里兜底）
if [ -n "${GITHUB_WORKSPACE:-}" ]; then
  cd "$GITHUB_WORKSPACE"
fi

# log <文本...>：打印并追加到 build.log
log() {
  printf '%s\n' "$*" | tee -a "$BUILD_LOG"
}

# step <步骤名>：写步骤分隔标记（方便从 build.log 里切段排查）
step() {
  printf '\n===== STEP %s  %s =====\n' "$1" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" | tee -a "$BUILD_LOG"
}
