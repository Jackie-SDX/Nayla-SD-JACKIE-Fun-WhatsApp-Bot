#!/usr/bin/env bash
set -u

attempt="${OC_ATTEMPT:-peer}"
runner_temp="${RUNNER_TEMP:-/tmp}"
peer_log="$runner_temp/copilot-peer-${attempt}.safe.log"
result_file="$runner_temp/copilot-peer-${attempt}.result"
mkdir -p "$runner_temp"
: > "$peer_log"
peer_started_at="$(date +%s)"

write_peer_result() {
  local result="$1"
  local elapsed="$(( $(date +%s) - peer_started_at ))"
  {
    echo "COPILOT_PEER_RESULT=$result"
    echo "COPILOT_PEER_ELAPSED_SECONDS=$elapsed"
    echo "COPILOT_PEER_LOG_PATH=$peer_log"
  } > "$result_file"
}

peer_token="${COPILOT_GITHUB_TOKEN:-}"
if [[ -z "$peer_token" && -f "${COPILOT_PEER_TOKEN_FILE:-}" ]]; then
  peer_token="$(cat "$COPILOT_PEER_TOKEN_FILE")"
fi
if [[ -z "$peer_token" ]]; then
  echo "::warning title=Copilot peer unavailable::No Copilot credential is configured; OpenCode continues solo."
  write_peer_result unavailable
  exit 0
fi

copilot_root="$runner_temp/copilot-cli"
copilot_bin="${COPILOT_CLI_BIN:-$copilot_root/node_modules/.bin/copilot}"
mcp_args=()
mcp_config=""
cleanup_mcp() { [[ -n "$mcp_config" ]] && rm -f "$mcp_config" || true; }
trap cleanup_mcp EXIT
if [[ ! -x "$copilot_bin" ]]; then
  mkdir -p "$copilot_root"
  npm install --prefix "$copilot_root" --no-audit --no-fund --prefer-online --save-exact "@github/copilot@${COPILOT_CLI_VERSION:-1.0.86}" >"$copilot_root/install.log" 2>&1 || {
    echo "::warning title=Copilot peer installation unavailable::Peer consultation could not start; OpenCode continues solo."
    tail -80 "$copilot_root/install.log" 2>/dev/null || true
    write_peer_result unavailable
    exit 0
  }
fi

if [[ -n "${COMPOSIO_MCP_URL:-}" && -f "${COMPOSIO_MCP_HEADERS_FILE:-}" ]]; then
  mcp_config="$(mktemp "$runner_temp/copilot-peer-mcp.XXXXXX.json")"
  headers_json="$(python3 - "${COMPOSIO_MCP_HEADERS_FILE}" <<'PY'
import json,sys
headers={}
for line in open(sys.argv[1],errors="replace"):
    line=line.rstrip("\n")
    if ":" not in line: continue
    k,v=line.split(":",1)
    headers[k.strip()]=v.lstrip()
print(json.dumps(headers))
PY
  )"
  jq -n --arg url "$COMPOSIO_MCP_URL" --argjson headers "$headers_json" '{mcpServers:{composio:{type:"http",url:$url,headers:$headers,tools:["*"]}}}' > "$mcp_config"
  mcp_args+=(--additional-mcp-config "@$mcp_config" --allow-tool "composio")
fi

task="${COPILOT_PEER_TASK:-}"
[[ -n "$task" ]] || task="${1:-Review the current work as an independent engineering peer. Identify risks, missing tests, and concrete fixes.}"
state="$(git status --short 2>/dev/null | head -80)"
diff_stat="$(git diff --stat 2>/dev/null | head -40)"
policy_root="${OC_CONTROLLER_ROOT:-$PWD}"
copilot_rules="$(cat "$policy_root/.github/copilot-instructions.md" 2>/dev/null || true)"

prompt="$copilot_rules

## OpenCode peer invitation
You are the second engineering brain in an active OpenCode task.

Question/task:
$task

You are operating in the SAME isolated worktree that OpenCode is using.
Current state:
$state

Diff summary:
$diff_stat

Inspect, test, and edit this worktree as useful. Do not commit, push, reset, clean, delete branches, or mutate GitHub through gh. Do not wait for user approval.
Return findings and make concrete corrective edits when justified.
OpenCode will re-read your changes and independently validate the resulting tree."

sanitize() {
  local line="$1" secret
  for secret in "${peer_token:-}" "${COPILOT_GITHUB_TOKEN:-}" "${OPENROUTER_API_KEY:-}" "${GITHUB_TOKEN:-}" "${GH_TOKEN:-}" "${UNIVERSAL_TOKEN:-}" "${OPENCODE_API_KEY:-}" "${COMPOSIO_API_KEY:-}"; do
    [[ -n "$secret" ]] && line="${line//$secret/[REDACTED]}"
  done
  printf "%s" "$line" | sed -E -e "s/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g" -e "s/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g" -e "s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g"
}

echo "[OC][copilot-peer] inviting Copilot in the current worktree"
set +e
GITHUB_TOKEN="$peer_token" "$copilot_bin" \
  --model auto \
  --stream=on \
  --max-ai-credits "${COPILOT_PEER_MAX_AI_CREDITS:-30}" \
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
  -p "$prompt" 2>&1 |
  while IFS= read -r line || [[ -n "$line" ]]; do
    safe="$(sanitize "$line")"
    printf "%s\n" "$safe" | tee -a "$peer_log"
  done
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -eq 0 ]]; then
  write_peer_result completed
else
  echo "COPILOT_PEER_RESULT=unavailable" > "$result_file"
  echo "::warning title=Copilot peer unavailable::Peer session exited non-zero; OpenCode continues with its own evidence and work."
fi
exit 0