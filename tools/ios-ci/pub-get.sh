#!/usr/bin/env bash
# flutter pub get（iOS / Android job 共用）：先对齐 lockfile 里的 hosted 源，再解析依赖。
# 背景：本地 lockfile 由国内镜像 pub.flutter-io.cn 生成，GitHub runner 访问 pub.dev 更稳。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
step "pub-get"
cd "$APP_DIR" || exit 1

if grep -q 'pub.flutter-io.cn' pubspec.lock 2>/dev/null; then
  sed -i '' 's#https://pub.flutter-io.cn#https://pub.dev#g' pubspec.lock 2>/dev/null || sed -i 's#https://pub.flutter-io.cn#https://pub.dev#g' pubspec.lock
  log "pubspec.lock: hosted 源由 pub.flutter-io.cn 改写为 pub.dev（仅 CI 工作区，不提交）"
fi

flutter --version 2>&1 | tee -a "$BUILD_LOG"
flutter pub get 2>&1 | tee -a "$BUILD_LOG"
