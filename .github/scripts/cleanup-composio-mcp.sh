#!/usr/bin/env bash
set -euo pipefail

session_id="${SESSION_ID:-}"
if [[ -z "$session_id" || -z "${COMPOSIO_API_KEY:-}" ]]; then
  exit 0
fi

if curl -fsSL --retry 3 --retry-all-errors --connect-timeout 5 --max-time 20 \
  -X DELETE "https://backend.composio.dev/api/v3.1/tool_router/session/$session_id" \
  -H "x-api-key: $COMPOSIO_API_KEY" >/dev/null; then
  echo "Composio session cleaned up."
else
  echo "::warning title=Composio session cleanup::The short-lived Composio session could not be deleted; no credential was printed."
fi
