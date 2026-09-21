#!/usr/bin/env bash
set -euo pipefail

disable_composio_mcp() {
  echo "::warning title=Composio optional integration unavailable::COMPOSIO_API_KEY is not configured; continuing without Composio MCP."
  printf 'COMPOSIO_MCP_URL=\n' >> "$GITHUB_ENV"
  printf 'COMPOSIO_MCP_HEADERS_FILE=\n' >> "$GITHUB_ENV"
  printf 'COMPOSIO_MCP_ENABLED=false\n' >> "$GITHUB_ENV"
}


fail_composio_mcp() {
  echo "::warning title=Composio MCP unavailable::Session-backed Composio MCP could not be established; continuing without Composio tools."
  printf '%s\n' 'COMPOSIO_MCP_URL=' >> "$GITHUB_ENV"
  printf '%s\n' 'COMPOSIO_MCP_HEADERS_FILE=' >> "$GITHUB_ENV"
  printf '%s\n' 'COMPOSIO_MCP_ENABLED=false' >> "$GITHUB_ENV"
  return 0
}
if [[ -z "${COMPOSIO_API_KEY:-}" ]]; then
  disable_composio_mcp
  exit 0
fi

response="$(mktemp "${RUNNER_TEMP:-/tmp}/composio-session.XXXXXX.json")"

resolved_user_id="${COMPOSIO_USER_ID:-}"
[[ -n "$resolved_user_id" ]] || {
  echo "::warning title=Composio user ID missing::COMPOSIO_USER_ID is not configured; continuing without Composio MCP."
  fail_composio_mcp
  exit 0
}
payload="$(jq -cn --arg user_id "$resolved_user_id" '{user_id:$user_id,mcp:true}')"

if ! curl -fsSL --retry 3 --retry-all-errors --connect-timeout 5 --max-time 20 \
  -X POST "https://backend.composio.dev/api/v3.1/tool_router/session" \
  -H "x-api-key: $COMPOSIO_API_KEY" \
  -H "Content-Type: application/json" \
  --data "$payload" -o "$response"; then
  fail_composio_mcp
  exit 0
fi

session_id="$(jq -er '.session_id // empty' "$response")" || {
  fail_composio_mcp
  exit 0
}
mcp_url="$(jq -er '.mcp.url // empty' "$response")" || {
  fail_composio_mcp
  exit 0
}
headers="$(jq -ec '.mcp.headers // {} | if type == "object" then . else error("mcp.headers is not an object") end' "$response")" || {
  fail_composio_mcp
  exit 0
}

headers_file="$(mktemp "${RUNNER_TEMP:-/tmp}/composio-mcp-headers.XXXXXX")"
chmod 600 "$headers_file"
printf 'x-api-key: %s\n' "$COMPOSIO_API_KEY" > "$headers_file"
jq -r 'to_entries[] | select((.key | ascii_downcase) != "x-api-key") | "\(.key): \(.value)"' <<<"$headers" >> "$headers_file"

[[ "$mcp_url" =~ ^https://(app|backend)\.composio\.dev/tool_router/(v[0-9]+/)?[^/]+/mcp$ ]] || {
  echo "::warning title=Unexpected Composio MCP endpoint::Refusing an MCP URL outside Composio's hosted Tool Router domain."
  fail_composio_mcp
  exit 0
}

echo "::add-mask::$session_id"
echo "::add-mask::$mcp_url"
printf 'COMPOSIO_MCP_URL=%s\n' "$mcp_url" >> "$GITHUB_ENV"
printf 'COMPOSIO_MCP_HEADERS_FILE=%s\n' "$headers_file" >> "$GITHUB_ENV"
printf 'COMPOSIO_MCP_ENABLED=true\n' >> "$GITHUB_ENV"
printf 'session_id=%s\n' "$session_id" >> "$GITHUB_OUTPUT"
printf 'headers_file=%s\n' "$headers_file" >> "$GITHUB_OUTPUT"

if ! npx --yes --package="mcp-remote@0.14.2" mcp-remote --help >/dev/null; then
  echo "::warning title=MCP bridge unavailable::Pinned mcp-remote@0.14.2 could not be installed/started; continuing without Composio tools."
  fail_composio_mcp
  exit 0
fi

echo "Composio session-backed MCP endpoint and pinned stdio bridge prepared."
