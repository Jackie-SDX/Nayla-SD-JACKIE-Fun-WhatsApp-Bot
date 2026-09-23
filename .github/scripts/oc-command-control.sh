#!/usr/bin/env bash
set -euo pipefail

# Single command-control entrypoint: classify the request, load issue-scoped
# session state, prepare durable code sessions, and handle explicit merge.
bash .github/scripts/select-oc-task-mode.sh
bash .github/scripts/oc-session-state.sh load

# select-oc-task-mode.sh publishes classification to the GITHUB_OUTPUT/GITHUB_ENV
# files, which the runner only applies to the NEXT step. Read the values back
# from the output file so the same-step decision below can use them.
read_back_output() {
  local key="$1" val=""
  if [[ -n "${GITHUB_OUTPUT:-}" && -f "$GITHUB_OUTPUT" ]]; then
    val="$(sed -nE "s/^${key}=//p" "$GITHUB_OUTPUT" | tail -n 1)"
  else
    val="$(printenv "$key" 2>/dev/null || true)"
  fi
  printf '%s' "$val"
}

session_required="$(read_back_output OC_SESSION_REQUIRED)"
task_mode="$(read_back_output OC_TASK_MODE)"
merge_requested="$(read_back_output OC_MERGE_REQUESTED)"

if [[ "${session_required:-false}" == "true" && "${task_mode:-report}" == "code" ]]; then
  TARGET_NUMBER="${TARGET_NUMBER:-0}" BASE_REF="${BASE_REF:-main}" bash .github/scripts/prepare-oc-session.sh
  OC_SESSION_PHASE=ready OC_SESSION_STATUS=active OC_SESSION_NEXT_ACTION="inspect durable session and continue" OC_DURABLE_WORK=false bash .github/scripts/record-oc-session-progress.sh || true
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
