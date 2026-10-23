#!/usr/bin/env bash
# 记录 Android release APK 回归构建的产物/结论（非阻塞 job 的证据）。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
APK="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
OUTCOME="${OUT_BUILD_APK:-missing}"

step "android-collect"

if [ "$OUTCOME" = "success" ] && [ -f "$APK" ]; then
  status="success"
else
  status="failure"
fi

{
  echo "# Android release APK 回归构建产物清单"
  echo ""
  echo "- 生成时间: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "- 仓库: ${GITHUB_REPOSITORY:-?}　ref: ${GITHUB_REF_NAME:-?}"
  echo "- commit: ${GITHUB_SHA:-?}　run: ${GITHUB_RUN_ID:-?} attempt ${GITHUB_RUN_ATTEMPT:-1}"
  echo ""
  echo "## APK"
  if [ -f "$APK" ]; then
    echo "- path: $APK"
    echo "- size: $(du -h "$APK" | cut -f1)"
    echo "- bytes: $(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK" 2>/dev/null || echo '?')"
    echo "- sha256: $(sha256sum "$APK" 2>/dev/null | cut -d' ' -f1 || shasum -a 256 "$APK" 2>/dev/null | cut -d' ' -f1)"
    echo "- file: $(file "$APK" 2>/dev/null | sed 's/^[^:]*: //')"
  else
    echo "- 状态: 不存在（构建失败或未执行）"
  fi
  echo ""
  echo "## 输出目录"
  ls -la "$APP_DIR/build/app/outputs/flutter-apk" 2>/dev/null || echo "(目录不存在)"
} > "$CI_OUT/artifact-manifest.txt" 2>&1

cat "$CI_OUT/artifact-manifest.txt" | tee -a "$BUILD_LOG"

{
  echo "apk_outcome=$OUTCOME"
  if [ -f "$APK" ]; then
    echo "apk_bytes=$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK" 2>/dev/null || echo '?')"
    echo "apk_human=$(du -h "$APK" | cut -f1)"
  fi
} > "$CI_OUT/sizes.txt"

printf '%s\n' "$status" > "$CI_OUT/status.txt"

{
  echo "# Android 回归构建（非阻塞）"
  echo ""
  if [ "$status" = "success" ]; then
    echo "- 结论：✅ success"
  else
    echo "- 结论：❌ failure"
  fi
  echo "- flutter build apk --release：$OUTCOME"
  if [ -f "$APK" ]; then
    echo "- APK 大小：$(du -h "$APK" | cut -f1)"
  fi
  echo "- 说明：仓库无 key.properties，release 构建回退 debug 签名（见 android/app/build.gradle.kts）；"
  echo "  本 job 只验证 Dart 侧改动没有破坏 Android 构建，失败不阻塞 iOS 结论。"
} > "$CI_OUT/summary.md"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$CI_OUT/summary.md" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

log "Android 回归结论: $status（build apk: $OUTCOME）"
