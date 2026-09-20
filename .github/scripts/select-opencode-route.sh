#!/usr/bin/env bash
set -euo pipefail

route_index="$(printenv OPENCODE_ROUTE_INDEX 2>/dev/null || true)"
if [[ "$route_index" =~ ^[0-9]+$ && "$route_index" -ge 0 ]]; then
  echo "::warning title=No additional model route::The GitHub Copilot route has already been attempted for this task."
  printf 'selected=false\nroute=none\nprovider=none\n' >> "$GITHUB_OUTPUT"
  exit 0
fi

if [[ -z "${COPILOT_GITHUB_TOKEN:-}" ]]; then
  echo "Route 1/1: GitHub Copilot credential is not configured; skipping."
  printf 'selected=false\nroute=none\nprovider=none\n' >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Selected route 1/1: github-copilot/auto"
{
  echo "OPENCODE_SELECTED_MODEL=auto"
  echo "OPENCODE_SELECTED_PROVIDER=github-copilot"
  echo "OPENCODE_SELECTED_VARIANT="
  echo "OPENCODE_ROUTE_INDEX=0"
} >> "$GITHUB_ENV"
{
  echo "selected=true"
  echo "route=github-copilot/auto"
  echo "provider=github-copilot"
} >> "$GITHUB_OUTPUT"
