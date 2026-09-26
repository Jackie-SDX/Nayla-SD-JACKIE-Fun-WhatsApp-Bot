#!/usr/bin/env bash
set -u

attempt="${ATTEMPT:-1}"
model="${MODEL:-opencode/mimo-v2.6-flash-free}"
mode="${OC_TARGET_MODE:-local}"
task_mode="${TASK_MODE:-code}"
publish_requested="${OC_PUBLISH_REQUESTED:-${PUBLISH_REQUESTED:-false}}"
initial_sha="${INITIAL_SHA:-}"
output_file="${GITHUB_OUTPUT:-/dev/null}"
start_epoch="$(date +%s)"

out() { printf '%s=%s\n' "$1" "$2" >> "$output_file"; }
read_back() { sed -nE "s/^${1}=//p" "$output_file" 2>/dev/null | tail -n 1; }

set +e
MODEL="$model" VARIANT="" SHARE="false" AGENT="build" bash .github/scripts/run-opencode-attempt.sh "$attempt"
agent_rc=$?
set -e

agent_outcome="failure"
[[ "$agent_rc" -eq 0 ]] && agent_outcome="success"
termination_reason="$(read_back termination_reason)"
[[ -n "$termination_reason" ]] || termination_reason="failed"
timed_out="false"
[[ "$termination_reason" == "timeout" ]] && timed_out="true"
safe_log_path="$(read_back safe_log_path)"
agent_branch="$(read_back agent_branch)"
session_head_sha=""
durable_work="false"

if [[ -n "$agent_branch" ]]; then
  session_head_sha="$(git rev-parse "$agent_branch" 2>/dev/null || true)"
  if [[ "$initial_sha" =~ ^[0-9a-f]{40}$ && "$session_head_sha" =~ ^[0-9a-f]{40}$ && "$session_head_sha" != "$initial_sha" ]]; then
    durable_work="true"
  fi
fi

publish_outcome="not-requested"
pr_url="$(read_back pr_url)"
publish_rc=0
if [[ "$task_mode" == "report" ]]; then
  publish_outcome="report-only"
elif [[ "$publish_requested" == "true" && ( "$agent_outcome" == "success" || "$durable_work" == "true" ) ]]; then
  set +e
  if [[ "$mode" == "remote" ]]; then
    PUBLISH_REQUESTED="true" bash .github/scripts/publish-remote-opencode.sh
  else
    OC_SESSION_BRANCH="$agent_branch" PUBLISH_REQUESTED="true" bash .github/scripts/publish-oc-session.sh
  fi
  publish_rc=$?
  set -e
  pr_url="$(read_back pr_url)"
  if [[ "$publish_rc" -eq 0 ]]; then publish_outcome="published"; else publish_outcome="failed"; fi
elif [[ "$durable_work" == "true" ]]; then
  publish_outcome="checkpointed"
fi

result_state="failed"
[[ "$agent_outcome" == "success" ]] && result_state="completed"
[[ "$durable_work" == "true" && "$agent_outcome" != "success" ]] && result_state="checkpointed"
[[ "$publish_rc" -ne 0 ]] && result_state="publication-failed"

out agent_outcome "$agent_outcome"
out termination_reason "$termination_reason"
out timed_out "$timed_out"
out safe_log_path "$safe_log_path"
out durable_work "$durable_work"
out session_head_sha "$session_head_sha"
out publish_outcome "$publish_outcome"
out pr_url "$pr_url"
out verified "false"
out verified_sha ""
out ci_surfaces "unobserved"
out ci_run_id ""
out result_state "$result_state"
out attempt_elapsed_seconds "$(( $(date +%s) - start_epoch ))"
exit 0
