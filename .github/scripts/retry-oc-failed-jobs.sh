#!/usr/bin/env bash
set -euo pipefail
repo="$GITHUB_REPOSITORY"
event_file="$GITHUB_EVENT_PATH"
target="$(jq -r '.issue.number // .pull_request.number // 0' "$event_file")"
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0
comments="$(gh api --paginate --slurp "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null | jq 'add // []' 2>/dev/null || printf '%s' '[]')"
marker="$(jq -r '[.[] | select((.body // "") | test("<!-- oc-run-id:[0-9]+ issue:"; ""))] | sort_by(.created_at) | last | (.body // "")' <<<"$comments")"
run_id="$(sed -nE 's/.*<!-- oc-run-id:([0-9]+) issue:[0-9]+ sha:[^>]+-->.*/\1/p' <<<"$marker" | head -n 1)"
if [[ -z "$run_id" ]]; then
  gh issue comment "$target" --body $'## /oc retry failed jobs

No registered prior /oc run was found for this issue. Refusing to guess at an unrelated Actions run.'
  exit 0
fi
run="$(gh api "/repos/$repo/actions/runs/$run_id")"
name="$(jq -r '.name // ""' <<<"$run")"
status="$(jq -r '.status // ""' <<<"$run")"
conclusion="$(jq -r '.conclusion // ""' <<<"$run")"
attempt="$(jq -r '.run_attempt // 1' <<<"$run")"
if [[ "$name" != "opencode" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs"$'

'"Registered run #$run_id is not the opencode workflow ($name). No rerun issued."
  exit 0
fi
if [[ "$conclusion" == "timed_out" || "$conclusion" == "cancelled" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs"$'

'"Run #$run_id is $conclusion. Use /oc continue to resume from the durable checkpoint; no blind rerun was issued."
  exit 0
fi
display_conclusion="$conclusion"; [[ -n "$display_conclusion" ]] || display_conclusion=pending
if [[ "$status" != "completed" || "$conclusion" != "failure" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs"$'

'"Run #$run_id is $status / $display_conclusion. No rerun issued."
  exit 0
fi
last_retry_attempt="$(jq -r --arg run_id "$run_id" '[.[] | select((.body // "") | contains("<!-- oc-retry-run-id:" + $run_id + " "))] | sort_by(.created_at) | last | (.body // "")' <<<"$comments")"
last_attempt="$(sed -nE 's/.*<!-- oc-retry-run-id:[0-9]+ attempt:([0-9]+) -->.*/\1/p' <<<"$last_retry_attempt" | head -n 1)"
if [[ -n "$last_attempt" && "$last_attempt" == "$attempt" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs"$'

'"Run #$run_id attempt #$attempt has already received a selective failed-job rerun. Refusing to duplicate the same recovery action."
  exit 0
fi
jobs="$(gh api "/repos/$repo/actions/runs/$run_id/jobs?per_page=100&filter=latest")"
failed="$(jq '[.jobs[] | select(.conclusion == "failure")] | length' <<<"$jobs")"
if [[ "$failed" -eq 0 ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs"$'

'"Run #$run_id is marked failed, but no failed job is present in the latest attempt. No rerun issued."
  exit 0
fi
gh api -X POST "/repos/$repo/actions/runs/$run_id/rerun-failed-jobs" >/dev/null
gh issue comment "$target" --body "<!-- oc-retry-run-id:$run_id attempt:$attempt -->"$'

'"## /oc retry failed jobs"$'

'"Reran $failed failed job(s) from OpenCode run #$run_id (attempt #$attempt). This was a selective Actions rerun; no new AI task was started."
