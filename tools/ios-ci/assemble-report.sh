#!/usr/bin/env bash
# report job：把 ios / android 两个 job 的证据汇总到 ci-out-report，生成
# summary.md / run.json / status.txt / README.md，供 publish-artifacts.sh 推到 ci-artifacts 分支。
# 结论以 iOS 为准（Android 失败只记录）。verdict 已按允许列表过滤过失败步骤。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${STAGING:?STAGING 未设置（下载 artifact 的暂存目录）}"
IOS_JOB="${IOS_RESULT:-unknown}"
ANDROID_JOB="${ANDROID_RESULT:-unknown}"

step "assemble-report"

# 1) 拷贝证据（ios/ 与 android/ 子目录分开，互不覆盖）
rm -rf "$CI_OUT/ios" "$CI_OUT/android"
mkdir -p "$CI_OUT/ios" "$CI_OUT/android"
if [ -d "$STAGING/ios" ]; then
  cp -R "$STAGING/ios"/. "$CI_OUT/ios"/ 2>/dev/null || log "⚠️ 复制 ios 证据失败"
else
  log "⚠️ 未找到 ios 证据目录: $STAGING/ios"
fi
if [ -d "$STAGING/android" ]; then
  cp -R "$STAGING/android"/. "$CI_OUT/android"/ 2>/dev/null || log "⚠️ 复制 android 证据失败"
else
  log "⚠️ 未找到 android 证据目录: $STAGING/android"
fi

# 2) 结论：以 iOS 为准；Android 失败只记录（status.txt 必须在证据拷贝之后读）
IOS_STATUS="$(cat "$CI_OUT/ios/status.txt" 2>/dev/null || echo missing)"
ANDROID_STATUS="$(cat "$CI_OUT/android/status.txt" 2>/dev/null || echo missing)"
overall="success"
if [ "$IOS_STATUS" != "success" ] || [ "$IOS_JOB" != "success" ]; then
  overall="failure"
fi
printf '%s\n' "$overall" > "$CI_OUT/status.txt"

# 3) 失败 / 允许失败清单（verdict 已按 ALLOW_FAIL_STEPS 过滤）
: > "$CI_OUT/failed-steps.txt"
if [ -f "$CI_OUT/ios/failed-steps.txt" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "(无)") ;;
      *) echo "ios/$line" >> "$CI_OUT/failed-steps.txt" ;;
    esac
  done < "$CI_OUT/ios/failed-steps.txt"
fi
if [ "$IOS_JOB" != "success" ] && [ ! -s "$CI_OUT/failed-steps.txt" ]; then
  echo "ios job: $IOS_JOB" >> "$CI_OUT/failed-steps.txt"
fi
: > "$CI_OUT/allowed-steps.txt"
if [ -f "$CI_OUT/ios/allowed-steps.txt" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "(无)") ;;
      *) echo "ios/$line" >> "$CI_OUT/allowed-steps.txt" ;;
    esac
  done < "$CI_OUT/ios/allowed-steps.txt"
fi

# 4) 证据字段
smoke_value() { sed -n "s/^$1=//p" "$CI_OUT/ios/smoke.txt" 2>/dev/null | head -1; }
sizes_value() { sed -n "s/^$1=//p" "$CI_OUT/ios/sizes.txt" 2>/dev/null | head -1; }
android_value() { sed -n "s/^$1=//p" "$CI_OUT/android/sizes.txt" 2>/dev/null | head -1; }
steps_table() {
  [ -f "$1" ] || return 0
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
  done < "$1"
}
allowed_list() {
  [ -f "$1" ] || return 0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      "(无)") ;;
      *) echo "- $line（失败但按允许列表放行，不影响结论）" ;;
    esac
  done < "$1"
}

{
  echo "# iOS CI 运行摘要"
  echo ""
  if [ "$overall" = "success" ]; then
    echo "- 结论：✅ **success**（iOS 通过；Android 回归结果见下）"
  else
    echo "- 结论：❌ **failure**（iOS 未通过）"
  fi
  echo "- 仓库：${GITHUB_REPOSITORY:-?}　分支：${GITHUB_REF_NAME:-?}"
  echo "- commit：${GITHUB_SHA:-?}"
  echo "- run：${GITHUB_RUN_ID:-?}（attempt ${GITHUB_RUN_ATTEMPT:-1}）　触发：${GITHUB_EVENT_NAME:-?}"
  echo "- 运行链接：https://github.com/${GITHUB_REPOSITORY:-?}/actions/runs/${GITHUB_RUN_ID:-?}"
  echo "- Flutter：3.47.7 stable（Dart 3.13.5）"
  echo ""
  echo "## iOS（主结论）"
  echo ""
  echo "- job 结果：$IOS_JOB"
  echo "- 证据结论：$IOS_STATUS"
  echo ""
  steps_table "$CI_OUT/ios/steps.txt"
  if [ -s "$CI_OUT/failed-steps.txt" ]; then
    echo ""
    echo "失败 / 未完成步骤："
    echo ""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      echo "- $line"
    done < "$CI_OUT/failed-steps.txt"
  fi
  if [ -s "$CI_OUT/allowed-steps.txt" ]; then
    echo ""
    echo "允许失败（不影响结论）："
    echo ""
    allowed_list "$CI_OUT/allowed-steps.txt"
  fi
  echo ""
  echo "## 性能 / 冒烟证据（模拟器 debug 构建）"
  echo ""
  echo "| 指标 | 值 |"
  echo "| --- | --- |"
  echo "| 启动 PID | $(smoke_value pid) |"
  echo "| simctl launch 调用耗时(ms) | $(smoke_value launch_call_ms) |"
  echo "| 启动到首帧(ms，约 1s 精度) | $(smoke_value first_frame_elapsed_ms) |"
  echo "| 应用容器路径 | $(smoke_value app_container) |"
  echo "| 模拟器版 Runner.app | $(smoke_value sim_app_human)（$(smoke_value sim_app_bytes) bytes） |"
  echo "| 设备版 Runner.app | $(sizes_value device_app_human)（$(sizes_value device_app_bytes) bytes） |"
  echo "| 设备版 .app 归档 zip | $(sizes_value device_zip_human) |"
  echo "| Impeller 日志命中 | $(smoke_value impeller_log) |"
  echo ""
  echo "说明：Flutter 3.47 在 iOS 上默认启用 Impeller（Metal）渲染；设备版为 release 构建，"
  echo "模拟器版为 debug 构建（JIT + 调试开销），启动耗时只用于冒烟观察，不代表真机 release 性能。"
  echo ""
  echo "## Android 回归（非阻塞）"
  echo ""
  echo "- job 结果：$ANDROID_JOB"
  echo "- 证据结论：$ANDROID_STATUS"
  echo "- release APK：$(android_value apk_human)（$(android_value apk_bytes) bytes）"
  echo "- 说明：验证 Dart 侧改动没有破坏 Android 构建；失败不阻塞 iOS 结论。"
  echo ""
  echo "## 产物目录"
  echo ""
  echo "- ios/：build.log（全量日志）、smoke.png（模拟器截图）、summary.md、artifact-manifest.txt、"
  echo "  sizes.txt、smoke.txt、test-failures.txt/tar.gz（若有失败）、Runner-device-release.app.zip（设备版 .app 归档）"
  echo "- android/：build.log、summary.md、artifact-manifest.txt、sizes.txt"
  echo "- run.json：机器可读运行信息（状态 / 各步骤 / 产物清单）"
  echo ""
  echo "## 取回方式（无需 GitHub API token）"
  echo ""
  echo "    git fetch origin ci-artifacts"
  echo "    mkdir -p ci-artifacts-out && git archive FETCH_HEAD | tar -x -C ci-artifacts-out"
  echo ""
  echo "或直接读单个文件（raw.githubusercontent.com 会缓存，约 5 分钟）："
  echo ""
  echo "    https://raw.githubusercontent.com/${GITHUB_REPOSITORY:-?}/ci-artifacts/summary.md"
} > "$CI_OUT/summary.md"

# 5) README.md（给 ci-artifacts 分支的人看）
{
  echo "# ci-artifacts —— CI 运行产物（自动生成，勿手改）"
  echo ""
  echo "本分支由 .github/workflows/ios.yml 的 report job 在每次 CI 运行后强制覆盖（孤儿提交），"
  echo "只存放日志 / 截图 / 产物清单 / .app 归档，不含源码；不要合并回业务分支。"
  echo ""
  echo "- 最近运行：run ${GITHUB_RUN_ID:-?} attempt ${GITHUB_RUN_ATTEMPT:-1}"
  echo "- 结论：$overall"
  echo "- commit：${GITHUB_SHA:-?}　分支：${GITHUB_REF_NAME:-?}"
  echo "- runner：ios=macOS、android=ubuntu"
  echo ""
  echo "目录结构："
  echo ""
  echo "    ios/       iOS job 证据（build.log / smoke.png / summary.md / artifact-manifest.txt / sizes.txt / smoke.txt）"
  echo "    android/   Android job 证据（build.log / summary.md / artifact-manifest.txt / sizes.txt）"
  echo "    summary.md 本次运行总摘要"
  echo "    run.json   机器可读运行信息"
  echo ""
  echo "取回命令："
  echo ""
  echo "    git fetch origin ci-artifacts"
  echo "    git archive FETCH_HEAD | tar -x -C <目录>"
  echo ""
  echo "详细说明见仓库 docs/ios-ci.md。"
} > "$CI_OUT/README.md"

# 6) run.json（机器可读）
python3 - "$CI_OUT" <<'PY' >> "$BUILD_LOG" 2>&1 || log "⚠️ run.json 生成失败（不影响其他产物）"
import datetime
import json
import os
import sys

work = sys.argv[1]


def env(key, default=""):
    value = os.environ.get(key)
    return value if value else default


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except Exception:
        return "missing"


def read_kv(path):
    result = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if "=" in line:
                    key, value = line.split("=", 1)
                    result[key] = value
    except Exception:
        pass
    return result


jobs = {}
for name in ("ios", "android"):
    base = os.path.join(work, name)
    jobs[name] = {
        "job_result": env("IOS_RESULT" if name == "ios" else "ANDROID_RESULT", "unknown"),
        "evidence_status": read_text(os.path.join(base, "status.txt")),
        "steps": read_kv(os.path.join(base, "steps.txt")),
        "smoke": read_kv(os.path.join(base, "smoke.txt")),
        "sizes": read_kv(os.path.join(base, "sizes.txt")),
    }

artifacts = []
for root, dirs, files in os.walk(work):
    dirs[:] = [item for item in dirs if item != ".git"]
    for name in files:
        path = os.path.join(root, name)
        rel = os.path.relpath(path, work).replace(os.sep, "/")
        artifacts.append({"path": rel, "bytes": os.path.getsize(path)})
artifacts.sort(key=lambda item: -item["bytes"])

meta = {
    "repository": env("GITHUB_REPOSITORY"),
    "ref": env("GITHUB_REF_NAME"),
    "commit": env("GITHUB_SHA"),
    "commit_short": env("GITHUB_SHA")[:8],
    "run_id": env("GITHUB_RUN_ID"),
    "run_attempt": env("GITHUB_RUN_ATTEMPT", "1"),
    "event": env("GITHUB_EVENT_NAME"),
    "run_url": "https://github.com/" + env("GITHUB_REPOSITORY") + "/actions/runs/" + env("GITHUB_RUN_ID"),
    "status": read_text(os.path.join(work, "status.txt")),
    "flutter_version": "3.47.7",
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "jobs": jobs,
    "artifacts": artifacts,
    "note": "由 .github/workflows/ios.yml 自动生成；本分支只存 CI 产物，勿合并回业务分支。",
}
with open(os.path.join(work, "run.json"), "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
print("run.json 已生成:", len(artifacts), "个文件, status=", meta["status"])
PY

if [ ! -f "$CI_OUT/run.json" ]; then
  printf '{"status": "%s", "generated_at": "%s", "note": "python3 不可用，降级生成"}\n' "$overall" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$CI_OUT/run.json"
  log "run.json 用降级格式生成（python3 不可用）"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  cat "$CI_OUT/summary.md" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
fi

log "汇总完成：iOS=$IOS_STATUS(job=$IOS_JOB) Android=$ANDROID_STATUS(job=$ANDROID_JOB) 总体=$overall"
log "ci-out-report 内容:"
ls -la "$CI_OUT" | tee -a "$BUILD_LOG"
