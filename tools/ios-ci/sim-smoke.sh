#!/usr/bin/env bash
# iOS Simulator 冒烟：boot 一台可用 iPhone -> 安装 iphonesimulator/Runner.app
# -> 启动 -> 等待 -> 截图 -> 进程存活校验（崩溃则抓诊断）。
# 注意：设备版 build/ios/iphoneos/Runner.app 不能装进模拟器，这里用 --simulator 产物。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
APP_PATH="$APP_DIR/build/ios/iphonesimulator/Runner.app"
WAIT_SEC="${SMOKE_WAIT_SEC:-12}"
UDID=""

step "sim-smoke"

collect_diagnostics() {
  log "---- 崩溃诊断 ----"
  xcrun simctl spawn "$UDID" launchctl list > "$CI_OUT/launchctl-list.txt" 2>&1 || true
  log "已保存 launchctl-list.txt"
  REPORTS="$(ls -t "$HOME/Library/Logs/DiagnosticReports" 2>/dev/null | grep -i runner | head -3 || true)"
  if [ -n "$REPORTS" ]; then
    for report in $REPORTS; do
      cp "$HOME/Library/Logs/DiagnosticReports/$report" "$CI_OUT/" 2>/dev/null || true
      log "保存崩溃报告: $report"
    done
  fi
  xcrun simctl spawn "$UDID" log show --last 2m --style compact 2>/dev/null | grep -iE 'Runner|crash|fatal|exception|flutter' | tail -120 > "$CI_OUT/sim-log-tail.txt" 2>&1 || true
  log "已保存 sim-log-tail.txt"
  xcrun simctl io "$UDID" screenshot "$CI_OUT/smoke-fail.png" >/dev/null 2>&1 || true
}

if [ ! -d "$APP_PATH" ]; then
  log "❌ 未找到模拟器产物: $APP_PATH（需要先 flutter build ios --simulator --debug）"
  exit 1
fi
log "模拟器 App: $APP_PATH ($(du -sh "$APP_PATH" | cut -f1))"

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Info.plist" 2>/dev/null || true)"
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist" 2>/dev/null || true)"
fi
if [ -z "$BUNDLE_ID" ]; then
  log "❌ 无法读取 app 的 CFBundleIdentifier"
  exit 1
fi
log "bundle id: $BUNDLE_ID"

xcrun simctl list devices available --json > "$CI_OUT/sim-devices.json" 2>/dev/null || true
SIM_INFO="$(python3 - "$CI_OUT/sim-devices.json" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("")
    sys.exit(0)

candidates = []
for runtime, devices in (data.get("devices") or {}).items():
    if "iOS" not in runtime:
        continue
    for device in devices:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        candidates.append((runtime, name, device.get("udid", "")))

if not candidates:
    print("")
    sys.exit(0)

candidates.sort(reverse=True)
runtime, name, udid = candidates[0]
print(udid)
print(runtime.split(".")[-1] + " / " + name)
PY
)"
UDID="$(printf '%s\n' "$SIM_INFO" | sed -n '1p')"
SIM_DESC="$(printf '%s\n' "$SIM_INFO" | sed -n '2p')"
if [ -z "$UDID" ]; then
  log "❌ 没有可用的 iPhone 模拟器（xcrun simctl list devices available 为空）"
  exit 1
fi
log "选中模拟器: $UDID ($SIM_DESC)"

# 状态栏美化（让截图更像真机；失败不影响冒烟）
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 >/dev/null 2>&1 || true

log "启动模拟器（已启动则忽略报错）…"
xcrun simctl boot "$UDID" >> "$BUILD_LOG" 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >> "$BUILD_LOG" 2>&1 || log "（bootstatus 返回非 0，继续尝试安装）"

log "安装 App…"
if ! xcrun simctl install "$UDID" "$APP_PATH" >> "$BUILD_LOG" 2>&1; then
  log "❌ simctl install 失败（详见 build.log）"
  collect_diagnostics
  exit 1
fi
log "安装成功"

log "启动 App: xcrun simctl launch"
LAUNCH_OUT="$(xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" 2>&1)"
LAUNCH_RC=$?
log "launch rc=$LAUNCH_RC: $LAUNCH_OUT"
if [ "$LAUNCH_RC" -ne 0 ]; then
  log "❌ simctl launch 失败"
  collect_diagnostics
  exit 1
fi

log "等待 $WAIT_SEC 秒观察是否崩溃…"
sleep "$WAIT_SEC"

SCREENSHOT="$CI_OUT/smoke.png"
if xcrun simctl io "$UDID" screenshot "$SCREENSHOT" >> "$BUILD_LOG" 2>&1 && [ -f "$SCREENSHOT" ]; then
  SIZE="$(stat -f%z "$SCREENSHOT" 2>/dev/null || echo 0)"
  log "📸 截图 smoke.png（$SIZE bytes）"
  if [ "$SIZE" -lt 20000 ] 2>/dev/null; then
    log "⚠️ 截图偏小，可能是纯色/黑屏（首帧未渲染）"
  fi
else
  log "⚠️ simctl io screenshot 失败"
fi

if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "UIKitApplication:$BUNDLE_ID" >/dev/null 2>&1; then
  log "✅ App 进程存活（未崩溃）"
else
  log "❌ App 进程不在 launchctl 列表中（疑似启动即崩溃）"
  collect_diagnostics
  exit 1
fi

xcrun simctl terminate "$UDID" "$BUNDLE_ID" >> "$BUILD_LOG" 2>&1 || true
xcrun simctl shutdown "$UDID" >> "$BUILD_LOG" 2>&1 || true
{
  echo "udid=$UDID"
  echo "simulator=$SIM_DESC"
  echo "bundle_id=$BUNDLE_ID"
  echo "wait_seconds=$WAIT_SEC"
  echo "screenshot=s$(echo x)"
} > "$CI_OUT/smoke.txt"
log "✅ 模拟器冒烟通过"
