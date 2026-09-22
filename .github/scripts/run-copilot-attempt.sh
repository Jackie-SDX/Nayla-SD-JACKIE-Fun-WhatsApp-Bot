#!/usr/bin/env bash
set -u

attempt="$1"
script_dir="$(cd "$(dirname "$0")" && pwd)"
runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || printf /tmp)"
stream_log="$(mktemp "$runner_temp/copilot-$attempt-stream-raw.XXXXXX")"
safe_log="$runner_temp/copilot-$attempt-safe.log"
copilot_fifo="$runner_temp/copilot-$attempt.fifo"
cleanup() {
  rm -f "$stream_log" "$mcp_config" "$copilot_fifo"
}
trap cleanup EXIT

sanitize_stream_line() {
  python3 -c '
import os,re,sys
keys=("COMPOSIO_API_KEY","OPENCODE_API_KEY","GITHUB_TOKEN","GH_TOKEN","UNIVERSAL_TOKEN","COPILOT_GITHUB_TOKEN","GEMINI_API_KEY","GEMINI_API_KEY_2","GEMINI_API_KEY_3","GEMINI_API_KEY_4","GEMINI_API_KEY_5")
secrets=[os.environ.get(k,"") for k in keys]
for raw in sys.stdin:
    line=raw.rstrip("\n")
    for secret in secrets:
        if secret:
            line=line.replace(secret,"[REDACTED]")
    line=re.sub(r"(AIza[A-Za-z0-9_-]{20,})","[REDACTED_GOOGLE_KEY]",line)
    line=re.sub(r"(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})","[REDACTED_GITHUB_TOKEN]",line)
    line=re.sub(r"(sk-or-v1-[A-Za-z0-9_-]{20,})","[REDACTED_EXTERNAL_API_KEY]",line)
    line=re.sub(r"(Bearer\s+)[^\s]+",r"\1[REDACTED]",line)
    print(line,flush=True)
'
}

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
prompt="$(printf "%s\\n\\n## Current GitHub task\\n%s" "$prompt" "$task")"
handoff_log="${HANDOFF_REVIEW_LOG:-}"
if [[ -n "$handoff_log" && -f "$handoff_log" ]]; then
  handoff="$(tail -n 220 "$handoff_log")"
  prompt="$(printf "%s\\n\\n## Prior OpenCode peer-review handoff\\n%s\\n\\nVerify the handoff findings independently; do not blindly apply them." "$prompt" "$handoff")"
fi
prompt="$(printf "%s\\n\\nDo not commit, push, reset, clean, delete branches, or create GitHub-side mutations. Inspect and edit only the checked-out isolated branch. Use Composio MCP when an external tool is actually required.\\n" "$prompt")"

max_credits="$(printenv COPILOT_MAX_AI_CREDITS 2>/dev/null || printf 60)"
mkfifo "$copilot_fifo"

set +e
GITHUB_TOKEN="${COPILOT_GITHUB_TOKEN:-${GITHUB_TOKEN:-}}" "$copilot_bin" \
  --model auto \
  --stream=on \
  --max-ai-credits "$max_credits" \
  --no-ask-user \
  --allow-tool "shell" \
  --allow-tool "write" \
  --deny-tool "shell(git commit)" \
  --deny-tool "shell(git push)" \
  --deny-tool "shell(git reset)" \
  --deny-tool "shell(git clean)" \
  --deny-tool "shell(gh)" \
  --deny-tool "shell(curl)" \
  --deny-tool "shell(wget)" \
  ${mcp_args[@]} \
  -p "$prompt" >"$copilot_fifo" 2>&1 &
copilot_pid=$!

cat "$copilot_fifo" | sanitize_stream_line | tee "$stream_log" | awk -f "$script_dir/filter-opencode-live-output.awk" | tee -a "$safe_log"

wait "$copilot_pid"
exit_code=$?
set -e

{
  echo "exit_code=$exit_code"
  echo "safe_log_path=$safe_log"
} >> "$GITHUB_OUTPUT"

echo "GitHub Copilot attempt $attempt exit code: $exit_code"
echo "GitHub Copilot live stream captured in sanitized log."


