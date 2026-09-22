#!/usr/bin/env bash
set -euo pipefail

provider="${CURRENT_PROVIDER:-none}"
safe_log="${SAFE_LOG:-}"
excluded="${OPENCODE_EXCLUDED_PROVIDERS:-}"

advance_route() {
  local current="${OPENCODE_ROUTE_INDEX:-0}"
  if [[ "$current" =~ ^[0-9]+$ ]]; then
    printf 'OPENCODE_ROUTE_INDEX=%d\n' "$((10#$current + 1))" >> "$GITHUB_ENV"
  fi
}

if [[ -z "$safe_log" || ! -f "$safe_log" || "$provider" == "none" ]]; then
  echo "No provider failure evidence available for classification."
  exit 0
fi

if grep -Eiq "FreeTierError|free tier can only be used from within OpenCode" "$safe_log"; then
  printf "OPENCODE_ROUTE_HINT=openrouter\n" >> "$GITHUB_ENV"
  echo "OpenCode Zen free-tier context is unavailable; preferring the optional OpenRouter OpenCode lane."
  advance_route
  exit 0
fi

if grep -Eiq '(model[[:space:]_-]*(not[[:space:]_-]*found|unavailable)|not available for account|unknown model|invalid model)' "$safe_log"; then
  suggested="$(grep -Ei 'Did you mean:' "$safe_log" | grep -oE '[A-Za-z0-9][A-Za-z0-9._-]*-free' | head -n 1 || true)"
  if [[ -n "$suggested" ]]; then
    printf "OPENCODE_RECOVERY_MODEL=%s\n" "$suggested" >> "$GITHUB_ENV"
    echo "Provider suggested a free model replacement: $suggested"
  fi
  echo "Failure appears model-specific; advancing to the next untried route."
  advance_route
  exit 0
fi

if ! grep -Eiq '(statusCode:[[:space:]]*(401|403|429|500|502|503|504)\b|HTTP[[:space:]]+(401|403|429|500|502|503|504)\b|FreeTierError|free tier can only be used from within OpenCode|RESOURCE_EXHAUSTED|UNAVAILABLE|quota exceeded|rate[- ]limit|high demand|too many requests)' "$safe_log"; then
  echo "Failure is not classified as provider/account availability failure; advancing to the next route."
  advance_route
  exit 0
fi

case ",$excluded," in
  *,"$provider",*) ;;
  *)
    if [[ -n "$excluded" ]]; then
      excluded="$excluded,$provider"
    else
      excluded="$provider"
    fi
    ;;
esac

printf 'OPENCODE_EXCLUDED_PROVIDERS=%s\n' "$excluded" >> "$GITHUB_ENV"
advance_route
echo "Excluded provider for the remainder of this task: $provider"