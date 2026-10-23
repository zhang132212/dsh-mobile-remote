#!/usr/bin/env bash
# 收集本次 iOS CI 的产物到 ci-out：产物清单、体积数据、设备版 .app 归档、golden 失败证据、失败行抽取；
# 最后 shutdown 冒烟用过的模拟器。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
MAN="$CI_OUT/artifact-manifest.txt"
DEVICE_APP="$APP_DIR/build/ios/iphoneos/Runner.app"
SIM_APP="$APP_DIR/build/ios/iphonesimulator/Runner.app"

step "collect-artifacts"

{
  echo "# iOS CI 构建产物清单"
  echo ""
  echo "- 生成时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- 仓库: ${GITHUB_REPOSITORY:-?}"
  echo "- ref: ${GITHUB_REF_NAME:-?}  commit: ${GITHUB_SHA:-?}"
  echo "- run: ${GITHUB_RUN_ID:-?} attempt ${GITHUB_RUN_ATTEMPT:-1}"
  echo ""
} > "$MAN"

manifest_line() {
  printf '%s\n' "$*" >> "$MAN"
}

describe_app() {
  app="$1"
  label="$2"
  manifest_line ""
  manifest_line "## $label"
  manifest_line "- path: $app"
  if [ ! -d "$app" ]; then
    manifest_line "- 状态: 不存在（构建失败或未执行）"
    return 0
  fi
  manifest_line "- 大小: $(du -sh "$app" | cut -f1)"
  manifest_line "- 文件数: $(find "$app" -type f | wc -l | tr -d ' ')"
  bid="$(plutil -extract CFBundleIdentifier raw -o - "$app/Info.plist" 2>/dev/null || echo '?')"
  ver="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Info.plist" 2>/dev/null || echo '?')"
  bnum="$(plutil -extract CFBundleVersion raw -o - "$app/Info.plist" 2>/dev/null || echo '?')"
  manifest_line "- bundle id: $bid"
  manifest_line "- version: $ver (build $bnum)"
  if [ -f "$app/Runner" ]; then
    manifest_line "- sha256(Runner): $(shasum -a 256 "$app/Runner" | cut -d' ' -f1)"
    manifest_line "- Runner 架构: $(file "$app/Runner" | sed 's/^[^:]*: //')"
  fi
  manifest_line "- Frameworks:"
  ls "$app/Frameworks" 2>/dev/null | sed 's/^/    - /' >> "$MAN" || true
  if [ ! -d "$app/Frameworks" ]; then
    manifest_line "  - （无）"
  fi
  manifest_line "- 顶层内容:"
  find "$app" -maxdepth 1 -mindepth 1 | sort | sed 's/^/    - /' >> "$MAN"
}

describe_app "$DEVICE_APP" "设备版 Runner.app（flutter build ios --release --no-codesign）"
describe_app "$SIM_APP" "模拟器版 Runner.app（flutter build ios --simulator --debug）"

# 体积数据（供 summary / run.json 使用）
: > "$CI_OUT/sizes.txt"
record_size() {
  name="$1"
  dir="$2"
  if [ -d "$dir" ]; then
    kb="$(du -sk "$dir" 2>/dev/null | cut -f1)"
    echo "$name"_app_bytes="$((${kb:-0} * 1024))" >> "$CI_OUT/sizes.txt"
    echo "$name"_app_human="$(du -sh "$dir" 2>/dev/null | cut -f1)" >> "$CI_OUT/sizes.txt"
  fi
}
record_size device "$DEVICE_APP"
record_size sim "$SIM_APP"

# 归档设备版 .app（DoD 要求产物归档）；模拟器版只登记清单，避免仓库膨胀
if [ -d "$DEVICE_APP" ]; then
  ( cd "$APP_DIR/build/ios/iphoneos" && ditto -c -k --sequesterRsrc --keepParent Runner.app "$CI_OUT/Runner-device-release.app.zip" ) >> "$BUILD_LOG" 2>&1 || true
  if [ -f "$CI_OUT/Runner-device-release.app.zip" ]; then
    zip_kb="$(du -sk "$CI_OUT/Runner-device-release.app.zip" 2>/dev/null | cut -f1)"
    echo "device_zip_bytes=$((${zip_kb:-0} * 1024))" >> "$CI_OUT/sizes.txt"
    echo "device_zip_human=$(du -h "$CI_OUT/Runner-device-release.app.zip" | cut -f1)" >> "$CI_OUT/sizes.txt"
    log "已归档设备版 .app -> Runner-device-release.app.zip ($(du -h "$CI_OUT/Runner-device-release.app.zip" | cut -f1))"
    manifest_line ""
    manifest_line "## 归档"
    manifest_line "- Runner-device-release.app.zip（设备版 .app 压缩包）"
  fi
fi

# golden 测试失败时 flutter_test 会写 test/failures/（workflow 在测试前已清空该目录）
if [ -d "$APP_DIR/test/failures" ] && [ -n "$(find "$APP_DIR/test/failures" -type f -print -quit)" ]; then
  tar -czf "$CI_OUT/test-failures.tar.gz" -C "$APP_DIR/test" failures >> "$BUILD_LOG" 2>&1 || true
  if [ -f "$CI_OUT/test-failures.tar.gz" ]; then
    log "已打包 golden 失败证据 -> test-failures.tar.gz ($(du -h "$CI_OUT/test-failures.tar.gz" | cut -f1))"
  fi
fi

# 从全量日志抽失败行，方便快速扫
if [ -f "$BUILD_LOG" ]; then
  grep -E '\[E\]|Some tests failed|Test failed|EXCEPTION CAUGHT|FAILED' "$BUILD_LOG" > "$CI_OUT/test-failures.txt" 2>/dev/null || true
  log "test-failures.txt: $(wc -l < "$CI_OUT/test-failures.txt" | tr -d ' ') 行"
fi

# 关闭冒烟用过的模拟器（integration_test 之后统一收尾）
if [ -f "$CI_OUT/sim-udid.txt" ]; then
  SIM_UDID="$(head -1 "$CI_OUT/sim-udid.txt" 2>/dev/null || true)"
  if [ -n "$SIM_UDID" ]; then
    xcrun simctl shutdown "$SIM_UDID" >> "$BUILD_LOG" 2>&1 || true
    log "已关闭模拟器 $SIM_UDID"
  fi
fi

log "证据文件:"
ls -la "$CI_OUT" | tee -a "$BUILD_LOG"
