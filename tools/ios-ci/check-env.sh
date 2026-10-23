#!/usr/bin/env bash
# 打印 macOS / Xcode / 模拟器 / CocoaPods 环境，并写 ci-out/env.txt（供 summary / run.json 使用）。
# Xcode 版本依据：Flutter 3.47.7 的 flutter_tools/lib/src/macos/xcode.dart
#   xcodeRequiredVersion = 15，xcodeRecommendedVersion = 16 —— 低于 15 直接报错。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

step "env-info"

log "仓库: ${GITHUB_REPOSITORY:-?}"
log "ref: ${GITHUB_REF:-?} / ${GITHUB_REF_NAME:-?}"
log "commit: ${GITHUB_SHA:-?}"
log "run: ${GITHUB_RUN_ID:-?} attempt ${GITHUB_RUN_ATTEMPT:-1} event=${GITHUB_EVENT_NAME:-?}"
log "runner: ${RUNNER_NAME:-?} os=${RUNNER_OS:-?} arch=${RUNNER_ARCH:-?}"
log "workspace: $PWD"
log ""
log "---- sw_vers ----"
sw_vers 2>&1 | tee -a "$BUILD_LOG" || true

# 可选：workflow_dispatch 输入 xcode_app 指定 Xcode.app（例如 /Applications/Xcode_16.4.app）
if [ -n "${XCODE_APP:-}" ] && [ -d "${XCODE_APP}" ]; then
  log "按输入切换 Xcode -> $XCODE_APP"
  sudo xcode-select -s "$XCODE_APP" 2>&1 | tee -a "$BUILD_LOG" || true
fi

log ""
log "---- xcode-select -p ----"
xcode-select -p 2>&1 | tee -a "$BUILD_LOG" || true
log "---- xcodebuild -version ----"
XCODE_VERSION_LINE="$(xcodebuild -version 2>&1 | head -2 | tr '\n' ' ')"
log "$XCODE_VERSION_LINE"
log "---- /Applications 下的 Xcode ----"
ls -d /Applications/Xcode*.app 2>/dev/null | tee -a "$BUILD_LOG" || true

XCODE_MAJOR="$(printf '%s' "$XCODE_VERSION_LINE" | sed -n 's/^Xcode \([0-9][0-9]*\).*/\1/p' | head -1)"
log "Xcode 主版本: ${XCODE_MAJOR:-未知}（Flutter 要求 >= 15，推荐 16）"

if [ -n "${XCODE_MAJOR:-}" ] && [ "$XCODE_MAJOR" -lt 15 ] 2>/dev/null; then
  log "⚠️ 默认 Xcode 低于 15，尝试从 /Applications 里挑一个 >= 15 的"
  for app in $(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -rV); do
    ver="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
    major="${ver%%.*}"
    if [ -n "$major" ] && [ "$major" -ge 15 ] 2>/dev/null; then
      log "切换 Xcode -> $app ($ver)"
      sudo xcode-select -s "$app" 2>&1 | tee -a "$BUILD_LOG" || true
      XCODE_VERSION_LINE="$(xcodebuild -version 2>&1 | head -2 | tr '\n' ' ')"
      log "$XCODE_VERSION_LINE"
      break
    fi
  done
fi

log ""
log "---- iOS 模拟器 runtime ----"
xcrun simctl list runtimes 2>&1 | tee -a "$BUILD_LOG" || true
log "---- 可用模拟器设备 ----"
xcrun simctl list devices available 2>&1 | tee -a "$BUILD_LOG" || true
xcrun simctl list devices available --json > "$CI_OUT/sim-devices.json" 2>/dev/null || true
xcrun simctl list devices available > "$CI_OUT/sim-devices.txt" 2>&1 || true

log ""
log "---- CocoaPods / Ruby ----"
(pod --version 2>&1 || echo 'CocoaPods 未安装') | tee -a "$BUILD_LOG"
ruby --version 2>&1 | tee -a "$BUILD_LOG" || true
log ""
log "---- 磁盘 ----"
df -h / 2>&1 | tee -a "$BUILD_LOG" || true

{
  echo "runner=${RUNNER_NAME:-?} os=${RUNNER_OS:-?} arch=${RUNNER_ARCH:-?}"
  echo "macos=$(sw_vers -productVersion 2>/dev/null || echo '?')"
  echo "xcode=$XCODE_VERSION_LINE"
  echo "xcode_select=$(xcode-select -p 2>/dev/null || echo '?')"
  echo "flutter_requested=${FLUTTER_VERSION:-?}"
  echo "event=${GITHUB_EVENT_NAME:-?}"
  echo "cocoapods=$(pod --version 2>/dev/null || echo '未安装')"
} > "$CI_OUT/env.txt"
log "环境信息已写 ci-out/env.txt"
