#!/usr/bin/env bash
set -euo pipefail

target="$TARGET_NUMBER"
base_ref="$BASE_REF"
repo="$GITHUB_REPOSITORY"
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0

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
      "#(.number) (.url) (.headRefName) (.headRefOid)"
    ' 2>/dev/null || true
)"

body="$(cat <<EOF
<!-- oc-checkpoint-run-id:$run_id issue:$target -->
## /oc execution checkpoint

The autonomous agent reached its controlled long-running execution budget (${OPENCODE_AGENT_TIMEOUT_MINUTES:-350}) without claiming task completion.

This is a recoverable timeout, not a success claim.

Resume with /oc continue. For a completed run with failed CI jobs, use /oc retry failed jobs instead; timed-out work should resume from this checkpoint rather than blindly rerun.

Execution:
- workflow run: $run_url
- runner branch: $branch
- runner HEAD: $sha
- last commit: $last_commit

Working tree at timeout:
${status:-clean}

Agent-created Open PRs still visible for this target:
${open_prs:-none visible}

On resume, inspect the previous /oc request, this checkpoint, current repository state, existing branches/PRs, CI logs, and issue comments. Preserve existing partial work and evidence; do not create duplicate work solely because the previous process timed out.
EOF
)"

gh issue comment "$target" --body "$body"
