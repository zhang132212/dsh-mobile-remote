#!/usr/bin/env bash
# 汇总各步骤结果：写 ci-out/steps.txt、status.txt、failed-steps.txt、summary.md，
# 并追加到 GitHub Step Summary。始终 exit 0；红/绿由 workflow 最后的门禁步骤决定。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

step "verdict"

ALLOW_TEST_FAIL="${ALLOW_TEST_FAIL:-false}"

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
record_step collect-artifacts "${OUT_COLLECT:-missing}"

failed=""
skipped=""
while IFS='=' read -r name outcome; do
  [ -n "$name" ] || continue
  case "$outcome" in
    success) ;;
    skipped) skipped="$skipped $name" ;;
    *) failed="$failed $name" ;;
  esac
done < "$CI_OUT/steps.txt"
failed="$(echo $failed)"
skipped="$(echo $skipped)"

status="success"
note=""
if [ -n "$failed" ]; then
  if [ "$failed" = "test" ] && [ "$ALLOW_TEST_FAIL" = "true" ]; then
    status="success"
    note="flutter test 失败，但按 workflow_dispatch allow_test_failures=true 放行（仅排障用，正式判绿前需修复）"
    failed=""
  else
    status="failure"
  fi
fi
printf '%s\n' "$status" > "$CI_OUT/status.txt"
printf '%s\n' "${failed:-(无)}" > "$CI_OUT/failed-steps.txt"

ENV_INFO=""
if [ -f "$CI_OUT/env.txt" ]; then
  ENV_INFO="$(cat "$CI_OUT/env.txt")"
fi

{
  echo "# iOS CI 运行摘要"
  echo ""
  if [ "$status" = "success" ]; then
    echo "- 结论：✅ **success**"
  else
    echo "- 结论：❌ **failure**"
  fi
  if [ -n "$note" ]; then
    echo "- 备注：$note"
  fi
  echo "- 仓库：${GITHUB_REPOSITORY:-?}"
  echo "- 分支：${GITHUB_REF_NAME:-?}　commit：${GITHUB_SHA:-?}"
  echo "- run：${GITHUB_RUN_ID:-?}（attempt ${GITHUB_RUN_ATTEMPT:-1}）　触发：${GITHUB_EVENT_NAME:-?}"
  echo "- 运行链接：https://github.com/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
  echo ""
  echo "## 环境"
  echo ""
  echo "    $(printf '%s\n' "$ENV_INFO" | sed 's/^/    /')"
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
  echo "## 失败 / 未完成步骤"
  echo ""
  if [ -n "$failed" ]; then
    for item in $failed; do
      echo "- $item"
    done
  else
    echo "（无）"
  fi
  if [ -n "$skipped" ]; then
    echo ""
    echo "跳过（前置步骤失败导致）："
    for item in $skipped; do
      echo "- $item"
    done
  fi
  echo ""
  echo "## 产物"
  echo ""
  if [ -f "$CI_OUT/smoke.png" ]; then
    echo "- smoke.png：模拟器启动后截图"
  else
    echo "- smoke.png：无（冒烟未执行或截图失败）"
  fi
  if [ -f "$CI_OUT/Runner-device-release.app.zip" ]; then
    echo "- Runner-device-release.app.zip：设备版 .app 归档"
  fi
  if [ -f "$CI_OUT/test-failures.txt" ]; then
    echo "- test-failures.txt：从全量日志抽取的失败行（$(wc -l < "$CI_OUT/test-failures.txt" | tr -d ' ') 行）"
  fi
  if [ -f "$CI_OUT/test-failures.tar.gz" ]; then
    echo "- test-failures.tar.gz：golden 失败图（master/test/diff）"
  fi
  echo "- build.log：全量日志（含每个步骤输出）"
  echo "- artifact-manifest.txt：产物清单（大小 / bundle id / sha256 / 架构）"
  echo "- run.json：机器可读运行信息（供脚本/审计使用）"
  echo ""
  echo "## 取回方式（无需 GitHub API token）"
  echo ""
  echo "    git fetch origin ci-artifacts"
  echo "    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out"
  echo ""
  echo "真机（设备版）构建与模拟器冒烟分别执行，证据见上。"
} > "$CI_OUT/summary.md"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$CI_OUT/summary.md" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

log "结论: $status"
log "失败步骤: ${failed:-(无)}"
log "summary.md 已生成"
