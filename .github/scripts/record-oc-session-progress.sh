#!/usr/bin/env bash
set -euo pipefail

state_file="${OC_SESSION_STATE_FILE:-${RUNNER_TEMP:-/tmp}/oc-session-state.json}"
[[ -f "$state_file" ]] || exit 0

phase="${OC_SESSION_PHASE:-${SESSION_PHASE:-}}"
status="${OC_SESSION_STATUS:-${SESSION_STATUS:-active}}"
next_action="${OC_SESSION_NEXT_ACTION:-${SESSION_NEXT_ACTION:-}}"
request="${OC_COMMAND_TEXT:-${SESSION_REQUEST:-}}"
session_branch="${OC_SESSION_BRANCH:-}"
head_sha="${OC_SESSION_HEAD_SHA:-}"
pr_number="${OC_SESSION_PR_NUMBER:-0}"
pr_url="${OC_SESSION_PR_URL:-}"
comment_id="${OC_ISSUE_LAST_COMMENT_ID:-0}"
run_id="${GITHUB_RUN_ID:-}"
durable="${OC_DURABLE_WORK:-false}"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json="$(jq   --arg phase "$phase"   --arg status "$status"   --arg next "$next_action"   --arg request "$request"   --arg branch "$session_branch"   --arg head "$head_sha"   --arg pr_url "$pr_url"   --arg run "$run_id"   --arg now "$now"   --argjson pr "${pr_number:-0}"   --argjson comment "${comment_id:-0}"   --argjson durable "${durable:-false}"   '.phase = (if $phase != "" then $phase else .phase end)
   | .status = (if $status != "" then $status else .status end)
   | .next_action = (if $next != "" then $next else .next_action end)
   | .current_request = (if $request != "" then $request else .current_request end)
   | .active_branch = (if $branch != "" then $branch else .active_branch end)
   | .active_head_sha = (if $head != "" then $head else .active_head_sha end)
   | .active_pr_number = (if $pr > 0 then $pr else .active_pr_number end)
   | .active_pr_url = (if $pr_url != "" then $pr_url else .active_pr_url end)
   | .last_processed_comment_id = (if $comment > 0 then $comment else .last_processed_comment_id end)
   | .last_run_id = (if $run != "" then ($run|tonumber) else .last_run_id end)
   | .durable_work = $durable
   | .updated_at = $now
   | .last_checkpoint_at = $now
   | .state_revision = ((.state_revision // 0) + 1)' "$state_file")"

printf '%s\n' "$json" > "$state_file"
SESSION_JSON="$json" bash .github/scripts/oc-session-state.sh set || true
echo "Session checkpoint: phase=$(jq -r '.phase' "$state_file") revision=$(jq -r '.state_revision' "$state_file") durable=$(jq -r '.durable_work' "$state_file")"
