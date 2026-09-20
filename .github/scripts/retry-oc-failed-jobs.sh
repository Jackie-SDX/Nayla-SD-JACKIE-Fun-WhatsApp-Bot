#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?}"
event_file="${GITHUB_EVENT_PATH:?}"
target="$(jq -r '.issue.number // .pull_request.number // 0' "$event_file")"
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 1

comments="$(gh api "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null || true)"
run_id="$(printf '%s' "$comments" | jq -r '[.[] | select((.body // "") | test("<!-- oc-run-id:[0-9]+ issue:"))] | sort_by(.created_at) | last | (.body // "") | capture("oc-run-id:(?<id>[0-9]+)").id // empty')"

if [[ -z "$run_id" ]]; then
  gh issue comment "$target" --body 
  exit 0
fi

run="$(gh api "/repos/$repo/actions/runs/$run_id")"
name="$(jq -r '.name // ""' <<<"$run")"
status="$(jq -r '.status // ""' <<<"$run")"
conclusion="$(jq -r '.conclusion // ""' <<<"$run")"

if [[ "$name" != "opencode" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRegistered run #$run_id is not the opencode workflow ($name). No rerun issued."
  exit 0
fi

if [[ "$conclusion" == "timed_out" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id timed out. Use /oc continue to resume from the durable checkpoint."
  exit 0
fi

if [[ "$status" != "completed" || "$conclusion" != "failure" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id is $status / $conclusion. No rerun issued."
  exit 0
fi

jobs="$(gh api "/repos/$repo/actions/runs/$run_id/jobs?per_page=100&filter=latest")"
failed="$(jq '[.jobs[] | select(.conclusion == "failure")] | length' <<<"$jobs")"
if [[ "$failed" -eq 0 ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id is marked failed, but no failed job is present in the latest attempt. No rerun issued."
  exit 0
fi

gh api -X POST "/repos/$repo/actions/runs/$run_id/rerun-failed-jobs" >/dev/null
gh issue comment "$target" --body "## /oc retry failed jobs\n\nReran $failed failed job(s) from OpenCode run #$run_id. This was a selective Actions rerun; no new AI task was started."## /oc retry failed jobs\n\nNo registered prior /oc run was found for this issue. Refusing to guess at an unrelated Actions run.'
  exit 0
fi

run="$(gh api "/repos/$repo/actions/runs/$run_id")"
name="$(jq -r '.name // ""' <<<"$run")"
status="$(jq -r '.status // ""' <<<"$run")"
conclusion="$(jq -r '.conclusion // ""' <<<"$run")"

if [[ "$name" != "opencode" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRegistered run #$run_id is not the opencode workflow ($name). No rerun issued."
  exit 0
fi

if [[ "$conclusion" == "timed_out" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id timed out. Use /oc continue to resume from the durable checkpoint."
  exit 0
fi

if [[ "$status" != "completed" || "$conclusion" != "failure" ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id is $status / $conclusion. No rerun issued."
  exit 0
fi

jobs="$(gh api "/repos/$repo/actions/runs/$run_id/jobs?per_page=100&filter=latest")"
failed="$(jq '[.jobs[] | select(.conclusion == "failure")] | length' <<<"$jobs")"
if [[ "$failed" -eq 0 ]]; then
  gh issue comment "$target" --body "## /oc retry failed jobs\n\nRun #$run_id is marked failed, but no failed job is present in the latest attempt. No rerun issued."
  exit 0
fi

gh api -X POST "/repos/$repo/actions/runs/$run_id/rerun-failed-jobs" >/dev/null
gh issue comment "$target" --body "## /oc retry failed jobs\n\nReran $failed failed job(s) from OpenCode run #$run_id. This was a selective Actions rerun; no new AI task was started."