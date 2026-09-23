#!/usr/bin/env bash
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
target=0
comment_id=0

if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  target="$(jq -r '.issue.number // .pull_request.number // 0' "$GITHUB_EVENT_PATH" 2>/dev/null || printf '0')"
  comment_id="$(jq -r '.comment.id // 0' "$GITHUB_EVENT_PATH" 2>/dev/null || printf '0')"
fi

[[ "$target" =~ ^[1-9][0-9]*$ && "$comment_id" =~ ^[1-9][0-9]*$ ]] || {
  printf 'accepted=false\n' >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
}

marker="<!-- oc-comment-claim:$comment_id -->"
if ! comments="$(gh api --paginate --slurp "/repos/$repo/issues/$target/comments?per_page=100" 2>/dev/null)"; then
  echo "Unable to inspect existing /oc claims; refusing to execute." >&2
  printf 'accepted=false\n' >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 1
fi
if jq -e --arg marker "$marker" 'add // [] | any(.[]; (.body // "") | contains($marker))' <<<"$comments" >/dev/null 2>&1; then
  echo "Duplicate /oc delivery for comment $comment_id; skipping agent execution."
  printf 'accepted=false\n' >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

gh issue comment "$target" --body "$marker" >/dev/null
printf 'accepted=true\n' >> "${GITHUB_OUTPUT:-/dev/null}"
echo "Claimed /oc comment $comment_id for one agent execution."
