#!/usr/bin/env bash
set -euo pipefail

target="${TARGET_NUMBER:-0}"
base_ref="${BASE_REF:-main}"
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0

branch="$(git branch --show-current 2>/dev/null || printf '%s' 'unknown')"
sha="$(git rev-parse HEAD 2>/dev/null || printf '%s' 'unknown')"
status="$(git status --short 2>/dev/null || true)"
last_commit="$(git log -1 --oneline 2>/dev/null || printf '%s' 'unknown')"
open_prs="$(gh pr list --head "$branch" --base "$base_ref" --state open --limit 20 --json number,url 2>/dev/null | jq -r '.[] | "#\(.number) \(.url)"' 2>/dev/null || true)"

body="$(cat <<EOF
## /oc execution checkpoint

The autonomous agent reached its controlled long-running execution budget (${OPENCODE_AGENT_TIMEOUT_MINUTES:-350} minutes) without claiming task completion.

This is a recoverable timeout, not a success claim.

**Resume:** comment `/oc continue` on this issue/PR.
**Retry failed CI:** comment `/oc retry failed jobs` after the relevant failure has been inspected.

**Checkpoint**
- runner branch: `$branch`
- runner HEAD: `$sha`
- last commit: `$last_commit`

Working tree at timeout:
```text
${status:-clean}
```

Open PRs for the runner branch:
${open_prs:-none visible}

On resume, inspect the previous `/oc` request, current repository state, existing branches/PRs, and CI. Continue from durable checkpoints; do not blindly restart or duplicate work.
EOF
)"

gh issue comment "$target" --body "$body"