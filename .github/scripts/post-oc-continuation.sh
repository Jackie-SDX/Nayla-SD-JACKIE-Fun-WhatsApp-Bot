#!/usr/bin/env bash
set -euo pipefail

target="$TARGET_NUMBER"
base_ref="$BASE_REF"
repo="$GITHUB_REPOSITORY"
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0

# Single source of truth for control-plane defaults (see oc-control-plane-config.sh).
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$script_dir/oc-control-plane-config.sh" ]]; then
  source "$script_dir/oc-control-plane-config.sh"
else
  OC_CONTROL_PLANE_AGENT_TIMEOUT_MINUTES=350
fi

branch="$(git branch --show-current 2>/dev/null || printf '%s' 'unknown')"
sha="$(git rev-parse HEAD 2>/dev/null || printf '%s' 'unknown')"
status="$(git status --short 2>/dev/null || true)"
last_commit="$(git log -1 --oneline 2>/dev/null || printf '%s' 'unknown')"
run_id="$GITHUB_RUN_ID"
run_url="$GITHUB_SERVER_URL/$repo/actions/runs/$run_id"

open_prs="$(
  gh pr list --state open --limit 50 --json number,url,headRefName,headRefOid,baseRefName |
    jq -r --arg a "opencode/issue$target-" --arg c "oc/copilot-$target-" --arg base "$base_ref" '
      .[] | select(.baseRefName == $base) |
      select((.headRefName | startswith($a)) or (.headRefName | startswith($c))) |
      "#\(.number) \(.url) \(.headRefName) \(.headRefOid)"
    ' 2>/dev/null || true
)"

# Remote-target runs leave a machine-readable durable marker so a bare
# "/oc continue" can recover the exact target base/branch on a later run.
target_marker=""
if [[ "${OC_TARGET_MODE:-local}" == "remote" && -n "${OC_TARGET_REPO:-}" ]]; then
  oc_branch="$(git -C "${OC_TARGET_WORKSPACE:-.}" branch --show-current 2>/dev/null || printf '%s' 'unknown')"
  [[ -n "$oc_branch" && "$oc_branch" != "unknown" ]] || oc_branch="${OC_TARGET_BRANCH:-}"
  target_marker="<!-- oc-target-repo:${OC_TARGET_REPO} base:${OC_TARGET_BASE:-main} branch:${oc_branch:-unknown} -->"
fi

body="$(cat <<EOF
$target_marker
<!-- oc-checkpoint-run-id:$run_id issue:$target -->
## /oc execution checkpoint

The autonomous agent reached its controlled long-running execution budget (${OPENCODE_AGENT_TIMEOUT_MINUTES:-${OC_CONTROL_PLANE_AGENT_TIMEOUT_MINUTES:-350}}) without claiming task completion.

This is a recoverable timeout, not a success claim.

Resume with /oc continue. For a completed run with failed CI jobs, use /oc retry failed jobs instead; timed-out work should resume from this checkpoint rather than blindly rerun.

Execution:
- workflow run: $run_url
- runner branch: $branch
- runner HEAD: $sha
- last commit: $last_commit
- execution mode: ${OC_TARGET_MODE:-local}${target_marker:+ (remote target: $OC_TARGET_REPO @ ${OC_TARGET_BASE:-main}, branch: ${OC_TARGET_BRANCH:-})}

Working tree at timeout:
${status:-clean}

Agent-created Open PRs still visible for this target:
${open_prs:-none visible}

On resume, inspect the previous /oc request, this checkpoint, current repository state, existing branches/PRs, CI logs, and issue comments. Preserve existing partial work and evidence; do not create duplicate work solely because the previous process timed out.
EOF
)"

gh issue comment "$target" --body "$body"
