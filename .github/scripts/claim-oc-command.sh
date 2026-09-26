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

if [[ "$GITHUB_EVENT_NAME" == "pull_request_review_comment" ]]; then
  reaction_api="/repos/$repo/pulls/comments/$comment_id/reactions"
else
  reaction_api="/repos/$repo/issues/comments/$comment_id/reactions"
fi

actor="$(gh api user --jq '.login' 2>/dev/null || true)"
if [[ -z "$actor" ]]; then
  echo "Unable to identify the authenticated GitHub Actions actor; refusing to execute." >&2
  printf 'accepted=false
' >> "$GITHUB_OUTPUT"
  exit 1
fi

reactions="$(gh api "$reaction_api?per_page=100" 2>/dev/null || true)"
if jq -e --arg actor "$actor" 'any(.[]; .content == "eyes" and .user.login == $actor)' <<<"$reactions" >/dev/null 2>&1; then
  echo "Duplicate /oc delivery for comment $comment_id; existing bot claim reaction found."
  printf 'accepted=false
' >> "$GITHUB_OUTPUT"
  exit 0
fi

if ! gh api -X POST -f content=eyes "$reaction_api" >/dev/null 2>&1; then
  echo "Unable to claim /oc comment $comment_id with an eyes reaction; refusing to execute." >&2
  printf 'accepted=false
' >> "$GITHUB_OUTPUT"
  exit 1
fi

printf 'accepted=true
' >> "$GITHUB_OUTPUT"
echo "Claimed /oc comment $comment_id for one agent execution."
