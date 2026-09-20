#!/usr/bin/env bash
set -euo pipefail

provider="${CURRENT_PROVIDER:-none}"
safe_log="${SAFE_LOG:-}"
excluded="${OPENCODE_EXCLUDED_PROVIDERS:-}"

if [[ -z "$safe_log" || ! -f "$safe_log" || "$provider" == "none" ]]; then
  echo "No provider failure evidence available for classification."
  exit 0
fi

if grep -Eiq '(model[[:space:]_-]*(not[[:space:]_-]*found|unavailable)|not available for account|unknown model|invalid model)' "$safe_log"; then
  echo "Failure appears model-specific; preserving the provider for the next untried Zen model."
  exit 0
fi

if ! grep -Eiq '(statusCode:[[:space:]]*(401|403|429|500|502|503|504)\b|HTTP[[:space:]]+(401|403|429|500|502|503|504)\b|FreeTierError|free tier can only be used from within OpenCode|RESOURCE_EXHAUSTED|UNAVAILABLE|quota exceeded|rate[- ]limit|high demand|too many requests)' "$safe_log"; then
  echo "Failure is not classified as provider/account availability failure; preserving cross-route failover."
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
echo "Excluded provider for the remainder of this task: $provider"