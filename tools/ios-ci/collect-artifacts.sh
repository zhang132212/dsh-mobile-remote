#!/usr/bin/env bash
# 收集本次 CI 的产物到 ci-out：产物清单、设备版 .app 归档、golden 失败证据、失败行抽取。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
MAN="$CI_OUT/artifact-manifest.txt"

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

describe_app "$APP_DIR/build/ios/iphoneos/Runner.app" "设备版 Runner.app（flutter build ios --release --no-codesign）"
describe_app "$APP_DIR/build/ios/iphonesimulator/Runner.app" "模拟器版 Runner.app（flutter build ios --simulator --debug）"

# 归档设备版 .app（DoD 要求产物归档）；模拟器版只登记清单，避免仓库膨胀
ARCH_SRC="$APP_DIR/build/ios/iphoneos/Runner.app"
if [ -d "$ARCH_SRC" ]; then
  ( cd "$APP_DIR/build/ios/iphoneos" && ditto -c -k --sequesterRsrc --keepParent Runner.app "$CI_OUT/Runner-device-release.app.zip" ) >> "$BUILD_LOG" 2>&1 || true
  if [ -f "$CI_OUT/Runner-device-release.app.zip" ]; then
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

log "ci-out 目录内容:"
ls -la "$CI_OUT" | tee -a "$BUILD_LOG"
