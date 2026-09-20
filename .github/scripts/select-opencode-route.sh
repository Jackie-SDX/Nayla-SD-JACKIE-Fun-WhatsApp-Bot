#!/usr/bin/env bash
set -euo pipefail

route_index="$(printenv OPENCODE_ROUTE_INDEX 2>/dev/null || true)"
start=0
if [[ "$route_index" =~ ^[0-9]+$ ]]; then
  start=$((route_index + 1))
fi

excluded_providers="${OPENCODE_EXCLUDED_PROVIDERS:-}"

provider_is_excluded() {
  local provider="$1"
  local item
  IFS=',' read -r -a items <<< "$excluded_providers"
  for item in "${items[@]}"; do
    [[ "$item" == "$provider" ]] && return 0
  done
  return 1
}

select_route() {
  local index="$1"
  local provider="$2"
  local model="$3"
  local key="$4"
  local route="$5"

  echo "Selected route $((index + 1))/27: $route"
  {
    echo "OPENCODE_SELECTED_GEMINI_KEY=$key"
    if [[ "$provider" == "google" ]]; then
      echo "OPENCODE_SELECTED_VARIANT=high"
    else
      echo "OPENCODE_SELECTED_VARIANT="
    fi
    echo "OPENCODE_SELECTED_MODEL=$model"
    echo "OPENCODE_SELECTED_PROVIDER=$provider"
    echo "OPENCODE_ROUTE_INDEX=$index"
  } >> "$GITHUB_ENV"
  {
    echo "selected=true"
    echo "route=$route"
    echo "provider=$provider"
  } >> "$GITHUB_OUTPUT"
  exit 0
}

key1="$(printenv GEMINI_API_KEY 2>/dev/null || true)"
key2="$(printenv GEMINI_API_KEY_2 2>/dev/null || true)"
key3="$(printenv GEMINI_API_KEY_3 2>/dev/null || true)"
key4="$(printenv GEMINI_API_KEY_4 2>/dev/null || true)"
key5="$(printenv GEMINI_API_KEY_5 2>/dev/null || true)"
primary_model="$(printenv OPENROUTER_PRIMARY_MODEL 2>/dev/null || true)"
[[ -n "$primary_model" ]] || primary_model="qwen/qwen3.8-27b:free"

route_count=27
gemini_route_count=25
global_fallback_index=26
keys=("$key1" "$key2" "$key3" "$key4" "$key5")

for ((i=start; i<route_count; i++)); do
  if (( i == 0 )); then
    if provider_is_excluded "openrouter"; then
      echo "Route 1/27: OpenRouter provider excluded by prior provider failure; skipping."
      continue
    fi
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
      echo "Route 1/27: OpenRouter credential is not configured; skipping."
      continue
    fi
    if [[ "$primary_model" != *":free" ]]; then
      echo "Route 1/27: configured OpenRouter primary is not explicitly marked :free; refusing paid activation."
      continue
    fi
    select_route "$i" "openrouter" "openrouter/$primary_model" "" "openrouter/$primary_model"
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
      *) continue ;;
    esac
    key="${keys[$key_index]}"

    if provider_is_excluded "google"; then
      if (( key_index == 0 )); then
        echo "Google provider excluded by prior provider failure; skipping remaining Gemini routes."
      fi
      continue
    fi

    if [[ -z "$key" ]]; then
      echo "Route $((i+1))/$route_count: Gemini key slot $((key_index+1)) is not configured; skipping."
      continue
    fi

    select_route "$i" "google" "google/$model" "$key" "google/$model:key-slot-$((key_index+1))"
  fi

  if (( i == global_fallback_index )); then
    if provider_is_excluded "openrouter"; then
      echo "Route 27/27: OpenRouter provider excluded by prior provider failure; skipping global free router."
      continue
    fi
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
      echo "Route 27/27: OpenRouter credential is not configured; no global free router."
      continue
    fi
    select_route "$i" "openrouter" "openrouter/free" "" "openrouter/free"
  fi
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
  echo "provider=none"
} >> "$GITHUB_OUTPUT"
echo "::warning title=No configured model route::All configured zero-cost routes are exhausted or excluded by observed provider failures."
exit 0
