#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GITHUB_OUTPUT="$tmp/out"
export GITHUB_ENV="$tmp/env"
# The agent session inherits the controller's exported OC_* contract; the
# classification under test must come from the script, not from the parent env.
while IFS='=' read -r leaked _; do
  case "$leaked" in OC_*|SESSION_*) unset "$leaked" 2>/dev/null || true ;; esac
done < <(env)
run_case(){
  local body="$1" mode="$2" pub="$3" resume="$4"
  : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
  jq -n --arg body "$body" '{comment:{body:$body}}' > "$tmp/event.json"
  GITHUB_EVENT_PATH="$tmp/event.json" bash .github/scripts/select-oc-task-mode.sh >/dev/null
  grep -Fq "OC_TASK_MODE=$mode" "$GITHUB_OUTPUT"
  grep -Fq "OC_PUBLISH_REQUESTED=$pub" "$GITHUB_OUTPUT"
  grep -Fq "OC_RESUME_REQUESTED=$resume" "$GITHUB_OUTPUT"
  # There is no report/content downgrade path anymore: every non-merge request
  # launches the agent with the full task environment.
  if grep -Fq 'OC_CONTENT_TASK' "$GITHUB_OUTPUT" "$GITHUB_ENV"; then
    echo "FAIL: content/report classification is still emitted for: $body" >&2
    exit 1
  fi
}
run_case '/oc hello' code false false
run_case '/oc explain the architecture' code false false
run_case '/oc inspect why this fails' code false false
run_case $'/oc hi\nDo not inspect, modify, commit, push, or run repository tests; this is a startup/lazy-tooling smoke test.' code false false
run_case '/oc fix the parser' code false false
run_case '/oc create a pull request for this' code true false
run_case '/oc continue' code true true
run_case '/oc continue fix the parser' code true true
run_case '/oc merge PR #123' merge false false

# Regression: a capability-heavy non-repository request must not be downgraded
# into a capability-starved report/content path. It launches the agent in code
# mode, which is the only mode the workflow provisions the Composio bootstrap
# and the full task environment for (opencode.yml gates those on != merge only).
: > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
jq -n --arg body '/oc send an email to snapdragon0313@gmail.com telling him the workflow is fixed' '{comment:{body:$body}}' > "$tmp/event-email.json"
GITHUB_EVENT_PATH="$tmp/event-email.json" bash .github/scripts/select-oc-task-mode.sh >/dev/null
grep -Fq 'OC_TASK_MODE=code' "$GITHUB_OUTPUT"
grep -Fq 'OC_SESSION_REQUIRED=false' "$GITHUB_OUTPUT"
if grep -Fq 'OC_TASK_MODE=report' "$GITHUB_OUTPUT" "$GITHUB_ENV"; then
  echo 'FAIL: "send an email" was downgraded to a report path' >&2
  exit 1
fi
if grep -Fq 'OC_CONTENT_TASK=true' "$GITHUB_OUTPUT" "$GITHUB_ENV"; then
  echo 'FAIL: "send an email" was classified as a content task' >&2
  exit 1
fi
grep -Fq 'Bootstrap Composio session MCP (all non-merge tasks)' .github/workflows/opencode.yml
grep -Fq 'COMPOSIO_API_KEY: ${{ secrets.COMPOSIO_API_KEY }}' .github/workflows/opencode.yml
if grep -Fq "if: env.OC_TASK_MODE == 'report'" .github/workflows/opencode.yml; then
  echo 'FAIL: workflow still selects a report path that can starve capability provisioning' >&2
  exit 1
fi
echo 'intent classification contract: OK'
