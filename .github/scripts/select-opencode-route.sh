#!/usr/bin/env bash
set -u

start=0
if [[ -n "${OPENCODE_ROUTE_INDEX:-}" ]]; then
  start=$((OPENCODE_ROUTE_INDEX + 1))
fi

probe_gemini() {
  local model="$1"
  local key="$2"
  local body code
  [[ -n "$key" ]] || return 1

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
      -d '{"contents":[{"parts":[{"text":"Reply with OK."}]}],"generationConfig":{"maxOutputTokens":1,"temperature":0}}' \
      2>/dev/null || true
  )"
  rm -f "$body"

  case "$code" in
    200) return 0 ;;
    401|403) echo "Google $model returned $code (authentication/authorization); moving on." ;;
    429) echo "Google $model returned 429 (quota/rate limit); rotating immediately." ;;
    500|502|503|504) echo "Google $model returned $code (transient service condition); moving on." ;;
    *) echo "Google $model returned HTTP ${code:-unknown}; moving on." ;;
  esac
  return 1
}

probe_openrouter() {
  local body code
  [[ -n "${OPENROUTER_API_KEY:-}" ]] || return 1

  body="$(mktemp)"
  code="$(
    curl -sS \
      --connect-timeout 5 \
      --max-time 18 \
      -o "$body" \
      -w '%{http_code}' \
      -H "Authorization: Bearer ${OPENROUTER_API_KEY}" \
      -H 'Content-Type: application/json' \
      -X POST \
      'https://openrouter.ai/api/v1/chat/completions' \
      -d '{"model":"openrouter/free","messages":[{"role":"user","content":"Reply with OK."}],"max_tokens":1}' \
      2>/dev/null || true
  )"
  rm -f "$body"

  [[ "$code" == "200" ]] && return 0
  echo "OpenRouter free router returned HTTP ${code:-unknown}; no route selected from it."
  return 1
}

models=(
  "gemini-3.8-flash" "gemini-3.8-flash" "gemini-3.8-flash"
  "gemini-3.6-flash" "gemini-3.6-flash" "gemini-3.6-flash"
  "gemini-3.5-flash-lite" "gemini-3.5-flash-lite" "gemini-3.5-flash-lite"
  "openrouter/free"
)

keys=(
  "${GEMINI_API_KEY:-}"
  "${GEMINI_API_KEY_2:-}"
  "${GEMINI_API_KEY_3:-}"
)

for ((i=start; i<10; i++)); do
  model="${models[$i]}"

  if (( i < 9 )); then
    slot=$((i % 3))
    key="${keys[$slot]}"
    if [[ -z "$key" ]]; then
      echo "Route $((i+1))/10: Google key slot $((slot+1)) is not configured; skipping."
      continue
    fi

    echo "Route $((i+1))/10: probing Google $model with key slot $((slot+1))..."
    if probe_gemini "$model" "$key"; then
      echo "::add-mask::$key"
      echo "OPENCODE_SELECTED_GEMINI_KEY=$key" >> "$GITHUB_ENV"
      echo "OPENCODE_SELECTED_MODEL=google/$model" >> "$GITHUB_ENV"
      echo "OPENCODE_ROUTE_INDEX=$i" >> "$GITHUB_ENV"
      echo "selected=true" >> "$GITHUB_OUTPUT"
      echo "route=google/$model:key-slot-$((slot+1))" >> "$GITHUB_OUTPUT"
      exit 0
    fi
  else
    echo "Route 10/10: probing OpenRouter free router..."
    if probe_openrouter; then
      echo "::add-mask::$OPENROUTER_API_KEY"
      echo "OPENCODE_SELECTED_GEMINI_KEY=" >> "$GITHUB_ENV"
      echo "OPENCODE_SELECTED_MODEL=openrouter/free" >> "$GITHUB_ENV"
      echo "OPENCODE_ROUTE_INDEX=$i" >> "$GITHUB_ENV"
      echo "selected=true" >> "$GITHUB_OUTPUT"
      echo "route=openrouter/free" >> "$GITHUB_OUTPUT"
      exit 0
    fi
  fi
done

echo "OPENCODE_SELECTED_GEMINI_KEY=" >> "$GITHUB_ENV"
echo "OPENCODE_SELECTED_MODEL=" >> "$GITHUB_ENV"
echo "selected=false" >> "$GITHUB_OUTPUT"
echo "route=none" >> "$GITHUB_OUTPUT"
echo "::warning title=No healthy model route::All configured provider probes failed."
