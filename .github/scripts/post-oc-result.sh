#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
target=0
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  target="$(jq -r '.issue.number // .pull_request.number // 0' "$GITHUB_EVENT_PATH" 2>/dev/null || printf '0')"
fi
[[ "$target" =~ ^[0-9]+$ && "$target" != "0" ]] || exit 0

run_id="${GITHUB_RUN_ID:-0}"
marker="<!-- oc-result-run-id:$run_id -->"
if gh api --paginate --slurp "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null | jq -e --arg marker "$marker" 'add // [] | any(.[]; (.body // "") | contains($marker))' >/dev/null 2>&1; then
  exit 0
fi

task_mode="${TASK_MODE:-report}"
body=""

if [[ "${MERGE_REQUESTED:-false}" == "true" ]]; then
  if [[ "${MERGE_EXIT:-1}" == "0" ]]; then
    body="$marker\n## /oc\nMerge command completed successfully."
  else
    body="$marker\n## /oc\nMerge command did not complete successfully. No merge success is claimed."
  fi
elif [[ "$task_mode" == "report" ]]; then
  attempt=""
  response_file=""
  for n in 3 2 1; do
    case "$n" in
      3) outcome="${A3:-}" ;;
      2) outcome="${A2:-}" ;;
      1) outcome="${A1:-}" ;;
    esac
    file="${RUNNER_TEMP:-/tmp}/opencode-final-response-$n.md"
    if [[ "$outcome" == "success" && -f "$file" ]]; then
      attempt="$n"
      response_file="$file"
      break
    fi
  done
  if [[ -n "$response_file" ]]; then
    answer="$(cat "$response_file" | tr -d '\r' | sed -E '/^\[OPENCODE\]/d; /^\[COPILOT\]/d; /\[object Object\]/d' | sed -e 's/[[:space:]]*$//' | cut -c1-12000)"
  else
    answer="OpenCode completed, but no clean final response was captured."
  fi
  body="$marker\n## /oc\n\n$answer"
else
  selected="0"
  for n in 3 2 1; do
    case "$n" in
      3) outcome="${A3:-}" ;;
      2) outcome="${A2:-}" ;;
      1) outcome="${A1:-}" ;;
    esac
    if [[ "$outcome" == "success" ]]; then selected="$n"; break; fi
  done
  if [[ "$selected" == "0" ]]; then
    body="$marker\n## /oc\nAgent did not complete successfully. No success is claimed."
  else
    case "$selected" in
      3) pub="${P3:-}"; ver="${V3:-}"; pr="${PR3:-}"; sha="${SHA3:-}" ;;
      2) pub="${P2:-}"; ver="${V2:-}"; pr="${PR2:-}"; sha="${SHA2:-}" ;;
      1) pub="${P1:-}"; ver="${V1:-}"; pr="${PR1:-}"; sha="${SHA1:-}" ;;
    esac
    if [[ "${OC_TARGET_MODE:-local}" == "remote" && -n "${OC_TARGET_REPO:-}" && -n "${OC_TARGET_BRANCH:-}" ]]; then
      remote_sha="$(gh api "/repos/$OC_TARGET_REPO/git/ref/heads/$OC_TARGET_BRANCH" --jq '.object.sha' 2>/dev/null || true)"
      if [[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]]; then
        summary="Completed target work on `$OC_TARGET_REPO@$OC_TARGET_BRANCH` at `$remote_sha`."
      else
        summary="OpenCode completed, but the target branch could not be observed."
      fi
      if [[ "$pub" == "published" && -n "$pr" ]]; then summary="$summary PR: $pr"; fi
    else
      if [[ -n "$pr" ]]; then
        summary="Completed and published: $pr"
      elif [[ "$pub" == "checkpointed" ]]; then
        summary="Completed durable work and checkpointed the session; resume with `/oc continue`."
      else
        summary="OpenCode completed. Publication was not requested."
      fi
    fi
    if [[ "$ver" == "true" && -n "$sha" ]]; then
      summary="$summary Verified exact SHA `$sha` with observable CI checks."
    elif [[ "$pub" == "published" ]]; then
      summary="$summary Independent CI verification is not currently recorded as green."
    fi
    body="$marker\n## /oc\n$summary"
  fi
fi

gh issue comment "$target" --body "$body" >/dev/null