#!/usr/bin/env bash
set -u
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
    opencode)
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
termination_reason="$(read_back_output termination_reason)"

if [[ "$agent_rc" -eq 0 ]]; then
  agent_outcome="success"
else
  agent_outcome="failure"
fi
out agent_outcome "$agent_outcome"
[[ -n "$safe_log_path" ]] && out safe_log_path "$safe_log_path"
[[ -n "$termination_reason" ]] && out termination_reason "$termination_reason"

# Publication runs only after a successful agent. Local opencode publications
# are self-owned by the `opencode github run` flow, so only copilot (local) and
# remote-target opencode reach these scripts.
publish_outcome="not-applicable"
if [[ "$agent_rc" -eq 0 ]]; then
  publish_rc=0
  if [[ "$provider" == "github-copilot" ]] && [[ "$mode" == "local" ]]; then
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

expected_head=""
if [[ "$mode" == "remote" ]]; then
  expected_head="$(read_back_output head_sha)"
fi

verify_run() {
  EXPECTED_TARGET_HEAD="$expected_head" \
    PROVIDER="$provider" \
    ATTEMPT="$attempt" \
    TARGET_NUMBER="$target_number" \
    BASE_REF="$base_ref" \
    INITIAL_SHA="$initial_sha" \
    bash .github/scripts/verify-agent-result.sh
}

if [[ "$agent_rc" -eq 0 ]]; then
  verify_rc=1
  set +e
  verify_run
  verify_rc=$?
  set -e
  if [[ "$verify_rc" -ne 0 ]]; then
    ci_run_id="$(read_back_output ci_run_id)"
    recoveries_done="${OC_VERIFY_RECOVERIES:-0}"
    max_recoveries="${OC_VERIFY_MAX_RECOVERIES:-1}"
    if [[ "$ci_run_id" =~ ^[0-9]+$ ]] && [[ "$recoveries_done" =~ ^[0-9]+$ ]] && (( recoveries_done < max_recoveries )); then
      echo "::warning title=CI recovery attempt for attempt ${attempt}::Verification failed with ci_run_id=$ci_run_id; requesting one exact-head CI recovery rerun."
      CI_RUN_ID="$ci_run_id" bash .github/scripts/recover-verify-failure.sh || true
      printf 'OC_VERIFY_RECOVERIES=%d\n' "$((recoveries_done + 1))" >> "${GITHUB_ENV:-/dev/null}"
      set +e
      verify_run
      verify_rc=$?
      set -e
    fi
  fi
  verified="$(read_back_output verified)"
  [[ -n "$verified" ]] || verified="false"
  out verified "$verified"
  verified_sha="$(read_back_output verified_sha)"
  [[ -n "$verified_sha" ]] && out verified_sha "$verified_sha"
  ci_surfaces="$(read_back_output ci_surfaces)"
  [[ -n "$ci_surfaces" ]] && out ci_surfaces "$ci_surfaces"
fi

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
   [[ "$termination_reason" != "timeout" && "$termination_reason" != "signal" ]]; then
  set +e
  CURRENT_PROVIDER="$provider" MODEL="$model" AGENT_OUTCOME="failure" TERMINATION_REASON="$termination_reason" \
    bash .github/scripts/record-model-memory.sh
  set -e
fi

out attempt_elapsed_seconds "$(( $(date +%s) - attempt_start ))"
exit 0