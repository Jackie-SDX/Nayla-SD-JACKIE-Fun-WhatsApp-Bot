#!/usr/bin/env bash
set -uo pipefail

start=0
if [[ -n "${OPENCODE_ROUTE_INDEX:-}" ]]; then
  start=$((OPENCODE_ROUTE_INDEX + 1))
fi

redact_status() {
  local code="$1"
  case "$code" in
    200) return 0 ;;
    401|403) echo "authentication/authorization failure; moving to next independent route." ;;
    429) echo "quota/rate-limit response; moving to next route without retry storm." ;;
    500|502|503|504) echo "transient provider response ($code); moving to next route." ;;
    *) echo "HTTP ${code:-unknown}; moving to next route." ;;
  esac
  return 1
}

probe_gemini() {
  local model="$1"
  local key="$2"
  [[ -n "$key" ]] || return 1

  local body code
  body="$(mktemp)"
  code="$(
    curl -sS \
      --connect-timeout 5 \
      --max-time 18 \
      -o "$body" \
      -w '%{http_code}' \
      -H "x-goog-api-key: $key" \
      -H 'Content-Type: application/json' \
      -X POST \
      "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" \
      --data '{"contents":[{"parts":[{"text":"Reply with OK."}]}],"generationConfig":{"maxOutputTokens":1,"temperature":0}}' \
      2>/dev/null
  )" || code=""
  rm -f "$body"

  case "$code" in
    200) return 0 ;;
    401|403) redact_status "$code" ;;
    429) redact_status "$code" ;;
    500|502|503|504) redact_status "$code" ;;
    *) echo "Google ${model} returned HTTP ${code:-unknown}; moving on." ;;
  esac
  return 1
}

probe_openrouter() {
  [[ -n "${OPENROUTER_API_KEY:-}" ]] || return 1

  local body code
  body="$(mktemp)"
  code="$(
    curl -sS \
      --connect-timeout 5 \
      --max-time 18 \
      -o "$body" \
      -w '%{http_code}' \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      -H 'Content-Type: application/json' \
      -X POST \
      'https://openrouter.ai/api/v1/chat/completions' \
      --data '{"model":"openrouter/free","messages":[{"role":"user","content":"Reply with OK."}],"max_tokens":1}' \
      2>/dev/null
  )" || code=""
  rm -f "$body"

  case "$code" in
    200) return 0 ;;
    401|403) echo "OpenRouter authentication/authorization failed; moving on." ;;
    429) echo "OpenRouter rate limited; no repeat; route exhausted." ;;
    500|502|503|504) echo "OpenRouter transient response ($code); route exhausted." ;;
    *) echo "OpenRouter free router returned HTTP ${code:-unknown}; no route selected." ;;
  esac
  return 1
}

models=(
  "gemini-3.8-flash"
  "gemini-3.7-flash"
  "gemini-3.6-flash"
  "gemini-3.5-flash"
  "gemini-3.5-flash-lite"
)

keys=(
  "${GEMINI_API_KEY:-}"
  "${GEMINI_API_KEY_2:-}"
  "${GEMINI_API_KEY_3:-}"
  "${GEMINI_API_KEY_4:-}"
  "${GEMINI_API_KEY_5:-}"
)

route_count=$(( ${#models[@]} * ${#keys[@]} + 1 ))

for ((i=start; i<route_count; i++)); do
  if (( i < ${#models[@]} * ${#keys[@]} )); then
    model_index=$((i / ${#keys[@]}))
    key_index=$((i % ${#keys[@]}))
    model="${models[$model_index]}"
    key="${keys[$key_index]}"

    if [[ -z "$key" ]]; then
      echo "Route $((i+1))/$route_count: Gemini key slot $((key_index+1)) is not configured; skipping."
      continue
    fi

    echo "Route $((i+1))/$route_count: probing Google $model with key slot $((key_index+1))..."
    if probe_gemini "$model" "$key"; then
      echo "::add-mask::$key"
      {
        echo "OPENCODE_SELECTED_GEMINI_KEY=$key"
        echo "OPENCODE_SELECTED_MODEL=google/$model"
        echo "OPENCODE_SELECTED_VARIANT=high"
        echo "OPENCODE_SELECTED_PROVIDER=google"
        echo "OPENCODE_ROUTE_INDEX=$i"
      } >> "$GITHUB_ENV"
      {
        echo "selected=true"
        echo "route=google/$model:key-slot-$((key_index+1))"
      } >> "$GITHUB_OUTPUT"
      exit 0
    fi
  else
    echo "Route $((i+1))/$route_count: probing OpenRouter free router..."
    if probe_openrouter; then
      {
        echo "OPENCODE_SELECTED_GEMINI_KEY="
        echo "OPENCODE_SELECTED_MODEL=openrouter/free"
        echo "OPENCODE_SELECTED_VARIANT="
        echo "OPENCODE_SELECTED_PROVIDER=openrouter"
        echo "OPENCODE_ROUTE_INDEX=$i"
      } >> "$GITHUB_ENV"
      {
        echo "selected=true"
        echo "route=openrouter/free"
      } >> "$GITHUB_OUTPUT"
      exit 0
    fi
  fi
  sleep 1
done

{
  echo "OPENCODE_SELECTED_GEMINI_KEY="
  echo "OPENCODE_SELECTED_MODEL="
  echo "OPENCODE_SELECTED_VARIANT="
  echo "OPENCODE_SELECTED_PROVIDER="
} >> "$GITHUB_ENV"
{
  echo "selected=false"
  echo "route=none"
} >> "$GITHUB_OUTPUT"
echo "::warning title=No healthy model route::All configured zero-cost provider routes were unavailable."
exit 0
