#!/usr/bin/env bash
# 把 ci-out-report 全部产物（含 ios/ 与 android/ 子目录）推到 ci-artifacts 分支：
# 临时 git 仓库 -> 孤儿提交 -> force push。每次覆盖整个分支，只保留最近一次运行证据。
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

: "${GITHUB_TOKEN:?GITHUB_TOKEN 未设置（需要 permissions: contents: write）}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY 未设置}"
ARTIFACT_BRANCH="${ARTIFACTS_BRANCH:-ci-artifacts}"
STATUS="$(cat "$CI_OUT/status.txt" 2>/dev/null || echo unknown)"
COMMIT_SHORT="$(printf '%s' "${GITHUB_SHA:-unknown}" | cut -c1-8)"
MAX_BYTES="${ARTIFACT_MAX_BYTES:-62914560}"   # 单文件上限 60MB（GitHub 硬上限 100MB；控制推送耗时）

step "publish-artifacts (branch=$ARTIFACT_BRANCH status=$STATUS)"

WORK="${RUNNER_TEMP:-/tmp}/ci-artifacts-publish"
rm -rf "$WORK"
mkdir -p "$WORK"

SKIP_GLOBS="${ARTIFACT_SKIP_GLOBS:-}"   # 空格分隔的 glob，例如 "*.zip *.ips"
TOTAL="$(find "$CI_OUT" -type f 2>/dev/null | wc -l | tr -d ' ')"
# -print0 + read -d '' 处理带空格的文件名（bash 3.2 支持）
find "$CI_OUT" -type f -print0 2>/dev/null | while IFS= read -r -d '' src; do
  rel="${src#$CI_OUT/}"
  skip=""
  if [ -n "$SKIP_GLOBS" ]; then
    for glob in $SKIP_GLOBS; do
      case "$rel" in
        $glob) skip="1" ;;
      esac
      case "$(basename "$rel")" in
        $glob) skip="1" ;;
      esac
    done
  fi
  if [ -n "$skip" ]; then
    log "⚠️ 按 glob 跳过: $rel"
    continue
  fi
  size="$(stat -f%z "$src" 2>/dev/null || stat -c%s "$src" 2>/dev/null || echo 0)"
  if [ "$size" -gt "$MAX_BYTES" ] 2>/dev/null; then
    log "⚠️ 跳过超大文件（>$MAX_BYTES bytes）: $rel ($(du -h "$src" | cut -f1))"
    continue
  fi
  mkdir -p "$WORK/$(dirname "$rel")"
  cp "$src" "$WORK/$rel" || log "⚠️ 复制失败: $rel"
done
COPIED="$(find "$WORK" -type f 2>/dev/null | wc -l | tr -d ' ')"
log "待推送文件: $COPIED 个（总计 $TOTAL，跳过 $((TOTAL - COPIED)) 个）"

cd "$WORK" || exit 1
git init -q
git symbolic-ref HEAD "refs/heads/$ARTIFACT_BRANCH"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git config http.postBuffer 524288000
git add -A
git commit -q -m "ci(ios): run ${GITHUB_RUN_ID:-0} attempt ${GITHUB_RUN_ATTEMPT:-1} $STATUS $COMMIT_SHORT"

TOKEN_B64="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
git remote add origin "https://github.com/${GITHUB_REPOSITORY}.git"
if git -c http.extraheader="AUTHORIZATION: basic $TOKEN_B64" push -q --force origin "HEAD:refs/heads/$ARTIFACT_BRANCH" >> "$BUILD_LOG" 2>&1; then
  log "✅ 产物已回传到 ${GITHUB_REPOSITORY}#$ARTIFACT_BRANCH（status=$STATUS）"
  log "   run: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-?}"
  log "   取回: git fetch origin $ARTIFACT_BRANCH && git archive FETCH_HEAD | tar -x -C <dir>"
else
  log "❌ 推送 ci-artifacts 失败（详见 build.log；常见原因：Actions 权限不是 Read and write）"
  exit 1
fi
