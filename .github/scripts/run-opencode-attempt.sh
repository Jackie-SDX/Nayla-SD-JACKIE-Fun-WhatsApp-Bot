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
command -v mkfifo >/dev/null 2>&1 || {
  echo "::error title=Missing mkfifo utility::mkfifo is required for live OpenCode output streaming."
  exit 2
}

runner_temp="${RUNNER_TEMP:-/tmp}"
mkdir -p "$runner_temp"
safe_log="$runner_temp/opencode-${attempt}-safe.log"
progress_log="$runner_temp/opencode-${attempt}-progress.log"
fifo="$runner_temp/opencode-${attempt}.fifo"
output_file="${GITHUB_OUTPUT:-/dev/null}"
: > "$safe_log"
: > "$progress_log"

cleanup() {
  [[ -n "${heartbeat_pid:-}" ]] && kill "$heartbeat_pid" 2>/dev/null || true
  rm -f "$fifo"
}
trap cleanup EXIT

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

sanitize_line() {
  local line="$1" secret
  for secret in \
    "${COMPOSIO_API_KEY:-}" \
    "${OPENCODE_API_KEY:-}" \
    "${GITHUB_TOKEN:-}" \
    "${GH_TOKEN:-}" \
    "${UNIVERSAL_TOKEN:-}" \
    "${COPILOT_GITHUB_TOKEN:-}"; do
    if [[ -n "$secret" ]]; then
      line="${line//$secret/[REDACTED]}"
    fi
  done
  printf "%s" "$line" |
    sed -E \
      -e "s/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g" \
      -e "s/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g" \
      -e "s/(sk-or-v1-[[:alnum:]_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g" \
      -e "s/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g"
}

configured_timeout_seconds=$((agent_timeout_minutes * 60))
effective_timeout_seconds="$configured_timeout_seconds"
job_budget_seconds="${OC_JOB_BUDGET_SECONDS:-}"
job_safety_seconds="${OC_JOB_SAFETY_MARGIN_SECONDS:-120}"
job_start_epoch="${OC_JOB_START_EPOCH:-}"

if [[ -n "$job_budget_seconds" && "$job_budget_seconds" =~ ^[0-9]+$ &&
      "$job_safety_seconds" =~ ^[0-9]+$ && "$job_start_epoch" =~ ^[0-9]+$ ]]; then
  now_epoch="$(date +%s)"
  elapsed=$((now_epoch - job_start_epoch))
  remaining=$((job_budget_seconds - elapsed - job_safety_seconds))
  if (( remaining < effective_timeout_seconds )); then
    effective_timeout_seconds="$remaining"
  fi
fi

{
  printf "effective_timeout_seconds=%s\n" "$effective_timeout_seconds"
  printf "progress_log_path=%s\n" "$progress_log"
  printf "safe_log_path=%s\n" "$safe_log"
} >> "$output_file"

if (( effective_timeout_seconds < 1 )); then
  printf "termination_reason=timeout\nexit_code=124\n" >> "$output_file"
  echo "::warning title=OpenCode attempt budget exhausted::No remaining job budget is available for attempt ${attempt}."
  exit 124
fi

heartbeat_interval="${OC_PROGRESS_INTERVAL_SECONDS:-30}"
if [[ ! "$heartbeat_interval" =~ ^[0-9]+$ ]] || (( heartbeat_interval < 1 )); then
  heartbeat_interval=30
fi

start_epoch="$(date +%s)"
printf "[OC][attempt=%s][elapsed=0s] started route=%s\n" "$attempt" "${MODEL:-github}" >> "$progress_log"
echo "[OC][attempt=${attempt}][elapsed=0s] started route=${MODEL:-github}"
mkfifo "$fifo"

heartbeat() {
  local elapsed
  while kill -0 "$agent_pid" 2>/dev/null; do
    sleep "$heartbeat_interval"
    kill -0 "$agent_pid" 2>/dev/null || break
    elapsed=$(( $(date +%s) - start_epoch ))
    printf "[OC][attempt=%s][elapsed=%ss] heartbeat state=running\n" "$attempt" "$elapsed" | tee -a "$progress_log"
  done
}

set +e
timeout --signal=TERM --kill-after=60s "${effective_timeout_seconds}s" "${agent_cmd[@]}" >"$fifo" 2>&1 &
agent_pid=$!
heartbeat &
heartbeat_pid=$!

while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  safe_line="$(sanitize_line "$raw_line")"
  printf "%s\n" "$safe_line" | tee -a "$safe_log"
done < "$fifo"

wait "$agent_pid"
exit_code=$?
set -e

elapsed=$(( $(date +%s) - start_epoch ))
termination_reason="completed"
case "$exit_code" in
  124) termination_reason="timeout" ;;
  125|126|127) termination_reason="failed" ;;
  128|129|130|131|132|133|134|135|136|137|138|139|140|141|142|143|144|145|146|147|148|149|150|151|152|153|154|155|156|157|158|159) termination_reason="signal" ;;
  0) termination_reason="completed" ;;
  *) termination_reason="failed" ;;
esac

printf "[OC][attempt=%s][elapsed=%ss] finished exit_code=%s termination_reason=%s\n" "$attempt" "$elapsed" "$exit_code" "$termination_reason" | tee -a "$progress_log"

{
  printf "exit_code=%s\n" "$exit_code"
  printf "termination_reason=%s\n" "$termination_reason"
  printf "safe_log_path=%s\n" "$safe_log"
  printf "progress_log_path=%s\n" "$progress_log"
  printf "effective_timeout_seconds=%s\n" "$effective_timeout_seconds"
} >> "$output_file"

echo "[OC][attempt=${attempt}] live stream complete; exit_code=${exit_code}; termination_reason=${termination_reason}"
exit "$exit_code"
