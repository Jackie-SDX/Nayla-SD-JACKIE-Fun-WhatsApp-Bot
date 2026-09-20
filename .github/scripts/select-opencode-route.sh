#!/usr/bin/env bash
set -euo pipefail

route_index="${OPENCODE_ROUTE_INDEX:-}"
start=0
if [[ "$route_index" =~ ^[0-9]+$ ]]; then
  start=$((route_index + 1))
fi

excluded=",${OPENCODE_EXCLUDED_PROVIDERS:-},"

# OpenCode Zen free models are not valid direct inference routes from GitHub Actions.
# CI only uses an explicitly configured OpenCode model; otherwise it falls back to Copilot.
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
  models_csv="${OPENCODE_CI_MODELS:-}"
else
  models_csv="${OPENCODE_ZEN_FREE_MODELS:-big-pickle,mimo-v2.5-free}"
fi
IFS=',' read -r -a models <<< "$models_csv"

opencode_available="${HAS_OPENCODE_CREDENTIAL:-}"
copilot_available="${HAS_COPILOT_CREDENTIAL:-}"

if [[ -z "$opencode_available" ]]; then
  [[ -n "${OPENCODE_API_KEY:-}" ]] && opencode_available=true || opencode_available=false
fi
if [[ -z "$copilot_available" ]]; then
  [[ -n "${COPILOT_GITHUB_TOKEN:-}" ]] && copilot_available=true || copilot_available=false
fi

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

if [[ ",$excluded," != *,opencode,* && "$opencode_available" == "true" ]]; then
  if [[ "${GITHUB_ACTIONS:-false}" == "true" && -z "$models_cv" ]]; then
    echo "::notice title=OpenCode CI model not configured::Skipping OpenCode Zen free models in GitHub Actions; configure OPENCODE_CI_MODELSs with a CI-supported OpenCode model to enable the OpenCode route."
  fi
  index=0
  for model in "${models[@]}"; do
    [[ -n "$model" ]] || continue
    if [[ "${GITHUB_ACTIONS:-false}" == "true" && -z "${OPENCODE_CI_MODELS:-}" ]] && is_free_model "$model"; then
      continue
    fi
    if [[ "${GITHUB_ACTIONS:-false}" != "true" ]] && ! is_free_model "$model"; then
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
if (( start <= copilot_index )) && [[ ",$excluded," != *,github-copilot,* ]] && [[ "$copilot_available" == "true" ]]; then
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
