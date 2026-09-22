#!/usr/bin/env bash
set -u

runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || printf /tmp)"
log_file="$(printenv OC_COPILOT_HOOK_LOG 2>/dev/null || true)"
[ -n "$log_file" ] || log_file="$runner_temp/copilot-hooks.log"
mkdir -p "$(dirname "$log_file")"
payload="$(cat 2>/dev/null || true)"

event="$(jq -r '.hook_event_name // .event // "hook"' <<<"$payload" 2>/dev/null || printf hook)"
tool="$(jq -r '.toolName // .tool_name // "unknown"' <<<"$payload" 2>/dev/null || printf unknown)"
arg_hint="$(jq -r '.toolArgs // .tool_input // {} | if type=="object" then (.filePath // .path // .command // .query // .url // .text // "") else "" end' <<<"$payload" 2>/dev/null || true)"
result_type="$(jq -r '.toolResult.resultType // .tool_result.result_type // ""' <<<"$payload" 2>/dev/null || true)"
error="$(jq -r '.error // ""' <<<"$payload" 2>/dev/null || true)"

safe() {
  printf '%s' "$1" |
    sed -E \
      -e 's/(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-or-v1-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,})/[REDACTED]/g' \
      -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' |
    tr '\r\n' '  ' |
    cut -c1-260
}

if [ "$event" = "PostToolUseFailure" ] || [ "$event" = "postToolUseFailure" ]; then
  printf '[COPILOT][hook] tool=%s failed: %s\n' "$(safe "$tool")" "$(safe "$error")" >> "$log_file"
else
  printf '[COPILOT][hook] tool=%s result=%s %s\n' "$(safe "$tool")" "$result_type" "$(safe "$arg_hint")" >> "$log_file"
fi
exit 0
