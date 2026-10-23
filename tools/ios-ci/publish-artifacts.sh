#!/usr/bin/env bash
# 把 ci-out 全部产物推到 ci-artifacts 分支：新建临时 git 仓库 -> 孤儿提交 -> force push。
# 幂等：每次运行覆盖整个分支，只保留最近一次运行的产物；业务分支不受影响。
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

for file in "$CI_OUT"/*; do
  [ -f "$file" ] || continue
  size="$(stat -f%z "$file" 2>/dev/null || echo 0)"
  if [ "$size" -gt "$MAX_BYTES" ] 2>/dev/null; then
    log "⚠️ 跳过超大文件（>$MAX_BYTES bytes）: $(basename "$file") ($(du -h "$file" | cut -f1)）"
    continue
  fi
  cp "$file" "$WORK"/
done

{
  echo "# ci-artifacts —— iOS CI 运行产物（自动生成，勿手改）"
  echo ""
  echo "本分支由 .github/workflows/ios.yml 在每次 iOS CI 运行后用孤儿提交强制覆盖，"
  echo "只存放日志、截图、产物清单与 .app 归档，不含源码；不要把它合并回业务分支。"
  echo ""
  echo "- 最近运行：run ${GITHUB_RUN_ID:-?} attempt ${GITHUB_RUN_ATTEMPT:-1}"
  echo "- 结论：$STATUS"
  echo "- commit：${GITHUB_SHA:-?}"
  echo "- 分支：${GITHUB_REF_NAME:-?}　runner：${RUNNER_NAME:-?}"
  echo ""
  echo "取回命令："
  echo ""
  echo "    git fetch origin ci-artifacts"
  echo "    git archive FETCH_HEAD | tar -x -C <目录>"
  echo ""
  echo "更详细说明见仓库 docs/ios-ci.md。"
} > "$WORK/README.md"

# 机器可读的 run.json（供无 token 轮询：raw.githubusercontent.com/<repo>/ci-artifacts/run.json）
python3 - "$WORK" <<'PY' >> "$BUILD_LOG" 2>&1 || log "⚠️ run.json 生成失败（不影响其他产物）"
import datetime
import json
import os
import sys

work = sys.argv[1]


def env(key, default=""):
    value = os.environ.get(key)
    return value if value else default


steps = {}
steps_path = os.path.join(work, "steps.txt")
if os.path.exists(steps_path):
    with open(steps_path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if "=" in line:
                name, outcome = line.split("=", 1)
                steps[name] = outcome

artifacts = []
for root, dirs, files in os.walk(work):
    dirs[:] = [item for item in dirs if item != ".git"]
    for name in files:
        path = os.path.join(root, name)
        rel = os.path.relpath(path, work).replace(os.sep, "/")
        artifacts.append({"path": rel, "bytes": os.path.getsize(path)})
artifacts.sort(key=lambda item: -item["bytes"])

failed = [name for name, outcome in steps.items() if outcome not in ("success", "skipped")]
meta = {
    "repository": env("GITHUB_REPOSITORY"),
    "ref": env("GITHUB_REF_NAME"),
    "commit": env("GITHUB_SHA"),
    "commit_short": env("GITHUB_SHA")[:8],
    "run_id": env("GITHUB_RUN_ID"),
    "run_attempt": env("GITHUB_RUN_ATTEMPT", "1"),
    "event": env("GITHUB_EVENT_NAME"),
    "run_url": "https://github.com/" + env("GITHUB_REPOSITORY") + "/actions/runs/" + env("GITHUB_RUN_ID"),
    "status": env("CI_STATUS", "unknown"),
    "failed_steps": failed,
    "steps": steps,
    "runner": env("RUNNER_NAME"),
    "runner_os": env("RUNNER_OS"),
    "runner_arch": env("RUNNER_ARCH"),
    "flutter_version": env("FLUTTER_VERSION"),
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "artifacts": artifacts,
    "note": "由 .github/workflows/ios.yml 自动生成；本分支只存 CI 产物，勿合并回业务分支。",
}
with open(os.path.join(work, "run.json"), "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
print("run.json 已生成:", len(artifacts), "个文件, status=", meta["status"])
PY

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
  log "✅ 产物已回传到 ${GITHUB_REPOSITORY}#$ARTIFACT_BRANCH"
  log "   run: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID:-?}"
  log "   取回: git fetch origin $ARTIFACT_BRANCH && git archive FETCH_HEAD | tar -x -C <dir>"
else
  log "❌ 推送 ci-artifacts 失败（详见 build.log；常见原因：仓库 Actions 权限不是 Read and write）"
  exit 1
fi
