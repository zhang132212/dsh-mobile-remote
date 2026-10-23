#!/usr/bin/env bash
# iOS Simulator 冒烟：boot 一台可用 iPhone -> 安装 iphonesimulator/Runner.app
# -> 启动（记 PID / 调用耗时）-> 首帧检测（截图轮询）-> 截图 -> 进程存活校验（崩溃抓诊断）。
# 证据写入 ci-out/smoke.txt：PID、启动耗时、首帧耗时、容器路径、包体积、Impeller 日志命中。
# 注意 1：设备版 build/ios/iphoneos/Runner.app 不能装进模拟器，这里用 --simulator 产物。
# 注意 2：模拟器启动后保持 booted（UDID 写入 ci-out/sim-udid.txt），供后续 integration_test 复用；
#         由 collect-artifacts.sh 统一 shutdown。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${APP_DIR:?APP_DIR 未设置}"
APP_PATH="$APP_DIR/build/ios/iphonesimulator/Runner.app"
WAIT_SEC="${SMOKE_WAIT_SEC:-12}"
UDID=""
BUNDLE_ID=""
PID=""
LAUNCH_CALL_MS=""
FIRST_FRAME_MS=""

now_ms() {
  python3 -c 'import time; print(int(time.monotonic() * 1000))' 2>/dev/null || echo 0
}

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
printf '%s\n' "$UDID" > "$CI_OUT/sim-udid.txt"
printf '%s\n' "$SIM_DESC" > "$CI_OUT/sim-desc.txt"
{
  echo "udid=$UDID"
  echo "device=$SIM_DESC"
} > "$CI_OUT/sim-info.txt"

# 状态栏固定（截图更像真机，也保证首帧检测的截图基线稳定；失败不影响冒烟）
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

# 首帧检测基线：启动前截一张桌面图，之后截图内容变化 = App 首帧已渲染
HOME_SHOT="$CI_OUT/_sim_home.png"
HOME_MD5=""
if xcrun simctl io "$UDID" screenshot "$HOME_SHOT" >/dev/null 2>&1 && [ -f "$HOME_SHOT" ]; then
  HOME_MD5="$(md5 -q "$HOME_SHOT" 2>/dev/null || true)"
fi

log "启动 App: xcrun simctl launch"
T0="$(now_ms)"
LAUNCH_OUT="$(xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" 2>&1)"
LAUNCH_RC=$?
T1="$(now_ms)"
if [ "$T1" -gt "$T0" ] 2>/dev/null; then
  LAUNCH_CALL_MS=$((T1 - T0))
fi
log "launch rc=$LAUNCH_RC 调用耗时=${LAUNCH_CALL_MS:-?}ms: $LAUNCH_OUT"
PID="$(printf '%s' "$LAUNCH_OUT" | sed -n 's/.*: *\([0-9][0-9]*\).*/\1/p' | head -1)"
if [ "$LAUNCH_RC" -ne 0 ]; then
  log "❌ simctl launch 失败"
  collect_diagnostics
  exit 1
fi

ELAPSED=0
if [ -n "$HOME_MD5" ]; then
  log "首帧检测：每秒截图与桌面基线比对（最多 25s）…"
  while [ "$ELAPSED" -lt 25 ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
    POLL="$CI_OUT/_sim_poll.png"
    xcrun simctl io "$UDID" screenshot "$POLL" >/dev/null 2>&1 || continue
    CUR="$(md5 -q "$POLL" 2>/dev/null || true)"
    if [ -n "$CUR" ] && [ "$CUR" != "$HOME_MD5" ]; then
      NOW="$(now_ms)"
      if [ "$NOW" -gt "$T0" ] 2>/dev/null; then
        FIRST_FRAME_MS=$((NOW - T0))
      fi
      log "检测到画面变化（首帧已渲染），约 ${FIRST_FRAME_MS:-?}ms（截图轮询精度约 1s）"
      break
    fi
  done
  rm -f "$CI_OUT/_sim_poll.png"
else
  log "⚠️ 无法取得桌面基线截图，跳过首帧检测"
fi

REMAIN=$((WAIT_SEC - ELAPSED))
if [ "$REMAIN" -gt 0 ]; then
  log "继续等待 $REMAIN s 观察启动后稳定性…"
  sleep "$REMAIN"
fi

SCREENSHOT="$CI_OUT/smoke.png"
if xcrun simctl io "$UDID" screenshot "$SCREENSHOT" >> "$BUILD_LOG" 2>&1 && [ -f "$SCREENSHOT" ]; then
  SHOT_BYTES="$(stat -f%z "$SCREENSHOT" 2>/dev/null || echo 0)"
  log "📸 截图 smoke.png（$SHOT_BYTES bytes）"
  if [ "$SHOT_BYTES" -lt 20000 ] 2>/dev/null; then
    log "⚠️ 截图偏小，可能是纯色/黑屏（首帧可能未渲染）"
  fi
else
  SHOT_BYTES="?"
  log "⚠️ simctl io screenshot 失败"
fi

if ! xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -F "UIKitApplication:$BUNDLE_ID" >/dev/null 2>&1; then
  log "❌ App 进程不在 launchctl 列表中（疑似启动即崩溃）"
  collect_diagnostics
  exit 1
fi
log "✅ App 进程存活（未崩溃）"

CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" app 2>/dev/null || true)"
if [ -n "$CONTAINER" ]; then
  log "应用容器: $CONTAINER"
fi

SIM_KB="$(du -sk "$APP_PATH" 2>/dev/null | cut -f1)"
SIM_BYTES="$((${SIM_KB:-0} * 1024))"
SIM_HUMAN="$(du -sh "$APP_PATH" 2>/dev/null | cut -f1)"
BIN_BYTES="$(stat -f%z "$APP_PATH/Runner" 2>/dev/null || echo '?')"
IMPELLER_LOG="$(xcrun simctl spawn "$UDID" log show --last 2m --style compact 2>/dev/null | grep -i 'impeller' || true)"
printf '%s\n' "$IMPELLER_LOG" > "$CI_OUT/impeller.log"
IMPELLER_HITS="$(printf '%s\n' "$IMPELLER_LOG" | grep -c . || true)"
[ -n "${IMPELLER_HITS:-}" ] || IMPELLER_HITS=0
IMPELLER_SNIPPET="$(printf '%s\n' "$IMPELLER_LOG" | head -1)"

{
  echo "udid=$UDID"
  echo "simulator=$SIM_DESC"
  echo "bundle_id=$BUNDLE_ID"
  echo "pid=${PID:-unknown}"
  echo "launch_call_ms=${LAUNCH_CALL_MS:-unknown}"
  echo "first_frame_elapsed_ms=${FIRST_FRAME_MS:-unmeasured}"
  echo "app_container=${CONTAINER:-unknown}"
  echo "sim_app_bytes=$SIM_BYTES"
  echo "sim_app_human=${SIM_HUMAN:-?}"
  echo "runner_binary_bytes=$BIN_BYTES"
  echo "impeller_log=$IMPELLER_HITS"
  echo "impeller_snippet=$IMPELLER_SNIPPET"
  echo "wait_seconds=$WAIT_SEC"
  echo "screenshot=smoke.png"
  echo "screenshot_bytes=$SHOT_BYTES"
  echo "alive=yes"
  echo "keep_booted=yes"
} > "$CI_OUT/smoke.txt"

log "性能/冒烟证据: pid=${PID:-?} launch_call_ms=${LAUNCH_CALL_MS:-?} first_frame_elapsed_ms=${FIRST_FRAME_MS:-unmeasured} sim_app=${SIM_HUMAN:-?} impeller_log=$IMPELLER_HITS"

rm -f "$CI_OUT/_sim_home.png"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >> "$BUILD_LOG" 2>&1 || true
# 模拟器保持 booted，供 integration_test 复用；由 collect-artifacts.sh 统一 shutdown
log "✅ 模拟器冒烟通过（模拟器保持 booted 供 integration_test）"
