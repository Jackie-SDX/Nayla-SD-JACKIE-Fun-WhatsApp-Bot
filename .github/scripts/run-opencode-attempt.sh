#!/usr/bin/env bash
set -u

attempt="${1:-unknown}"
agent_timeout_minutes="${OPENCODE_AGENT_TIMEOUT_MINUTES:-350}"
if [[ ! "$agent_timeout_minutes" =~ ^[0-9]+$ ]] || (( agent_timeout_minutes < 1 || agent_timeout_minutes >= 360 )); then
  echo "::error title=Invalid OpenCode timeout::OPENCODE_AGENT_TIMEOUT_MINUTES must be an integer from 1 to 359."
  exit 2
fi
command -v timeout >/dev/null 2>&1 || {
  echo "::error title=Missing timeout utility::GNU timeout is required for controlled OpenCode execution."
  exit 2
}
raw_log="$(mktemp "${RUNNER_TEMP:-/tmp}/opencode-${attempt}-raw.XXXXXX")"
safe_log="${RUNNER_TEMP:-/tmp}/opencode-${attempt}-safe.log"

cleanup() {
  rm -f "$raw_log"
}
trap cleanup EXIT

set +e
agent_cmd=()
if [[ "${OC_TARGET_MODE:-local}" == "remote" ]]; then
  ws="${OC_TARGET_WORKSPACE:-}"
  if [[ -z "$ws" || ! -d "$ws/.git" ]]; then
    echo "::error title=Remote target workspace missing for attempt ${attempt}::prepare-oc-target.sh must run before the agent attempt." >&2
    exit 2
  fi
  task_prompt="${OC_TARGET_TASK:-}"
  if [[ -n "${OC_TARGET_TASK_FILE:-}" && -f "${OC_TARGET_TASK_FILE:-}" ]]; then
    task_prompt="$(cat "$OC_TARGET_TASK_FILE")"
  fi
  [[ -n "$task_prompt" ]] || task_prompt="Inspect the target repository workspace and implement the requested change. Do not modify anything outside the workspace."
  model_name="${MODEL:-opencode/big-pickle}"
  agent_cmd=(opencode run --dir "$ws" --model "$model_name")
  [[ -n "${VARIANT:-}" ]] && agent_cmd+=(--variant "$VARIANT")
  agent_cmd+=(--agent build --title "oc remote ${OC_TARGET_REPO:-target}" "$task_prompt")
else
  agent_cmd=(opencode github run)
fi
timeout --signal=TERM --kill-after=60s "${agent_timeout_minutes}m" "${agent_cmd[@]}" >"$raw_log" 2>&1
exit_code=$?
set -e
termination_reason="completed"
if [[ "$exit_code" -eq 124 ]]; then
  termination_reason="timeout"
elif [[ "$exit_code" -ne 0 ]]; then
  termination_reason="failed"
fi

safe_contents="$(cat "$raw_log")"

for secret in \
  "${COMPOSIO_API_KEY:-}" \
  "${OPENCODE_API_KEY:-}" \
  "${GITHUB_TOKEN:-}" \
  "${GH_TOKEN:-}" \
  "${UNIVERSAL_TOKEN:-}" \
  "${COPILOT_GITHUB_TOKEN:-}"; do
  if [[ -n "$secret" ]]; then
    safe_contents="${safe_contents//$secret/[REDACTED]}"
  fi
done

printf '%s\n' "$safe_contents" |
  sed -E \
    -e 's/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g' \
    -e 's/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/(sk-or-v1-[[:alnum:]_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g' \
    -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' \
  > "$safe_log"

{
  echo "exit_code=$exit_code"
  echo "termination_reason=$termination_reason"
  echo "safe_log_path=$safe_log"
} >> "$GITHUB_OUTPUT"

echo "OpenCode attempt ${attempt} exit code: ${exit_code}"
echo "--- sanitized OpenCode tail (last 100 lines) ---"
tail -n 100 "$safe_log" || true
echo "--- end sanitized OpenCode tail ---"

exit "$exit_code"
