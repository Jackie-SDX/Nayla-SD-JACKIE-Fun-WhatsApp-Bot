#!/usr/bin/env bash
set -euo pipefail
# Regression: oc-command-control.sh must decide from the classification written
# to $GITHUB_OUTPUT in the SAME step (select-oc-task-mode.sh only publishes to
# files, not the current shell), so prepare-oc-session.sh actually runs and the
# durable session branch is published for later steps.
tmp="$(mktemp -d)"
cat > "$tmp/event.json" <<'JSON'
{"comment":{"body":"/oc implement a durable-session regression fix"}}
JSON
head_sha="$(git rev-parse HEAD)"
# Hermetic git state: pre-create the durable branch locally so
# prepare-oc-session.sh uses it instead of branching from origin/main.
git branch oc/session-42 "$head_sha" 2>/dev/null || true
trap '
  git branch -D oc/session-42 >/dev/null 2>&1 || true
  rm -rf "$tmp"
' EXIT

GITHUB_EVENT_PATH="$tmp/event.json" \
GITHUB_REPOSITORY=example/repo \
GITHUB_OUTPUT="$tmp/out" \
GITHUB_ENV="$tmp/env" \
RUNNER_TEMP="$tmp" \
TARGET_NUMBER=42 \
OC_SESSION_STATE_FILE="$tmp/state.json" \
bash .github/scripts/oc-command-control.sh >/dev/null

grep -Fq 'OC_TASK_MODE=code' "$tmp/env"
grep -Fq 'OC_SESSION_REQUIRED=true' "$tmp/env"
if ! grep -Eq '^OC_SESSION_BRANCH=[^[:space:]]+$' "$tmp/env"; then
  echo "oc-command-control.sh did not publish OC_SESSION_BRANCH (prepare-oc-session.sh skipped)." >&2
  exit 1
fi
session_branch="$(sed -nE 's/^OC_SESSION_BRANCH=//p' "$tmp/env" | tail -n 1)"
[[ "$session_branch" == "oc/session-42" ]]
grep -Fq 'oc/session-42' "$tmp/state.json"
grep -Fq '"phase"' "$tmp/state.json"
echo "oc-command-control.sh same-step durable-session bootstrap: OK ($session_branch)"