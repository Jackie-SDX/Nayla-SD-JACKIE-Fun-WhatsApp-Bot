#!/usr/bin/env bash
set -u

attempt="${1:-unknown}"
raw_log="$(mktemp "/tmp/copilot-${attempt}-raw.XXXXXX")"
safe_log="/tmp/copilot-${attempt}-safe.log"
mcp_config=""

cleanup() {
  rm -f "$raw_log" "$mcp_config"
}
trap cleanup EXIT

task="$(jq -r '.comment.body // empty' "$GITHUB_EVENT_PATH")"
task="$(printf '%s' "$task" | sed -E 's#^/(oc|opencode)[[:space:]]*##')"
if [[ -z "$task" ]]; then
  task="Inspect the repository state and report what you found. Do not change files."
fi

mcp_args=()
if [[ -n "${COMPOSIO_API_KEY:-}" ]]; then
  mcp_config="$(mktemp "/tmp/copilot-mcp.XXXXXX.json")"
  jq -n --arg key "$COMPOSIO_API_KEY" '{
    mcpServers: {
      composio: {
        type: "http",
        url: "https://connect.composio.dev/mcp",
        headers: {"x-consumer-api-key": $key},
        tools: ["*"]
      }
    }
  }' > "$mcp_config"
  mcp_args+=(--additional-mcp-config "@$mcp_config" --allow-tool "composio")
fi

prompt="$(cat .github/copilot-instructions.md)"
prompt+=$'\n\n## Current GitHub task\n'
prompt+="$task"
prompt+=$'\n\nDo not commit, push, reset, clean, delete branches, or create GitHub-side mutations. Inspect and edit only the checked-out isolated branch. Use Composio MCP when an external tool is actually required.\n'

set +e
copilot \
  --model auto \
  --max-ai-credits "${COPILOT_MAX_AI_CREDITS:-60}" \
  --no-ask-user \
  -s \
  --allow-tool "shell" \
  --deny-tool "shell(git commit)" \
  --deny-tool "shell(git push)" \
  --deny-tool "shell(git reset)" \
  --deny-tool "shell(git clean)" \
  --deny-tool "shell(gh)" \
  --deny-tool "shell(curl)" \
  --deny-tool "shell(wget)" \
  "${mcp_args[@]}" \
  --secret-env-vars "COMPOSIO_API_KEY" \
  -p "$prompt" >"$raw_log" 2>&1
exit_code=$?
set -e

RAW_LOG="$raw_log" SAFE_LOG="$safe_log" python3 - <<'PY'
import os, re
from pathlib import Path
raw=Path(os.environ["RAW_LOG"]).read_text(errors="replace")
for key in ("COPILOT_GITHUB_TOKEN","GITHUB_TOKEN","COMPOSIO_API_KEY","OPENCODE_API_KEY","GEMINI_API_KEY","GEMINI_API_KEY_2","GEMINI_API_KEY_3","GEMINI_API_KEY_4","GEMINI_API_KEY_5"):
    value=os.environ.get(key)
    if value:
        raw=raw.replace(value,"[REDACTED]")
raw=re.sub(r"(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})","[REDACTED_GITHUB_TOKEN]",raw)
raw=re.sub(r"(AIza[A-Za-z0-9_-]{20,})","[REDACTED_GOOGLE_KEY]",raw)
raw=re.sub(r"(Bearer\s+)[^\s]+",r"\1[REDACTED]",raw)
Path(os.environ["SAFE_LOG"]).write_text(raw)
PY

{
  echo "exit_code=$exit_code"
  echo "safe_log_path=$safe_log"
} >> "$GITHUB_OUTPUT"

echo "GitHub Copilot attempt $attempt exit code: $exit_code"
echo "--- sanitized Copilot tail (last 100 lines) ---"
tail -n 100 "$safe_log" || true
echo "--- end sanitized Copilot tail ---"

exit "$exit_code"
