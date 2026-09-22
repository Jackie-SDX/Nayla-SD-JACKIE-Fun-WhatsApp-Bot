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
rm -f "$tmp/comment"
printf '%s\n' 'story response without PR publication' > "$tmp/opencode-final-response-1.md"
export A1=success P1=not-requested V1=false PR1= SHA1= TASK_MODE=code
bash "$root/.github/scripts/post-oc-result.sh"
body="$(cat "$tmp/comment")"
grep -Fq 'story response without PR publication' <<<"$body"
! grep -Fq 'Publication was not requested' <<<"$body"
! grep -Fq 'tail -n 160 "$REPORT_LOG"' "$root/.github/workflows/opencode.yml"
! grep -Fq 'safe_tail="$(gh run view' "$root/.github/scripts/verify-agent-result.sh"
! grep -Fq 'Sanitized failure evidence:' "$root/.github/scripts/verify-agent-result.sh"
grep -Fq 'Mark triggering /oc comment as running' "$root/.github/workflows/opencode.yml"
grep -Fq 'Clear /oc running reaction' "$root/.github/workflows/opencode.yml"
grep -Fq 'message.part.updated' "$root/.opencode/plugins/agentic-observability.js"
! grep -Fq 'status " + safe(event.properties?.status' "$root/.opencode/plugins/agentic-observability.js"
grep -Fq 'retrying the same peer prompt without a custom-agent callback' "$root/.github/scripts/invite-copilot-peer.sh"
grep -Fq 'OC_PUBLISH_REQUESTED:-' "$root/.github/scripts/run-attempt-pipeline.sh"
cat > "$tmp/event-content.json" <<'JSON'
{"comment":{"id":9,"body":"/oc Continue the lighthouse story with Parts 4 and 5 written by Copilot as co-author, then Part 6 by OpenCode. Do not modify the repository."},"issue":{"number":9}}
JSON
: > "$tmp/env-content"
: > "$tmp/out-content"
GITHUB_EVENT_PATH="$tmp/event-content.json" GITHUB_ENV="$tmp/env-content" GITHUB_OUTPUT="$tmp/out-content" bash "$root/.github/scripts/select-oc-task-mode.sh"
grep -Fq 'OC_TASK_MODE=report' "$tmp/env-content"
grep -Fq 'OC_CONTENT_TASK=true' "$tmp/env-content"
grep -Fq 'OC_COPILOT_COLLAB_REQUESTED=true' "$tmp/env-content"

cat > "$tmp/event-code.json" <<'JSON'
{"comment":{"id":10,"body":"/oc Fix the workflow bug and add a regression test. Do not create a PR yet."},"issue":{"number":10}}
JSON
: > "$tmp/env-code"
: > "$tmp/out-code"
GITHUB_EVENT_PATH="$tmp/event-code.json" GITHUB_ENV="$tmp/env-code" GITHUB_OUTPUT="$tmp/out-code" bash "$root/.github/scripts/select-oc-task-mode.sh"
grep -Fq 'OC_TASK_MODE=code' "$tmp/env-code"
grep -Fq 'OC_CONTENT_TASK=false' "$tmp/env-code"

bash -n "$root/.github/scripts/claim-oc-command.sh"
grep -Fq 'needs: oc_claim' "$root/.github/workflows/opencode.yml"
grep -Fq 'claim-oc-command.sh' "$root/.github/workflows/opencode.yml"
grep -Fq 'peer_mode' "$root/.github/scripts/invite-copilot-peer.sh"
grep -Fq 'writer_output_file' "$root/.github/scripts/invite-copilot-peer.sh"
grep -Fq 'OC_COPILOT_COLLAB_REQUESTED' "$root/.github/scripts/run-opencode-attempt.sh"
echo 'oc communication/reaction contract: OK'