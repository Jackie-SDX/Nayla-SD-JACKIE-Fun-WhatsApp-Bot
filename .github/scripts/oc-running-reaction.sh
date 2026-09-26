#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
event_kind="${GITHUB_EVENT_NAME:-issue_comment}"
state_file="${RUNNER_TEMP:-/tmp}/oc-running-reaction.state"
comment_id=""
if [[ -n "${GITHUB_EVENT_PATH:-}" && -f "$GITHUB_EVENT_PATH" ]]; then
  comment_id="$(jq -r ".comment.id // empty" "$GITHUB_EVENT_PATH" 2>/dev/null || true)"
fi
[[ "$comment_id" =~ ^[0-9]+$ && "$comment_id" != "0" ]] || exit 0

api_base="/repos/$repo"
case "$event_kind" in
  issue_comment) reaction_path="$api_base/issues/comments/$comment_id/reactions" ;;
  pull_request_review_comment) reaction_path="$api_base/pulls/comments/$comment_id/reactions" ;;
  *) exit 0 ;;
esac

case "$action" in
  add)
    if [[ -f "$state_file" ]]; then exit 0; fi
    actor="$(gh api user --jq ".login" 2>/dev/null || true)"
    # Only clear stale eyes reactions made by the workflow actor. Never reuse
    # or delete a human reaction.
    if [[ -n "$actor" ]]; then
      stale_ids="$(gh api "$reaction_path?per_page=100" 2>/dev/null | jq -r --arg actor "$actor" "[.[] | select(.content==\"eyes\" and .user.login==$actor)] | .[]?.id" 2>/dev/null || true)"
      while IFS= read -r stale_id; do
        [[ "$stale_id" =~ ^[0-9]+$ ]] || continue
        gh api --method DELETE "$reaction_path/$stale_id" >/dev/null 2>&1 || true
      done <<<"$stale_ids"
    fi
    reaction_id="$(gh api --method POST "$reaction_path" -f content=eyes --jq ".id" 2>/dev/null || true)"
    if [[ "$reaction_id" =~ ^[0-9]+$ ]]; then
      printf "%s\n" "$reaction_id" > "$state_file"
      echo "Added /oc running reaction $reaction_id."
    else
      echo "::warning title=/oc running reaction unavailable::Could not add eyes reaction to comment $comment_id."
    fi
    ;;
  remove)
    # Claim and cleanup run in different GitHub jobs, so RUNNER_TEMP state is not shared.
    # Resolve the workflow actor and remove only that actor's eyes reaction.
    actor="$(gh api user --jq ".login" 2>/dev/null || true)"
    if [[ -n "$actor" ]]; then
      reaction_ids="$(gh api "$reaction_path?per_page=100" 2>/dev/null | jq -r --arg actor "$actor" '.[] | select(.content=="eyes" and .user.login==$actor) | .id' 2>/dev/null || true)"
      removed=0
      while IFS= read -r reaction_id; do
        [[ "$reaction_id" =~ ^[0-9]+$ ]] || continue
        gh api --method DELETE "$reaction_path/$reaction_id" >/dev/null 2>&1 || true
        removed=1
      done <<<"$reaction_ids"
      if [[ "$removed" == "1" ]]; then
        echo "Removed /oc running reaction(s) owned by $actor."
      else
        echo "No /oc running reaction owned by $actor was present."
      fi
    else
      echo "::warning title=/oc running reaction cleanup unavailable::Could not identify the authenticated workflow actor."
    fi
    rm -f "$state_file"
    ;;
  *) echo "::error title=Invalid /oc reaction action::Expected add or remove." >&2; exit 2 ;;
esac
