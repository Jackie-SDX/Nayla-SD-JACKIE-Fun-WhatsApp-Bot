#!/usr/bin/env bash
set -u

attempt="${OC_ATTEMPT:-peer}"
runner_temp="${RUNNER_TEMP:-/tmp}"
peer_log="$runner_temp/copilot-peer-${attempt}.safe.log"
result_file="$runner_temp/copilot-peer-${attempt}.result"
mkdir -p "$runner_temp"
: > "$peer_log"

if [[ -z "${COPILOT_GITHUB_TOKEN:-}" ]]; then
  echo "::warning title=Copilot peer unavailable::No Copilot credential is configured; OpenCode continues solo."
  echo "COPILOT_PEER_RESULT=unavailable" > "$result_file"
  exit 0
fi

copilot_root="$runner_temp/copilot-cli"
copilot_bin="${COPILOT_CLI_BIN:-$copilot_root/node_modules/.bin/copilot}"
if [[ ! -x "$copilot_bin" ]]; then
  mkdir -p "$copilot_root"
  npm install --prefix "$copilot_root" --no-audit --no-fund --prefer-online --save-exact "@github/copilot@${COPILOT_CLI_VERSION:-1.0.86}" >"$copilot_root/install.log" 2>&1 || {
    echo "::warning title=Copilot peer installation unavailable::Peer consultation could not start; OpenCode continues solo."
    tail -80 "$copilot_root/install.log" 2>/dev/null || true
    echo "COPILOT_PEER_RESULT=unavailable" > "$result_file"
    exit 0
  }
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
  for secret in "${COPILOT_GITHUB_TOKEN:-}" "${OPENROUTER_API_KEY:-}" "${GITHUB_TOKEN:-}" "${GH_TOKEN:-}" "${UNIVERSAL_TOKEN:-}" "${OPENCODE_API_KEY:-}" "${COMPOSIO_API_KEY:-}"; do
    [[ -n "$secret" ]] && line="${line//$secret/[REDACTED]}"
  done
  printf "%s" "$line" | sed -E -e "s/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g" -e "s/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g" -e "s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g"
}

echo "[OC][copilot-peer] inviting Copilot in the current worktree"
set +e
GITHUB_TOKEN="$COPILOT_GITHUB_TOKEN" "$copilot_bin" \
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
  -p "$prompt" 2>&1 |
  while IFS= read -r line || [[ -n "$line" ]]; do
    safe="$(sanitize "$line")"
    printf "%s\n" "$safe" | tee -a "$peer_log"
  done
rc=${PIPESTATUS[0]}
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "COPILOT_PEER_RESULT=completed" > "$result_file"
else
  echo "COPILOT_PEER_RESULT=unavailable" > "$result_file"
  echo "::warning title=Copilot peer unavailable::Peer session exited non-zero; OpenCode continues with its own evidence and work."
fi
exit 0