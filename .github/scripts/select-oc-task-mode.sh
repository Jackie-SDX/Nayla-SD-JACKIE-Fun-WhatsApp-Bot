#!/usr/bin/env bash
set -euo pipefail
body="$(jq -r '.comment.body // empty' "${GITHUB_EVENT_PATH:-/dev/null}" 2>/dev/null || true)"
request="$(printf '%s' "$body" | sed -E 's#^/(oc|opencode)[[:space:]]*##')"
lower="$(printf '%s' "$request" | tr '[:upper:]' '[:lower:]')"
runner_temp="${RUNNER_TEMP:-/tmp}"
request_file="$runner_temp/oc-request.txt"
printf '%s\n' "$request" > "$request_file"

mode=report
intent=answer
resume_requested=false
publish_requested=false
merge_requested=false
session_required=false
content_task=false

if [[ "$lower" =~ ^continue([[:space:]]|$) ]] &&
   ! printf '%s' "$lower" | grep -Eiq '\b(story|stories|chapter|fiction|poem|poetry|essay|prose|dialogue|joke|caption|lyrics?|creative|co-?author|part[[:space:]-]*[0-9]+)\b'; then
  resume_requested=true; session_required=true; mode=code; intent=continue; publish_requested=true
  request="$(printf '%s' "$request" | sed -E 's#^continue[[:space:]]*##')"
  printf '%s\n' "$request" > "$request_file"
elif [[ "$lower" =~ ^merge([[:space:]]|$) ]]; then
  merge_requested=true; session_required=true; mode=merge; intent=merge
else
  if printf '%s' "$lower" | grep -Eiq '\b(create|open|publish|submit)[[:space:]]+(a[[:space:]]+)?(pull[[:space:]-]*request|pr)\b'; then
    publish_requested=true
  fi
  positive_request="$(printf '%s' "$lower" | sed -E 's/\b(do not|dont|don'\''t|without)\b[^.!?;]*[.!?;]?//g')"
  content_signal=false
  repo_signal=false
  if printf '%s' "$positive_request" | grep -Eiq '\b(story|stories|chapter|fiction|poem|poetry|essay|prose|dialogue|joke|caption|lyrics?|sentences?|email|message|response|answer|creative|co-?author|part[[:space:]-]*[0-9]+)\b'; then
    content_signal=true
  fi
  if printf '%s' "$positive_request" | grep -Eiq '\b(code|repository|repo|workflow|branch|commit|pull request|github|file|script|test|ci|build|deploy|patch|refactor|dependency|package|merge|release|bug)\b'; then
    repo_signal=true
  fi
  if [[ "$content_signal" == true && "$repo_signal" == false ]]; then
    content_task=true
    mode=report
    intent=answer
    session_required=false
 elif printf '%s' "$lower" | grep -Eiq '\b(fix|edit|change|modify|implement|add|remove|create|delete|refactor|debug|repair|update|build|write|test|patch|migrate|replace|rename)\b'; then
    mode=code; intent=code; session_required=true; publish_requested=true
  elif [[ "$publish_requested" == true ]]; then
    mode=code; intent=publish; session_required=true
  else
    mode=report; intent=answer
  fi
fi
emit_value() {
  local key="$1" value="$2" file="$3" delim
  if [[ "$value" == *$'\n'* ]]; then
    delim="EOF_${key}_${RANDOM}_${RANDOM}"
    while printf '%s' "$value" | grep -Fq "$delim"; do
      delim="EOF_${key}_${RANDOM}_${RANDOM}"
    done
    printf '%s<<%s\n%s\n%s\n' "$key" "$delim" "$value" "$delim" >> "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}
emit_env(){ emit_value "$1" "$2" "${GITHUB_ENV:-/dev/null}"; emit_value "$1" "$2" "${GITHUB_OUTPUT:-/dev/null}"; }
emit_out(){ emit_value "$1" "$2" "${GITHUB_OUTPUT:-/dev/null}"; }
emit_env OC_COMMAND_TEXT "$request"
emit_out mode "$mode"
emit_out intent "$intent"
emit_env OC_REQUEST_FILE "$request_file"
emit_env OC_TASK_MODE "$mode"
emit_env OC_INTENT "$intent"
emit_env OC_RESUME_REQUESTED "$resume_requested"
emit_env OC_PUBLISH_REQUESTED "$publish_requested"
emit_env OC_MERGE_REQUESTED "$merge_requested"
emit_env OC_SESSION_REQUIRED "$session_required"
emit_env OC_CONTENT_TASK "$content_task"
echo "Selected /oc intent=$intent mode=$mode content=$content_task resume=$resume_requested publish=$publish_requested merge=$merge_requested"
