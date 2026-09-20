#!/usr/bin/env bash
set -euo pipefail

provider="${CURRENT_PROVIDER:-none}"
safe_log="${SAFE_LOG:-}"
excluded="${OPENCODE_EXCLUDED_PROVIDERS:-}"

if [[ -z "$safe_log" || ! -f "$safe_log" || "$provider" == "none" ]]; then
  echo "No provider failure evidence available for classification."
  exit 0
fi

if ! grep -Eiq \
  '(statusCode:[[:space:]]*(401|403|429|500|502|503|504)\b|HTTP[[:space:]]+(401|403|429|500|502|503|504)\b|RESOURCE_EXHAUSTED|UNAVAILABLE|quota exceeded|rate[- ]limit|high demand)' \
  "$safe_log"; then
  echo "Failure is not classified as a provider/account availability failure; preserving cross-provider failover."
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
echo "Excluded provider for the remainder of this task after observed provider availability/rate-limit failure: $provider"
