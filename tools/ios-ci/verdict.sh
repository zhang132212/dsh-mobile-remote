#!/usr/bin/env bash
# 汇总 iOS job 各步骤结果：写 ci-out/steps.txt、status.txt、failed-steps.txt、allowed-steps.txt、summary.md，
# 并追加到 GitHub Step Summary。始终 exit 0；红/绿由 report job 的门禁步骤决定。
# ALLOW_FAIL_STEPS：允许失败但不影响结论的步骤名（空格分隔），例如首次接入的 integration-test。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

step "verdict"

ALLOW_TEST_FAIL="${ALLOW_TEST_FAIL:-false}"
ALLOW_FAIL_STEPS="${ALLOW_FAIL_STEPS:-}"
if [ "$ALLOW_TEST_FAIL" = "true" ]; then
  ALLOW_FAIL_STEPS="$ALLOW_FAIL_STEPS test"
fi

record_step() {
  printf '%s=%s\n' "$1" "$2" >> "$CI_OUT/steps.txt"
}
: > "$CI_OUT/steps.txt"
record_step checkout "${OUT_CHECKOUT:-missing}"
record_step env "${OUT_ENV:-missing}"
record_step ios-project "${OUT_IOS_PROJECT:-missing}"
record_step install-flutter "${OUT_INSTALL:-missing}"
record_step pub-get "${OUT_PUB:-missing}"
record_step analyze "${OUT_ANALYZE:-missing}"
record_step test "${OUT_TEST:-missing}"
record_step build-device "${OUT_BUILD_DEVICE:-missing}"
record_step build-sim "${OUT_BUILD_SIM:-missing}"
record_step sim-smoke "${OUT_SMOKE:-missing}"
record_step integration-test "${OUT_INTEGRATION:-missing}"
record_step collect-artifacts "${OUT_COLLECT:-missing}"

raw_failed=""
skipped=""
while IFS='=' read -r name outcome; do
  [ -n "$name" ] || continue
  case "$outcome" in
    success) ;;
    skipped) skipped="$skipped $name" ;;
    *) raw_failed="$raw_failed $name" ;;
  esac
done < "$CI_OUT/steps.txt"
skipped="$(echo $skipped)"

failed=""
allowed=""
for item in $raw_failed; do
  case " $ALLOW_FAIL_STEPS " in
    *" $item "*) allowed="$allowed $item" ;;
    *) failed="$failed $item" ;;
  esac
done
failed="$(echo $failed)"
allowed="$(echo $allowed)"

if [ -n "$failed" ]; then
  status="failure"
else
  status="success"
fi
printf '%s\n' "$status" > "$CI_OUT/status.txt"
printf '%s\n' "${failed:-(无)}" > "$CI_OUT/failed-steps.txt"
printf '%s\n' "${allowed:-(无)}" > "$CI_OUT/allowed-steps.txt"

smoke_value() { sed -n "s/^$1=//p" "$CI_OUT/smoke.txt" 2>/dev/null | head -1; }
sizes_value() { sed -n "s/^$1=//p" "$CI_OUT/sizes.txt" 2>/dev/null | head -1; }

{
  echo "# iOS CI 运行摘要（iOS job）"
  echo ""
  if [ "$status" = "success" ]; then
    echo "- 结论：✅ **success**"
  else
    echo "- 结论：❌ **failure**"
  fi
  if [ -n "$allowed" ]; then
    echo "- 备注：以下步骤失败但按允许列表放行（不影响结论）：$allowed"
  fi
  echo "- 仓库：${GITHUB_REPOSITORY:-?}　分支：${GITHUB_REF_NAME:-?}　commit：${GITHUB_SHA:-?}"
  echo "- run：${GITHUB_RUN_ID:-?}（attempt ${GITHUB_RUN_ATTEMPT:-1}）　触发：${GITHUB_EVENT_NAME:-?}"
  echo "- runner：${RUNNER_NAME:-?}（${RUNNER_OS:-?}/${RUNNER_ARCH:-?}）"
  echo ""
  echo "## 步骤结果"
  echo ""
  echo "| 步骤 | 结果 |"
  echo "| --- | --- |"
  while IFS='=' read -r name outcome; do
    [ -n "$name" ] || continue
    case "$outcome" in
      success) mark="✅ success" ;;
      skipped) mark="⏭️ skipped" ;;
      *) mark="❌ $outcome" ;;
    esac
    echo "| $name | $mark |"
  done < "$CI_OUT/steps.txt"
  echo ""
  echo "## 性能 / 冒烟证据（模拟器 debug 构建）"
  echo ""
  if [ -f "$CI_OUT/smoke.txt" ]; then
    echo "| 指标 | 值 |"
    echo "| --- | --- |"
    echo "| 启动 PID | $(smoke_value pid) |"
    echo "| simctl launch 调用耗时(ms) | $(smoke_value launch_call_ms) |"
    echo "| 启动到首帧(ms，约 1s 精度) | $(smoke_value first_frame_elapsed_ms) |"
    echo "| 应用容器路径 | $(smoke_value app_container) |"
    echo "| 模拟器版 Runner.app | $(smoke_value sim_app_human)（$(smoke_value sim_app_bytes) bytes） |"
    echo "| Runner 可执行文件 | $(smoke_value runner_binary_bytes) bytes |"
    echo "| 设备版 Runner.app | $(sizes_value device_app_human)（$(sizes_value device_app_bytes) bytes） |"
    echo "| 设备版 .app 归档 zip | $(sizes_value device_zip_human) |"
    echo "| Impeller 日志命中 | $(smoke_value impeller_log) |"
    echo ""
    echo "说明：Flutter 3.47 在 iOS 上默认启用 Impeller（Metal）渲染；设备版为 release 构建，"
    echo "模拟器版为 debug（JIT + 调试开销），启动耗时仅用于冒烟观察，不代表真机 release 性能。"
  else
    echo "（冒烟未执行或无 smoke.txt）"
  fi
  echo ""
  echo "## 失败 / 未完成步骤"
  echo ""
  if [ -n "$failed" ]; then
    for item in $failed; do
      echo "- $item"
    done
  else
    echo "（无）"
  fi
  if [ -n "$allowed" ]; then
    echo ""
    echo "> ⚠️ **以下步骤失败但被允许列表放行，不能当成绿**：$allowed —— 例如 integration-test 失败说明端到端冒烟没跑通，需人工确认。"
    echo ""
    for item in $allowed; do
      echo "- $item"
    done
  fi
  INTEG_OUTCOME="$(sed -n 's/^integration-test=//p' "$CI_OUT/steps.txt" 2>/dev/null | head -1)"
  echo ""
  echo "## 端到端冒烟（integration_test）"
  echo ""
  case "$INTEG_OUTCOME" in
    success) echo "✅ **integration-test: success** —— 模拟器上真机形态端到端冒烟已跑通（不是允许失败放行）。" ;;
    skipped) echo "⏭️ integration-test: skipped（前置步骤失败或未执行）。" ;;
    "") echo "integration-test: 未记录（步骤未运行）。" ;;
    *) echo "❌ **integration-test: $INTEG_OUTCOME** —— 当前在 ALLOW_FAIL_STEPS 里放行（不影响结论），但这说明端到端冒烟没跑通，需人工确认。" ;;
  esac
  if [ -f "$CI_OUT/test-failures.txt" ] && [ -s "$CI_OUT/test-failures.txt" ]; then
    echo ""
    echo "## flutter test 失败行（摘自全量日志，前 15 行）"
    echo ""
    head -15 "$CI_OUT/test-failures.txt" | sed 's/^/    /'
  fi
  if [ -n "$skipped" ]; then
    echo ""
    echo "跳过（前置步骤失败导致）："
    for item in $skipped; do
      echo "- $item"
    done
  fi
  echo ""
  echo "## 证据文件"
  echo ""
  [ -f "$CI_OUT/smoke.png" ] && echo "- smoke.png：模拟器启动后截图"
  [ -f "$CI_OUT/Runner-device-release.app.zip" ] && echo "- Runner-device-release.app.zip：设备版 .app 归档"
  [ -f "$CI_OUT/test-failures.txt" ] && echo "- test-failures.txt：失败行抽取（$(wc -l < "$CI_OUT/test-failures.txt" | tr -d ' ') 行）"
  [ -f "$CI_OUT/test-failures.tar.gz" ] && echo "- test-failures.tar.gz：golden 失败图（master/test/diff）"
  echo "- build.log：全量日志"
  echo "- artifact-manifest.txt：产物清单（大小 / bundle id / sha256 / 架构）"
  echo ""
  echo "## 取回方式（无需 GitHub API token）"
  echo ""
  echo "    git fetch origin ci-artifacts"
  echo "    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out"
} > "$CI_OUT/summary.md"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$CI_OUT/summary.md" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

log "iOS job 结论: $status"
log "失败步骤: ${failed:-(无)}"
log "允许失败: ${allowed:-(无)}"
log "summary.md 已生成"
