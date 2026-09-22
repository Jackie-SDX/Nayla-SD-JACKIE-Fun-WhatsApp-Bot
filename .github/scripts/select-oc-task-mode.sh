#!/usr/bin/env bash
set -euo pipefail
body="$(jq -r '.comment.body // empty' "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
body="$(printf '%s' "$body" | sed -E 's#^/(oc|opencode)[[:space:]]*##')"
mode=code
case "$body" in
  --report*|report:*|explain*|analyze*|research*|investigate*|audit*|compare*|why*|what*|how*)
    if ! printf '%s' "$body" | grep -Eiq '(fix|edit|change|modify|implement|add|remove|create|delete|refactor|debug|repair|update|build|write|publish|merge)'; then
      mode=report
    fi
    ;;
esac
echo "mode=$mode" >> "$GITHUB_OUTPUT"
echo "OC_TASK_MODE=$mode" >> "$GITHUB_ENV"
echo "Selected /oc task mode: $mode"
