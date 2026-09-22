#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"
cat > "$bin/gh" <<'FAKEGH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api user --jq .login") printf '%s\n' github-actions[bot] ;;
  *"/reactions?per_page=100"*) printf '%s\n' '[]' ;;
  *"--method POST"*"/reactions"*) printf '%s\n' '123' ;;
  *"--method DELETE"*"/reactions/123"*) exit 0 ;;
  *"/issues/7/comments?per_page=100"*) printf '%s\n' '[[]]' ;;
  "issue comment"*) printf '%s\n' "$*" > "$GH_COMMENT_FILE" ;;
  *) exit 0 ;;
esac
FAKEGH
chmod +x "$bin/gh"
export PATH="$bin:$PATH"
export GITHUB_REPOSITORY=fixture/repo GITHUB_EVENT_NAME=issue_comment RUNNER_TEMP="$tmp" GH_COMMENT_FILE="$tmp/comment" RUN_ID=424242
cat > "$tmp/event.json" <<'JSON'
{"comment":{"id":7},"issue":{"number":7}}
JSON
export GITHUB_EVENT_PATH="$tmp/event.json" GITHUB_RUN_ID=424242
bash "$root/.github/scripts/oc-running-reaction.sh" add >"$tmp/add"
grep -Fq 'Added /oc running reaction 123.' "$tmp/add"
[[ "$(cat "$tmp/oc-running-reaction.state")" == 123 ]]
bash "$root/.github/scripts/oc-running-reaction.sh" remove >"$tmp/remove"
[[ ! -e "$tmp/oc-running-reaction.state" ]]
bash -n "$root/.github/scripts/oc-running-reaction.sh"
bash -n "$root/.github/scripts/post-oc-result.sh"
bash -n "$root/.github/scripts/invite-copilot-peer.sh"
node --check "$root/.opencode/plugins/agentic-observability.js"
printf '%s\n' 'clean final answer' > "$tmp/opencode-final-response-1.md"
export A1=success P1=report-only V1=false PR1= SHA1= TASK_MODE=report
bash "$root/.github/scripts/post-oc-result.sh"
body="$(cat "$tmp/comment")"
grep -Fq 'clean final answer' <<<"$body"
! grep -Fq '[object Object]' <<<"$body"
! grep -Fq '[OPENCODE]' <<<"$body"
! grep -Fq 'tail -n 160 "$REPORT_LOG"' "$root/.github/workflows/opencode.yml"
grep -Fq 'Mark triggering /oc comment as running' "$root/.github/workflows/opencode.yml"
grep -Fq 'Clear /oc running reaction' "$root/.github/workflows/opencode.yml"
grep -Fq 'message.part.updated' "$root/.opencode/plugins/agentic-observability.js"
! grep -Fq 'status " + safe(event.properties?.status' "$root/.opencode/plugins/agentic-observability.js"
grep -Fq 'retrying the same peer prompt without a custom-agent callback' "$root/.github/scripts/invite-copilot-peer.sh"
echo 'oc communication/reaction contract: OK'