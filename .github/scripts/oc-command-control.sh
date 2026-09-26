#!/usr/bin/env bash
set -euo pipefail

# Single command-control entrypoint: select the lifecycle, load issue-scoped
# session state, prepare the durable session when the request requires it, and
# handle explicit merge. The controller is a launcher only — it never probes
# capabilities, write permissions, or credentials, and never decides which
# tools the agent may use (.opencode/instructions.md owns that contract).
bash .github/scripts/select-oc-task-mode.sh
bash .github/scripts/oc-session-state.sh load

# select-oc-task-mode.sh publishes classification to the GITHUB_OUTPUT/GITHUB_ENV
# files, which the runner only applies to the NEXT step. Read the values back
# from the output file so the same-step decision below can use them.
read_back_output() {
  local key="$1" val=""
  if [[ -n "${GITHUB_OUTPUT:-}" && -f "$GITHUB_OUTPUT" ]]; then
    val="$(sed -nE "s/^${key}=//p" "$GITHUB_OUTPUT" | tail -n 1)"
  fi
  if [[ -z "$val" && -n "${GITHUB_ENV:-}" && -f "$GITHUB_ENV" ]]; then
    val="$(sed -nE "s/^${key}=//p" "$GITHUB_ENV" | tail -n 1)"
  fi
  if [[ -z "$val" ]]; then
    val="$(printenv "$key" 2>/dev/null || true)"
  fi
  printf '%s' "$val"
}

session_required="$(read_back_output OC_SESSION_REQUIRED)"
task_mode="$(read_back_output OC_TASK_MODE)"
merge_requested="$(read_back_output OC_MERGE_REQUESTED)"
session_branch="$(read_back_output OC_SESSION_BRANCH)"

if [[ "${session_required:-false}" == "true" && "${task_mode:-}" == "code" ]]; then
  # Mechanical lifecycle only: materialize the durable session branch for this
  # repository request. No capability, permission, or credential decision is
  # made here — the attempt always runs with the full task environment.
  TARGET_NUMBER="${TARGET_NUMBER:-0}" BASE_REF="${BASE_REF:-main}" bash .github/scripts/prepare-oc-session.sh
  OC_SESSION_PHASE=ready OC_SESSION_STATUS=active OC_SESSION_NEXT_ACTION="inspect durable session and continue" OC_DURABLE_WORK=false bash .github/scripts/record-oc-session-progress.sh || true
elif [[ "${session_required:-false}" != "true" && -n "${session_branch}" ]]; then
  # Mechanical lifecycle only: an ordinary request does not enter the durable
  # session of an earlier task. Clear it for the later steps so the attempt
  # runs against the current checkout instead of a stale session branch.
  echo "Durable session ${session_branch} not required by this request; running against the current checkout."
  printf 'OC_SESSION_BRANCH=\n' >> "${GITHUB_ENV:-/dev/null}"
fi

if [[ "${merge_requested:-false}" == "true" ]]; then
  set +e
  bash .github/scripts/merge-oc-request.sh
  rc=$?
  set -e
  echo "OC_MERGE_EXIT=$rc" >> "${GITHUB_ENV:-/dev/null}"
  if [[ "$rc" -eq 0 ]]; then
    OC_SESSION_PHASE=merged OC_SESSION_STATUS=complete OC_SESSION_NEXT_ACTION="await user direction" OC_DURABLE_WORK=true bash .github/scripts/record-oc-session-progress.sh || true
  fi
fi
