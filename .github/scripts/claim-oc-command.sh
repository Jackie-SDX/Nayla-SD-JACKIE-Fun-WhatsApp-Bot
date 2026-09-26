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
if [[ "$GITHUB_EVENT_NAME" == "pull_request_review_comment" ]]; then
  comment_api="/repos/$repo/pulls/comments/$comment_id"
else
  comment_api="/repos/$repo/issues/comments/$comment_id"
fi
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

current_body="$(gh api "$comment_api" --jq '.body // ""' 2>/dev/null || true)"
if grep -Fq "$marker" <<<"$current_body"; then
  echo "Duplicate /oc delivery for comment $comment_id; skipping agent execution."
  printf 'accepted=false
' >> "$GITHUB_OUTPUT"
  exit 0
fi
claimed_body="$(printf '%s' "$current_body" | sed -E 's/[[:space:]]+$//')"
claimed_body="$claimed_body"$'

'"$marker"
if ! gh api -X PATCH -f body="$claimed_body" "$comment_api" >/dev/null 2>&1; then
  echo "Unable to claim /oc comment $comment_id in-place; refusing to execute." >&2
  printf 'accepted=false
' >> "$GITHUB_OUTPUT"
  exit 1
fi
printf 'accepted=true
' >> "$GITHUB_OUTPUT"
echo "Claimed /oc comment $comment_id for one agent execution."
printf 'accepted=true\n' >> "${GITHUB_OUTPUT:-/dev/null}"
echo "Claimed /oc comment $comment_id for one agent execution."
