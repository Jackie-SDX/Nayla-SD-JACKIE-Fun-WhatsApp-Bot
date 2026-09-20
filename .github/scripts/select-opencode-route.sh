#!/usr/bin/env bash
set -euo pipefail

route_index="${OPENCODE_ROUTE_INDEX:-}"
start=0
if [[ "$route_index" =~ ^[0-9]+$ ]]; then
  start=$route_index
fi
retry_current="${OPENCODE_RETRY_CURRENT_ROUTE:-0}"
if [[ "$retry_current" == "1" && "$route_index" =~ ^[0-9]+$ ]]; then
  start="$route_index"
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "OPENCODE_RETRY_CURRENT_ROUTE=0" >> "$GITHUB_ENV"
  fi
fi

excluded=",${OPENCODE_EXCLUDED_PROVIDERS:-},"
models_csv="${OPENCODE_ZEN_FREE_MODELS:-big-pickle,mimo-v2.5-free}"
IFS=',' read -r -a models <<< "$models_csv"

is_free_model() {
  local model="$1"
  [[ "$model" == "big-pickle" || "$model" == *"-free" ]]
}

select_route() {
  local index="$1" provider="$2" model="$3" route="$4"
  echo "Selected route $((index + 1)): $route"
  {
    echo "OPENCODE_SELECTED_MODEL=$model"
    echo "OPENCODE_SELECTED_VARIANT="
    echo "OPENCODE_SELECTED_PROVIDER=$provider"
    echo "OPENCODE_ROUTE_INDEX=$index"
  } >> "$GITHUB_ENV"
  {
    echo "selected=true"
    echo "route=$route"
    echo "provider=$provider"
  } >> "$GITHUB_OUTPUT"
}

if [[ ",$excluded," != *,opencode,* && -n "${OPENCODE_API_KEY:-}" ]]; then
  index=0
  for model in "${models[@]}"; do
    [[ -n "$model" ]] || continue
    if ! is_free_model "$model"; then
      echo "::warning title=Rejected non-free Zen model::Ignoring configured model '$model'."
      continue
    fi
    if (( index < start )); then
      index=$((index + 1))
      continue
    fi
    select_route "$index" opencode "opencode/$model" "opencode/$model"
    exit 0
  done
else
  index=0
  for model in "${models[@]}"; do
    [[ -n "$model" ]] || continue
    is_free_model "$model" && index=$((index + 1))
  done
fi

copilot_index="$index"
if (( start <= copilot_index )) && [[ ",$excluded," != *,github-copilot,* ]] && [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]]; then
  select_route "$copilot_index" github-copilot auto github-copilot/auto
  exit 0
fi

{
  echo "OPENCODE_SELECTED_MODEL="
  echo "OPENCODE_SELECTED_VARIANT="
  echo "OPENCODE_SELECTED_PROVIDER="
} >> "$GITHUB_ENV"
printf 'selected=false\nroute=none\nprovider=none\n' >> "$GITHUB_OUTPUT"
echo "::warning title=No configured agent route::All configured zero-cost routes are exhausted, excluded, or missing credentials."