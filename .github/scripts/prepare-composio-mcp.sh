#!/usr/bin/env bash
set -euo pipefail

disable_composio_mcp() {
  echo "::warning title=Composio optional integration unavailable::COMPOSIO_API_KEY is not configured; continuing without Composio MCP."
  printf 'COMPOSIO_MCP_URL=\n' >> "$GITHUB_ENV"
  {
    echo 'OPENCODE_CONFIG_CONTENT<<COMPOSIO_CONFIG_EOF'
    echo '{"mcp":{"composio":{"type":"remote","enabled":false}}}'
    echo 'COMPOSIO_CONFIG_EOF'
  } >> "$GITHUB_ENV"
}


fail_composio_mcp() {
  echo "::error title=Composio MCP bootstrap failed::COMPOSIO_API_KEY is configured but the session-backed MCP endpoint could not be established or validated."
  exit 1
}
if [[ -z "${COMPOSIO_API_KEY:-}" ]]; then
  disable_composio_mcp
  exit 0
fi

response="$(mktemp "${RUNNER_TEMP:-/tmp}/composio-session.XXXXXX.json")"
trap 'rm -f "$response"' EXIT

payload="$(jq -cn --arg user_id "${COMPOSIO_USER_ID:-github-actions}" '{user_id:$user_id,mcp:true}')"

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

[[ "$mcp_url" =~ ^https://backend\.composio\.dev/tool_router/[^/]+/mcp$ ]] || {
  echo "::warning title=Unexpected Composio MCP endpoint::Refusing an MCP URL outside Composio's hosted Tool Router domain."
  fail_composio_mcp
  exit 0
}

config="$(jq -cn --arg url "$mcp_url" --argjson headers "$headers" '
  {mcp:{composio:{type:"remote",url:$url,enabled:true,oauth:false,headers:$headers}}}
')"

printf 'COMPOSIO_MCP_URL=%s\n' "$mcp_url" >> "$GITHUB_ENV"
{
  echo 'OPENCODE_CONFIG_CONTENT<<COMPOSIO_CONFIG_EOF'
  echo "$config"
  echo 'COMPOSIO_CONFIG_EOF'
} >> "$GITHUB_ENV"
printf 'session_id=%s\n' "$session_id" >> "$GITHUB_OUTPUT"
echo "Composio session-backed MCP endpoint prepared."
