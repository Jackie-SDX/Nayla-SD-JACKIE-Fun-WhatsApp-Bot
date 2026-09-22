#!/usr/bin/env bash
set -u
# Verifier/recovery utilities are retained for audit and manual forensic use only.
# verify-agent-result.sh and recover-verify-failure.sh MUST NEVER control route selection,
# agent_outcome, publication success, or fallback decisions. EXPECTED_TARGET_HEAD remains
# an audit concept only; the agent result is authoritative for this attempt.
# One consolidated run unit for a single /oc route attempt (audit item 5).
#
# Executed as the only step of the oc-attempt composite action. It owns the
# full attempt lifecycle that previously lived as copy-pasted step chains in
# opencode.yml: copilot branch preparation, the agent run, publication
# (copilot/local or remote-target/opencode), independent verification with one
# bounded exact-head CI recovery rerun (audit item 2), provider-failure
# classification, and lost-openCode-model memory recording.
#
# Every sub-script writes into the same GITHUB_OUTPUT/GITHUB_ENV so the two
# step-owned files remain a single coherent ledger; later writers win on
# duplicate keys (GitHub last-wins semantics).
#
# Env (provided by the composite action inputs + inherited job env):
#   ATTEMPT, PROVIDER, OC_SELECTED_MODEL, OC_TARGET_MODE, TARGET_NUMBER,
#   BASE_REF, INITIAL_SHA, OC_CI_VERIFY_WAIT_MINUTES, OC_CI_VERIFY_POLL_SECONDS

attempt="${ATTEMPT:-unknown}"
provider="${PROVIDER:-none}"
model="${OC_SELECTED_MODEL:-}"
variant="${OC_SELECTED_VARIANT:-}"
mode="${OC_TARGET_MODE:-local}"
task_mode="${TASK_MODE:-code}"
target_number="${TARGET_NUMBER:-0}"
base_ref="${BASE_REF:-}"
initial_sha="${INITIAL_SHA:-}"

output_file="${GITHUB_OUTPUT:-/dev/null}"
out() { printf '%s=%s\n' "$1" "$2" >> "$output_file"; }

attempt_start="$(date +%s)"
out attempt_elapsed_seconds 0

read_back_output() {
  local key="$1"
  local val=""
  if [[ -f "$output_file" ]]; then
    val="$(sed -nE "s/^${key}=//p" "$output_file" | tail -n 1)"
  fi
  printf '%s' "$val"
}

run_agent() {
  case "$provider" in
    opencode|openrouter)
      MODEL="$model" VARIANT="$variant" SHARE="false" AGENT="build" \
        bash .github/scripts/run-opencode-attempt.sh "$attempt" ;;
    github-copilot)
      bash .github/scripts/run-copilot-attempt.sh "$attempt" ;;
    *)
      echo "::error title=No agent provider::provider='$provider' is not routable for attempt $attempt." >&2
      return 2 ;;
  esac
}

# The Copilot publication lane is local-only: a remote target is always owned
# by controller publication/verification logic, and run-copilot-attempt.sh
# would mutate the controller checkout instead of the target workspace.
if [[ "$provider" == "github-copilot" && "$mode" == "remote" ]]; then
  echo "::error title=Copilot lane is local-only::github-copilot is not supported for remote /oc targets." >&2
  out agent_outcome failure
  out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
  exit 3
fi

if [[ "$provider" == "github-copilot" && "$mode" == "local" ]]; then
  branch="oc/copilot-$target_number-$GITHUB_RUN_ID-$attempt"
  git switch -c "$branch" || {
    echo "::error title=Copilot branch prep failed::Could not create branch $branch." >&2
    out agent_outcome failure
    out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
    exit 1
  }
fi

agent_rc=99
if [[ "$provider" != "none" ]]; then
  set +e
  run_agent
  agent_rc=$?
  set -e
else
  out agent_outcome none
  out publish_outcome "not-applicable"
  out classify_outcome "not-applicable"
  out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
  exit 0
fi

safe_log_path="$(read_back_output safe_log_path)"
copilot_peer_result="$(read_back_output copilot_peer_result)"
copilot_peer_elapsed_seconds="$(read_back_output copilot_peer_elapsed_seconds)"
copilot_peer_rounds_used="$(read_back_output copilot_peer_rounds_used)"
copilot_peer_log_path="$(read_back_output copilot_peer_log_path)"
termination_reason="$(read_back_output termination_reason)"
provider_failure_kind="$(read_back_output provider_failure_kind)"
provider_warning="$(read_back_output provider_warning)"
[ -n "$provider_warning" ] || provider_warning="false"

agent_outcome="failure"
result_state="agent-failed"

# A provider-unavailable result after an OpenCode PR was already published is
# not permission to discard that durable work and launch the whole task again.
# Preserve the published branch and let exact-head CI verification/recovery
# decide whether more work is needed.
if [ "$agent_rc" -ne 0 ] &&
   [ "$termination_reason" = "provider-unavailable" ] &&
   [ "$provider" = "opencode" ] &&
   [ "$mode" = "local" ] &&
   [[ "$target_number" =~ ^[0-9]+$ ]] &&
   [ "$target_number" != "0" ]; then
  run_since="$(printenv OC_RUN_START_ISO 2>/dev/null || printf '%s' '')"
  repo="$(printenv GITHUB_REPOSITORY 2>/dev/null || printf '%s' '')"
  pr_candidates="$(gh pr list --repo "$repo" --base "$base_ref" --state open --limit 100 --json number,url,headRefName,headRefOid,createdAt 2>/dev/null || printf '%s' '[]')"
  prefix="opencode/issue$target_number-"
  published_pr="$(jq -c --arg prefix "$prefix" --arg initial "$initial_sha" --arg since "$run_since" '
    [ .[] |
      select((.headRefName|startswith($prefix))) |
      select((.headRefOid // "") != $initial) |
      select(($since == "") or ((.createdAt // "") >= $since))
    ] | sort_by(.createdAt) | last // {}
  ' <<<"$pr_candidates" 2>/dev/null || printf '%s' '{}')"
  published_number="$(jq -r '.number // 0' <<<"$published_pr" 2>/dev/null || printf '0')"
  if [[ "$published_number" =~ ^[1-9][0-9]*$ ]]; then
    agent_rc=0
    agent_outcome="success"
    result_state="published-after-provider-warning"
    provider_warning="true"
    pr_url="$(jq -r '.url // empty' <<<"$published_pr" 2>/dev/null || true)"
    [ -n "$pr_url" ] && out pr_url "$pr_url"
    echo "::warning title=Provider warning after publication::Attempt $attempt already published PR #$published_number; preserving that result and skipping fresh fallback."
  fi
fi

if [ "$agent_rc" -eq 0 ] && [ "$agent_outcome" != "success" ]; then
  agent_outcome="success"
  [ "$result_state" = "agent-failed" ] && result_state="completed"
fi
out agent_outcome "$agent_outcome"
out provider_warning "$provider_warning"
out result_state "$result_state"
[[ -n "$safe_log_path" ]] && out safe_log_path "$safe_log_path"
[[ -n "$copilot_peer_result" ]] && out copilot_peer_result "$copilot_peer_result"
[[ -n "$copilot_peer_elapsed_seconds" ]] && out copilot_peer_elapsed_seconds "$copilot_peer_elapsed_seconds"
[[ -n "$copilot_peer_rounds_used" ]] && out copilot_peer_rounds_used "$copilot_peer_rounds_used"
[[ -n "$copilot_peer_log_path" ]] && out copilot_peer_log_path "$copilot_peer_log_path"
agent_branch="$(read_back_output agent_branch)"
[[ -n "$agent_branch" ]] && out agent_branch "$agent_branch"
[[ -n "$termination_reason" ]] && out termination_reason "$termination_reason"

# Publication runs only after a successful agent. Local OpenCode publications
# are self-owned by the `opencode github run` flow, so only copilot (local) and
# remote-target opencode reach these scripts.
publish_outcome="not-applicable"
if [[ "$agent_rc" -eq 0 ]]; then
  publish_rc=0
  if [[ "$task_mode" == "report" ]] && [[ "$provider" == "opencode" ]]; then
    publish_outcome="report-only"
  elif [[ "$provider" == "github-copilot" ]] && [[ "$mode" == "local" ]]; then
    set +e
    bash .github/scripts/publish-copilot-change.sh
    publish_rc=$?
    set -e
  elif [[ "$provider" == "opencode" ]] && [[ "$mode" == "remote" ]]; then
    set +e
    bash .github/scripts/publish-remote-opencode.sh
    publish_rc=$?
    set -e
  fi
  if [[ "$publish_rc" -eq 0 ]]; then
    publish_outcome="published"
  else
    publish_outcome="failed"
  fi
  out publish_outcome "$publish_outcome"
  if [[ "$publish_rc" -ne 0 ]]; then
    echo "::error title=Publication failed for attempt ${attempt}::The $provider publication did not complete; the run cannot be verified and stops here." >&2
    out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
    exit 1
  fi
fi

out verified "false"
out verification_outcome "not-run-advisory"
out ci_surfaces "unobserved"

classify_outcome="not-applicable"
classify_rc=""
if [[ "$agent_rc" -ne 0 ]] && [[ "$provider" != "none" ]] &&
   [[ "$termination_reason" != "timeout" && "$termination_reason" != "signal" ]] &&
   [[ -n "$safe_log_path" ]]; then
  set +e
  CURRENT_PROVIDER="$provider" SAFE_LOG="$safe_log_path" bash .github/scripts/classify-provider-failure.sh
  classify_rc=$?
  set -e
fi
if [[ -n "$classify_rc" ]]; then
  if [[ "$classify_rc" -eq 0 ]]; then
    classify_outcome="success"
  else
    classify_outcome="failure"
  fi
fi
out classify_outcome "$classify_outcome"

# Lost-openCode-model memory (audit item 6): remember a model that failed for
# model-specific reasons so later runs skip it; timeout/signal terminations are
# budget events, not model defects, and must never poison the ladder.
if [[ "$agent_rc" -ne 0 ]] && [[ "$provider" == "opencode" ]] && [[ -n "$model" ]] &&
   [[ "$termination_reason" != "timeout" && "$termination_reason" != "signal" && "$termination_reason" != "provider-unavailable" ]]; then
  set +e
  CURRENT_PROVIDER="$provider" MODEL="$model" AGENT_OUTCOME="failure" TERMINATION_REASON="$termination_reason" \
    bash .github/scripts/record-model-memory.sh
  set -e
fi

out provider_warning "$provider_warning"
out result_state "$result_state"
out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
exit 0