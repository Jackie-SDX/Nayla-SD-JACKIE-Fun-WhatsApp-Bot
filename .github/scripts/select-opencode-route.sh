#!/usr/bin/env bash
set -uo pipefail
route_index="$(printenv OPENCODE_ROUTE_INDEX 2>/dev/null || true)"
start=0
if [[ -n "$route_index" ]]; then start=$((route_index + 1)); fi

redact_status() {
  local code="$1"
  case "$code" in
    200) return 0 ;;
    401|403) echo "authentication/authorization failure; moving to next independent route." ;;
    429) echo "quota/rate-limit response; moving to next route without retry storm." ;;
    500|502|503|504) echo "transient provider response ($code); moving to next route." ;;
    *) echo "HTTP $code; moving to next route." ;;
  esac
  return 1
}

probe_openrouter_model() {
  local model="$1"
  local api_key="$OPENROUTER_API_KEY"
  [[ -n "$api_key" && -n "$model" ]] || return 1
  [[ "$model" == *":free" ]] || { echo "OpenRouter primary model is not marked :free; refusing paid-route activation in the zero-cost lane."; return 1; }
  local body code
  body="$(mktemp)"
  code="$(
    curl -sS --connect-timeout 5 --max-time 18 -o "$body" -w "%{http_code}"       -H "Authorization: Bearer $api_key" -H "Content-Type: application/json"       -X POST https://openrouter.ai/api/v1/chat/completions       --data "$(jq -nc --arg model "$model" '{model:$model,messages:[{role:"user",content:"Reply with OK."}],max_tokens:1,temperature:0}')"       2>/dev/null
  )" || code=""
  rm -f "$body"
  case "$code" in
    200) return 0 ;;
    401|403) echo "OpenRouter primary authentication/authorization failed; moving to Google routes." ;;
    429) echo "OpenRouter primary rate limited; moving to Google routes without retry storm." ;;
    500|502|503|504) echo "OpenRouter primary transient response ($code); moving to Google routes." ;;
    *) echo "OpenRouter primary model returned HTTP $code; moving to Google routes." ;;
  esac
  return 1
}

probe_gemini() {
  local model="$1" key="$2"
  [[ -n "$key" ]] || return 1
  local body code
  body="$(mktemp)"
  code="$(
    curl -sS --connect-timeout 5 --max-time 18 -o "$body" -w "%{http_code}"       -H "x-goog-api-key: $key" -H "Content-Type: application/json"       -X POST "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent"       --data '{"contents":[{"parts":[{"text":"Reply with OK."}]}],"generationConfig":{"maxOutputTokens":1,"temperature":0}}'       2>/dev/null
  )" || code=""
  rm -f "$body"
  case "$code" in
    200) return 0 ;;
    401|403|429|500|502|503|504) redact_status "$code" ;;
    *) echo "Google $model returned HTTP $code; moving on." ;;
  esac
  return 1
}

probe_openrouter_free() {
  local api_key="$OPENROUTER_API_KEY"
  [[ -n "$api_key" ]] || return 1
  local body code
  body="$(mktemp)"
  code="$(
    curl -sS --connect-timeout 5 --max-time 18 -o "$body" -w "%{http_code}"       -H "Authorization: Bearer $api_key" -H "Content-Type: application/json"       -X POST https://openrouter.ai/api/v1/chat/completions       --data '{"model":"openrouter/free","messages":[{"role":"user","content":"Reply with OK."}],"max_tokens":1,"temperature":0}'       2>/dev/null
  )" || code=""
  rm -f "$body"
  case "$code" in
    200) return 0 ;;
    401|403) echo "OpenRouter free router authentication/authorization failed; no OpenRouter route remains." ;;
    429) echo "OpenRouter free router rate limited; no repeat." ;;
    500|502|503|504) echo "OpenRouter free router transient response ($code); no repeat." ;;
    *) echo "OpenRouter free router returned HTTP $code; no route selected." ;;
  esac
  return 1
}

key1="$(printenv GEMINI_API_KEY 2>/dev/null || true)"
key2="$(printenv GEMINI_API_KEY_2 2>/dev/null || true)"
key3="$(printenv GEMINI_API_KEY_3 2>/dev/null || true)"
key4="$(printenv GEMINI_API_KEY_4 2>/dev/null || true)"
key5="$(printenv GEMINI_API_KEY_5 2>/dev/null || true)"
primary_model="$(printenv OPENROUTER_PRIMARY_MODEL 2>/dev/null || true)"
[[ -n "$primary_model" ]] || primary_model="qwen/qwen3.8-27b:free"

gemini_route_count=25
global_fallback_index=26
route_count=27
keys=("$key1" "$key2" "$key3" "$key4" "$key5")

for ((i=start; i<route_count; i++)); do
  if (( i == 0 )); then
    echo "Route 1/$route_count: probing OpenRouter primary $primary_model..."
    if probe_openrouter_model "$primary_model"; then
      {
        echo "OPENCODE_SELECTED_GEMINI_KEY="
        echo "OPENCODE_SELECTED_MODEL=openrouter/$primary_model"
        echo "OPENCODE_SELECTED_VARIANT="
        echo "OPENCODE_SELECTED_PROVIDER=openrouter"
        echo "OPENCODE_ROUTE_INDEX=$i"
      } >> "$GITHUB_ENV"
      { echo "selected=true"; echo "route=openrouter/$primary_model"; } >> "$GITHUB_OUTPUT"
      exit 0
    fi
    continue
  fi

  if (( i <= gemini_route_count )); then
    offset=$((i - 1))
    model_index=$((offset / 5))
    key_index=$((offset % 5))
    case "$model_index" in
      0) model="gemini-3.8-flash" ;;
      1) model="gemini-3.7-flash" ;;
      2) model="gemini-3.6-flash" ;;
      3) model="gemini-3.5-flash" ;;
      4) model="gemini-3.5-flash-lite" ;;
    esac
    case "$key_index" in
      0) key="$key1" ;;
      1) key="$key2" ;;
      2) key="$key3" ;;
      3) key="$key4" ;;
      4) key="$key5" ;;
    esac

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
      { echo "selected=true"; echo "route=google/$model:key-slot-$((key_index+1))"; } >> "$GITHUB_OUTPUT"
      exit 0
    fi
    continue
  fi

  if (( i == global_fallback_index )); then
    echo "Route $((i+1))/$route_count: probing OpenRouter global free router..."
    if probe_openrouter_free; then
      {
        echo "OPENCODE_SELECTED_GEMINI_KEY="
        echo "OPENCODE_SELECTED_MODEL=openrouter/free"
        echo "OPENCODE_SELECTED_VARIANT="
        echo "OPENCODE_SELECTED_PROVIDER=openrouter"
        echo "OPENCODE_ROUTE_INDEX=$i"
      } >> "$GITHUB_ENV"
      { echo "selected=true"; echo "route=openrouter/free"; } >> "$GITHUB_OUTPUT"
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
{ echo "selected=false"; echo "route=none"; } >> "$GITHUB_OUTPUT"
echo "::warning title=No healthy model route::All configured zero-cost provider routes were unavailable."
exit 0
