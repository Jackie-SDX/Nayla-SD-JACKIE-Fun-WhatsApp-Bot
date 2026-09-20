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
if [[ -n "${COMPOSIO_MCP_URL:-}" && -f "${COMPOSIO_MCP_HEADERS_FILE:-}" ]]; then
  mcp_config="$(mktemp "/tmp/copilot-mcp.XXXXXX.json")"
  headers_json="$(python3 - "$COMPOSIO_MCP_HEADERS_FILE" <<'PY'
import json,sys
headers={}
for line in open(sys.argv[1],errors="replace"):
    line=line.rstrip("\n")
    if ":" not in line:
        continue
    key,value=line.split(":",1)
    headers[key.strip()]=value.lstrip()
print(json.dumps(headers))
PY
)"
  jq -n --arg url "$COMPOSIO_MCP_URL" --argjson headers "$headers_json" '{
    mcpServers: {
      composio: {
        type: "http",
        url: $url,
        headers: $headers,
        tools: ["*"]
      }
    }
  }' > "$mcp_config"
  mcp_args+=(--additional-mcp-config "@$mcp_config" --allow-tool "composio")
fi

copilot_root="${RUNNER_TEMP:-/tmp}/copilot-cli"
copilot_bin="$copilot_root/node_modules/.bin/copilot"
mkdir -p "$copilot_root"
if [[ ! -x "$copilot_bin" ]]; then
  npm install --prefix "$copilot_root" --no-audit --no-fund --prefer-online --save-exact "@github/copilot@${COPILOT_CLI_VERSION:-1.0.86}" >"$copilot_root/install.log" 2>&1 || {
    echo "::error title=GitHub Copilot CLI installation failed::Could not install the pinned @github/copilot package."
    tail -120 "$copilot_root/install.log" || true
    exit 1
  }
fi
test -x "$copilot_bin" || {
  echo "::error title=GitHub Copilot CLI missing::Expected $copilot_bin."
  exit 1
}
copilot_actual="$("$copilot_bin" --version 2>/dev/null)"
echo "GitHub Copilot CLI: $copilot_actual"
[[ "$copilot_actual" == *"${COPILOT_CLI_VERSION:-1.0.86}"* ]] || {
  echo "::error title=GitHub Copilot CLI version mismatch::Expected ${COPILOT_CLI_VERSION:-1.0.86}, got $copilot_actual"
  exit 1
}

prompt="$(cat .github/copilot-instructions.md)"
prompt+=$'\n\n## Current GitHub task\n'
prompt+="$task"
prompt+=$'\n\nDo not commit, push, reset, clean, delete branches, or create GitHub-side mutations. Inspect and edit only the checked-out isolated branch. Use Composio MCP when an external tool is actually required.\n'

set +e
"$copilot_bin" \
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
