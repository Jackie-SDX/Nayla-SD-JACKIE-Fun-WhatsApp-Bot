#!/usr/bin/env bash
set -euo pipefail
repo="$(printenv GITHUB_REPOSITORY || true)"
target="$(printenv TARGET_NUMBER || printf 0)"
state_file="${OC_SESSION_STATE_FILE:-${RUNNER_TEMP:-/tmp}/oc-session-state.json}"
wait_minutes="${OC_MERGE_WAIT_MINUTES:-30}"
[[ "$target" =~ ^[0-9]+$ && "$target" != 0 && -n "$repo" ]] || exit 0

emit_out(){ printf '%s=%s\n' "$1" "$2" >> "${GITHUB_OUTPUT:-/dev/null}"; }
pr_number="${PR_NUMBER:-0}"
if [[ ! "$pr_number" =~ ^[1-9][0-9]*$ ]]; then
  pr_number="$(jq -r '.active_pr_number // 0' "$state_file" 2>/dev/null || printf 0)"
fi
request="$(jq -r '.comment.body // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null || true)"
explicit="$(printf '%s' "$request" | sed -E 's#^/(oc|opencode)[[:space:]]*##' | grep -Eo '#[0-9]+' | head -n 1 | tr -d '#' || true)"
[[ "$explicit" =~ ^[1-9][0-9]*$ ]] && pr_number="$explicit"

if [[ ! "$pr_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error title=Merge requested but no PR is known::Use /oc merge PR #123 or publish the current task first." >&2
  emit_out merged false
  exit 1
fi

deadline=$(( $(date +%s) + wait_minutes*60 ))
last_head=""
while (( $(date +%s) < deadline )); do
  meta="$(gh pr view "$pr_number" --repo "$repo" --json state,headRefOid,baseRefName,url,statusCheckRollup 2>/dev/null || true)"
  state="$(jq -r '.state // ""' <<<"$meta")"
  head="$(jq -r '.headRefOid // ""' <<<"$meta")"
  url="$(jq -r '.url // ""' <<<"$meta")"
  if [[ "$state" != OPEN ]]; then
    echo "PR #$pr_number is not open (state=$state)."
    emit_out merged false; emit_out pr_number "$pr_number"; emit_out pr_url "$url"; exit 0
  fi
  if [[ "$head" != "$last_head" ]]; then echo "[merge] PR #$pr_number head=$head"; last_head="$head"; fi
  states="$(jq -r '[.statusCheckRollup[]? | (.state // .status // .conclusion // empty)] | map(select(. != "")) | join(",")' <<<"$meta" 2>/dev/null || true)"
  if [[ -z "$states" ]]; then break; fi
  if [[ "$states" =~ (FAILURE|ERROR|CANCELLED|TIMED_OUT) ]]; then
    echo "::error title=Merge blocked by CI::PR #$pr_number has failing checks: $states" >&2
    emit_out merged false; emit_out pr_number "$pr_number"; emit_out pr_url "$url"; exit 1
  fi
  if [[ ! "$states" =~ (PENDING|IN_PROGRESS|QUEUED|EXPECTED) ]]; then break; fi
  sleep 20
done

meta="$(gh pr view "$pr_number" --repo "$repo" --json state,headRefOid,baseRefName,url,statusCheckRollup)"
state="$(jq -r '.state' <<<"$meta")"
head="$(jq -r '.headRefOid' <<<"$meta")"
url="$(jq -r '.url' <<<"$meta")"
[[ "$state" == OPEN && "$head" =~ ^[0-9a-f]{40}$ ]] || { echo "::error title=Merge blocked::PR state/head changed or is unavailable." >&2; emit_out merged false; exit 1; }

if gh pr merge "$pr_number" --repo "$repo" --squash --match-head-commit "$head" --delete-branch=false; then
  emit_out merged true; emit_out pr_number "$pr_number"; emit_out pr_url "$url"; emit_out head_sha "$head"
  echo "Merged PR #$pr_number with expected head $head."
else
  echo "::error title=Explicit merge failed::GitHub refused PR #$pr_number at expected head $head." >&2
  emit_out merged false; emit_out pr_number "$pr_number"; emit_out pr_url "$url"; emit_out head_sha "$head"; exit 1
fi
