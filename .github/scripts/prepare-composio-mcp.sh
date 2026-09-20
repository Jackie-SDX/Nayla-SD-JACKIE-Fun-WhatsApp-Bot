#!/usr/bin/env bash
set -euo pipefail

disable_composio_mcp() {
  echo "::warning title=Composio optional integration unavailable::COMPOSIO_API_KEY is not configured; continuing without Composio MCP."
  printf 'COMPOSIO_MCP_URL=\n' >> "$GITHUB_ENV"
  printf 'COMPOSIO_MCP_HEADERS_FILE=\n' >> "$GITHUB_ENV"
  {
    echo 'OPENCODE_CONFIG_CONTENT<<COMPOSIO_CONFIG_EOF'
    echo '{"mcp":{"composio":{"type":"local","enabled":false}}}'
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

requested_user_id="${COMPOSIO_USER_ID:-}"
active_accounts="$(mktemp "${RUNNER_TEMP:-/tmp}/composio-active-accounts.XXXXXX.json")"
headers_file=""
trap 'rm -f "$response" "$active_accounts" "$headers_file" 2>/dev/null || true' EXIT

if ! curl -fsSL --retry 3 --retry-all-errors --connect-timeout 5 --max-time 20 \
  --get "https://backend.composio.dev/api/v3.1/connected_accounts" \
  --data-urlencode "toolkit_slugs=tavily_mcp" \
  --data-urlencode "statuses=ACTIVE" \
  --data-urlencode "account_type=ALL" \
  --data-urlencode "limit=100" \
  -H "x-api-key: $COMPOSIO_API_KEY" -o "$active_accounts"; then
  fail_composio_mcp
fi

if [[ -n "$requested_user_id" ]]; then
  matching_count="$(jq --arg uid "$requested_user_id" '[.items[] | select(.status == "ACTIVE" and .user_id == $uid)] | length' "$active_accounts")"
  if [[ "$matching_count" -eq 0 ]]; then
    requested_user_id=""
  fi
fi

if [[ -z "$requested_user_id" ]]; then
  user_candidates="$(jq -r '[.items[] | select(.status == "ACTIVE" and (.user_id // "") != "") | .user_id] | unique | .[]' "$active_accounts")"
  user_count="$(printf '%s\n' "$user_candidates" | sed '/^$/d' | wc -l | tr -d ' ')"
  [[ "$user_count" -eq 1 ]] || {
    echo "::error title=Ambiguous Composio user::The project has zero or multiple active Tavily users. Set COMPOSIO_USER_ID to the intended Composio app user ID."
    fail_composio_mcp
  }
  resolved_user_id="$user_candidates"
else
  resolved_user_id="$requested_user_id"
fi

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
jq -r 'to_entries[] | "\(.key): \(.value)"' <<<"$headers" > "$headers_file"

[[ "$mcp_url" =~ ^https://backend\.composio\.dev/tool_router/[^/]+/mcp$ ]] || {
  echo "::warning title=Unexpected Composio MCP endpoint::Refusing an MCP URL outside Composio's hosted Tool Router domain."
  fail_composio_mcp
  exit 0
}

config="$(jq -cn --arg url "$mcp_url" --argjson headers "$headers" '
  {mcp:{composio:{type:"remote",url:$url,enabled:true,oauth:false,headers:$headers}}}
')"

printf 'COMPOSIO_MCP_URL=%s\n' "$mcp_url" >> "$GITHUB_ENV"
printf 'COMPOSIO_MCP_HEADERS_FILE=%s\n' "$headers_file" >> "$GITHUB_ENV"
{
  echo 'OPENCODE_CONFIG_CONTENT<<COMPOSIO_CONFIG_EOF'
  echo "$config"
  echo 'COMPOSIO_CONFIG_EOF'
} >> "$GITHUB_ENV"
printf 'session_id=%s\n' "$session_id" >> "$GITHUB_OUTPUT"
printf 'headers_file=%s\n' "$headers_file" >> "$GITHUB_OUTPUT"

if ! npx --yes --package="mcp-remote@0.14.2" mcp-remote --help >/dev/null; then
  echo "::error title=MCP bridge unavailable::Pinned mcp-remote@0.14.2 could not be installed/started."
  fail_composio_mcp
fi

echo "Composio session-backed MCP endpoint and pinned stdio bridge prepared."
