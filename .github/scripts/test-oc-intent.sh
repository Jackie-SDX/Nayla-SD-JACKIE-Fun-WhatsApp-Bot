#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export GITHUB_OUTPUT="$tmp/out"
export GITHUB_ENV="$tmp/env"
run_case(){
  local body="$1" mode="$2" pub="$3" resume="$4"
  : > "$GITHUB_OUTPUT"; : > "$GITHUB_ENV"
  jq -n --arg body "$body" '{comment:{body:$body}}' > "$tmp/event.json"
  GITHUB_EVENT_PATH="$tmp/event.json" bash .github/scripts/select-oc-task-mode.sh >/dev/null
  grep -Fq "OC_TASK_MODE=$mode" "$GITHUB_OUTPUT"
  grep -Fq "OC_PUBLISH_REQUESTED=$pub" "$GITHUB_OUTPUT"
  grep -Fq "OC_RESUME_REQUESTED=$resume" "$GITHUB_OUTPUT"
}
run_case '/oc hello' report false false
run_case '/oc explain the architecture' report false false
run_case '/oc inspect why this fails' report false false
run_case '/oc fix the parser' code false false
run_case '/oc create a pull request for this' code true false
run_case '/oc continue' code false true
run_case '/oc continue fix the parser' code false true
run_case '/oc merge PR #123' merge false false
echo 'intent classification contract: OK'
