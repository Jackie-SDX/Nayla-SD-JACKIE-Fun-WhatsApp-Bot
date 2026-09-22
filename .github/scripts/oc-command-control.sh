#!/usr/bin/env bash
set -euo pipefail

# Single command-control entrypoint: classify the request, load issue-scoped
# session state, prepare durable code sessions, and handle explicit merge.
bash .github/scripts/select-oc-task-mode.sh
bash .github/scripts/oc-session-state.sh load

if [[ "${OC_SESSION_REQUIRED:-false}" == "true" && "${OC_TASK_MODE:-report}" == "code" ]]; then
  TARGET_NUMBER="${TARGET_NUMBER:-0}" BASE_REF="${BASE_REF:-main}" bash .github/scripts/prepare-oc-session.sh
  OC_SESSION_PHASE=ready OC_SESSION_STATUS=active OC_SESSION_NEXT_ACTION="inspect durable session and continue" OC_DURABLE_WORK=false bash .github/scripts/record-oc-session-progress.sh || true
fi

if [[ "${OC_MERGE_REQUESTED:-false}" == "true" ]]; then
  set +e
  bash .github/scripts/merge-oc-request.sh
  rc=$?
  set -e
  echo "OC_MERGE_EXIT=$rc" >> "${GITHUB_ENV:-/dev/null}"
  if [[ "$rc" -eq 0 ]]; then
    OC_SESSION_PHASE=merged OC_SESSION_STATUS=complete OC_SESSION_NEXT_ACTION="await user direction" OC_DURABLE_WORK=true bash .github/scripts/record-oc-session-progress.sh || true
  fi
fi
