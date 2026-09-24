#!/usr/bin/env bash
set -euo pipefail

route_index="${OPENCODE_ROUTE_INDEX:-}"

if [[ "$(printenv OC_MERGE_REQUESTED 2>/dev/null || printf false)" == "true" ]]; then
  echo "selected=false" >> "$GITHUB_OUTPUT"
  echo "provider=none" >> "$GITHUB_OUTPUT"
  echo "route=merge" >> "$GITHUB_OUTPUT"
  echo "Skipping agent routing for explicit merge request."
  exit 0
fi
start=0
if [[ "$route_index" =~ ^[0-9]+$ ]]; then
  start=$route_index
fi
retry_current="${OPENCODE_RETRY_CURRENT_ROUTE:-0}"
advance_route="${OPENCODE_ADVANCE_ROUTE:-0}"
if [[ "$route_index" =~ ^[0-9]+$ ]] && [[ "$retry_current" == "1" || "$advance_route" == "1" ]]; then
  start=$((10#$route_index + 1))
  if [[ -n "$GITHUB_ENV" ]]; then
    {
      echo "OPENCODE_RETRY_CURRENT_ROUTE=0"
      echo "OPENCODE_ADVANCE_ROUTE=0"
    } >> "$GITHUB_ENV"
  fi
fi

excluded=",${OPENCODE_EXCLUDED_PROVIDERS:-},"
models_csv="${OPENCODE_ZEN_FREE_MODELS:-big-pickle,mimo-v2.6-flash-free}"
recovery_model="${OPENCODE_RECOVERY_MODEL:-}"
route_hint="${OPENCODE_ROUTE_HINT:-}"
IFS=',' read -r -a models <<< "$models_csv"

# Keep the requested primary/secondary stable even when the workflow's historical
# CSV default is older. Additional discovered/configured free models remain in
# their existing order after the preferred pair.
preferred_models=("mimo-v2.6-flash-free" "big-pickle")
ordered_models=()
for preferred in "${preferred_models[@]}"; do
  for candidate in "${models[@]}"; do
    if [[ "$candidate" == "$preferred" ]]; then
      ordered_models+=( "$candidate" )
      break
    fi
  done
done
for candidate in "${models[@]}"; do
  [[ -n "$candidate" ]] || continue
  seen=false
  for existing in "${ordered_models[@]}"; do
    [[ "$candidate" == "$existing" ]] && { seen=true; break; }
  done
  [[ "$seen" == "true" ]] || ordered_models+=( "$candidate" )
done
models=( "${ordered_models[@]}" )

refresh_free_models() {
  local catalog line model base found_any=false
  command -v opencode >/dev/null 2>&1 || return 0
  catalog="$(opencode models opencode 2>/dev/null || true)"
  while IFS= read -r line; do
    case "$line" in
      opencode/*)
        model="${line#opencode/}"
        if [[ "$model" == "big-pickle" || "$model" == *"-free" ]]; then
          found_any=true
          if ! printf '%s\n' "${models[@]}" | grep -Fxq "$model"; then
            models+=( "$model" )
          fi
        fi
        ;;
    esac
  done <<< "$catalog"

  if [[ "$found_any" != "true" ]]; then
    catalog="$(opencode models --refresh 2>/dev/null || true)"
    while IFS= read -r line; do
      case "$line" in
        opencode/*)
          model="${line#opencode/}"
          if [[ "$model" == "big-pickle" || "$model" == *"-free" ]]; then
            if ! printf '%s\n' "${models[@]}" | grep -Fxq "$model"; then
              models+=( "$model" )
            fi
          fi
          ;;
      esac
    done <<< "$catalog"
  fi
}

refresh_free_models

is_free_model() {
  local model="$1"
  [[ "$model" == "big-pickle" || "$model" == *"-free" ]]
}

# Emits the base names of models remembered as broken (model=unix_epoch CSV in
# OPENCODE_BAD_MODELS), dropping entries older than
# OPENCODE_BAD_MODELS_MAX_AGE_HOURS so a temporarily-broken model can recover
# without manual edits. Only the base name (e.g. "big-pickle") is compared; the
# selected model keeps its real ladder index so retry/advance math is unchanged.
bad_models() {
  local bad_csv="${OPENCODE_BAD_MODELS:-}"
  local max_age_hours="${OPENCODE_BAD_MODELS_MAX_AGE_HOURS:-24}"
  [[ "$max_age_hours" =~ ^[0-9]+$ ]] || max_age_hours=24
  local now
  now="$(date +%s)"
  if [[ -n "$bad_csv" ]]; then
    local entry name ts age_seconds max_seconds
    max_seconds=$((max_age_hours * 3600))
    while IFS=',' read -r entry; do
      [[ -n "$entry" ]] || continue
      name="${entry%%=*}"
      ts="${entry#*=}"
      [[ "$ts" =~ ^[0-9]+$ ]] || continue
      age_seconds=$((now - 10#$ts))
      if (( age_seconds >= 0 && age_seconds < max_seconds )); then
        printf '%s\n' "$name"
      fi
    done <<< "$bad_csv"
  fi
}

is_bad_model() {
  local model="$1"
  bad_models | grep -qx "$model"
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
    # Only a fresh selection (start == 0) consults model memory: an explicit
    # retry or advance should still be able to target a formerly-bad model.
    if [[ "$start" == "0" ]] && is_bad_model "$model"; then
      echo "Skipping remembered-bad free Zen model '$model' for this task."
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

# A Zen free-tier context rejection is provider-level. Prefer the next
# OpenCode runtime through OpenRouter when explicitly hinted.
# Provider/model error recovery: use a provider-suggested free model once on the next route.
if [[ -n "$recovery_model" && "$start" -gt 0 && "$recovery_model" == *"-free" &&
      "$recovery_model" != "${OPENCODE_SELECTED_MODEL##*/}" && -n "${OPENCODE_API_KEY:-}" && ",$excluded," != *,opencode,* ]]; then
  select_route "$start" opencode "opencode/$recovery_model" "opencode/$recovery_model"
  if [[ -n "$GITHUB_ENV" ]]; then echo "OPENCODE_RECOVERY_MODEL=" >> "$GITHUB_ENV"; fi
  exit 0
fi

if (( start <= openrouter_index )) && [[ -n "${OPENROUTER_API_KEY:-}" && ",$excluded," != *,openrouter,* ]] && [[ "$route_hint" == "openrouter" || ",$excluded," == *,opencode,* || -z "${OPENCODE_API_KEY:-}" || "$start" == "$openrouter_index" ]]; then
  select_route "$openrouter_index" openrouter "openrouter/openrouter/free" "openrouter/openrouter/free"
  if [[ -n "$GITHUB_ENV" ]]; then
    echo "OPENCODE_ROUTE_HINT=" >> "$GITHUB_ENV"
  fi
  exit 0
fi

openrouter_index="$index"
copilot_index="$((index + 1))"
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