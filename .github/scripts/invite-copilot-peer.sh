#!/usr/bin/env bash
set -u

attempt="${OC_ATTEMPT:-peer}"
runner_temp="${RUNNER_TEMP:-/tmp}"
peer_log="$runner_temp/copilot-peer-${attempt}.safe.log"
state_file="$runner_temp/copilot-peer-collab.state"
result_file="$runner_temp/copilot-peer-${attempt}.result"
hook_log="$runner_temp/copilot-hooks-${attempt}.log"
mkdir -p "$runner_temp"
: > "$peer_log"
: > "$hook_log"
export OC_COPILOT_HOOK_LOG="$hook_log"
peer_started_at="$(date +%s)"
max_rounds="$(printenv COPILOT_PEER_MAX_ROUNDS 2>/dev/null || printf 5)"
round="$(printenv COPILOT_PEER_ROUND 2>/dev/null || printf 1)"

write_peer_result() {
  local result="$1"
  local elapsed="$(( $(date +%s) - peer_started_at ))"
  {
    echo "COPILOT_PEER_RESULT=$result"
    echo "COPILOT_PEER_ELAPSED_SECONDS=$elapsed"
    echo "COPILOT_PEER_LOG_PATH=$peer_log"
    echo "COPILOT_PEER_ROUNDS_USED=$(grep -c "^round=" "$state_file" 2>/dev/null || true)"
  } > "$result_file"
}

if ! [[ "$round" =~ ^[1-9][0-9]*$ ]] || ! [[ "$max_rounds" =~ ^[1-9][0-9]*$ ]] || (( round > max_rounds )); then
  echo "[COPILOT] peer round $round exceeds maximum $max_rounds; skipping without failing OpenCode"
  write_peer_result skipped_limit
  exit 0
fi

task="${COPILOT_PEER_TASK:-}"
[[ -n "$task" ]] || task="${1:-Review the current work as an independent engineering peer. Identify risks, missing tests, and concrete fixes.}"
diff_signature="$(git diff --binary 2>/dev/null | sha256sum | awk "{print \$1}")"
task_signature="$(printf "%s\n%s\n%s" "$round" "$task" "$diff_signature" | sha256sum | awk "{print \$1}")"
if grep -Fq "signature=$task_signature" "$state_file" 2>/dev/null; then
  echo "[COPILOT] duplicate objective on unchanged state; skipping round $round"
  write_peer_result skipped_duplicate
  exit 0
fi
{
  echo "round=$round"
  echo "signature=$task_signature"
} >> "$state_file"

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

state="$(git status --short 2>/dev/null | head -80)"
diff_stat="$(git diff --stat 2>/dev/null | head -40)"
context_path="${OC_ISSUE_CONTEXT_FILE:-$runner_temp/oc-issue-context.md}"
policy_root="${OC_CONTROLLER_ROOT:-$PWD}"
copilot_rules="$(cat "$policy_root/.github/copilot-instructions.md" 2>/dev/null || true)"

prompt="$copilot_rules

## OpenCode peer invitation
You are the second engineering brain in an active OpenCode task.

Question/task:
$task

You are operating in the SAME isolated worktree that OpenCode is using.

Give concise visible engineering notes before material actions: hypothesis, evidence, next action, result. Do not flood the shared stage with timestamps, hashes, or token-level narration. Read the shared task context in bounded batches before consequential changes.
Shared task context: $context_path
Read that file in bounded batches before consequential action; it contains the complete issue body/comments/review comments captured by the controller.

Current state:
$state

Diff summary:
$diff_stat

Inspect, test, and edit this worktree as useful. Do not commit, push, reset, clean, delete branches, or mutate GitHub through gh. Do not wait for user approval.
Return findings and make concrete corrective edits when justified.
OpenCode will re-read your changes and independently validate the resulting tree."

is_noise_line() {
  printf '%s' "$1" | grep -Eq '^(Resume copilot|Tokens |AI Credits |Changes |.*copilot --resume=)'
}

sanitize() {
  local line="$1" secret
  for secret in "${peer_token:-}" "${COPILOT_GITHUB_TOKEN:-}" "${OPENROUTER_API_KEY:-}" "${GITHUB_TOKEN:-}" "${GH_TOKEN:-}" "${UNIVERSAL_TOKEN:-}" "${OPENCODE_API_KEY:-}" "${COMPOSIO_API_KEY:-}"; do
    [[ -n "$secret" ]] && line="${line//$secret/[REDACTED]}"
  done
  printf "%s" "$line" | sed -E -e "s/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g" -e "s/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g" -e "s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g"
}

# Copilot CLI 1.0.x has no builtin agent registry; passing --agent for a
# non-empty builtin (e.g. "general-purpose") aborts the peer session. Only pin
# --agent when the operator explicitly configured a custom agent.
agent_args=()
if [[ -n "${COPILOT_PEER_AGENT:-}" ]]; then
  agent_args+=(--agent "$COPILOT_PEER_AGENT")
fi

echo "[OC][copilot-peer] inviting Copilot in the current worktree"
set +e
(tail -n 0 -F "$hook_log" 2>/dev/null | while IFS= read -r hook_line; do printf "%s\n" "$hook_line"; done) &
hook_tail_pid=$!
GITHUB_TOKEN="$peer_token" "$copilot_bin" \
  --model "${COPILOT_PEER_MODEL:-auto}" \
  "${agent_args[@]}" \
  --stream=on \
  --max-ai-credits "${COPILOT_PEER_MAX_AI_CREDITS:-30}" \
  --no-ask-user \
  --allow-tool "shell" \
  --allow-tool "read" \
  --allow-tool "url" \
  --allow-tool "memory" \
  --allow-tool "write" \
  --deny-tool "shell(git commit)" \
  --deny-tool "shell(git push)" \
  --deny-tool "shell(git reset)" \
  --deny-tool "shell(git clean)" \
  --deny-tool "shell(gh)" \
  --deny-tool "shell(curl)" \
  --deny-tool "shell(wget)" \
  --secret-env-vars "COPILOT_GITHUB_TOKEN,GITHUB_TOKEN,GH_TOKEN,UNIVERSAL_TOKEN,OPENROUTER_API_KEY,OPENCODE_API_KEY,COMPOSIO_API_KEY" \
  ${mcp_args[@]} \
  -p "$prompt" 2>&1 |
  while IFS= read -r line || [[ -n "$line" ]]; do
    if is_noise_line "$line"; then continue; fi
    safe="$(sanitize "$line")"
    printf "[COPILOT] %s\n" "$safe" | tee -a "$peer_log"
  done
rc=${PIPESTATUS[0]}
kill "$hook_tail_pid" 2>/dev/null || true
wait "$hook_tail_pid" 2>/dev/null || true
set -e

if [[ "$rc" -eq 0 ]]; then
  write_peer_result completed
else
  write_peer_result unavailable
  echo "::warning title=Copilot peer unavailable::Peer session exited non-zero; OpenCode continues with its own evidence and work."
fi
exit 0