#!/usr/bin/env bash
set -euo pipefail
dir="${1:-.}"
branch="${OC_SESSION_BRANCH:-$(git -C "$dir" branch --show-current 2>/dev/null || true)}"
attempt="${OC_ATTEMPT:-checkpoint}"
source "$(cd "$(dirname "$0")" && pwd)/oc-publish-lib.sh"

[[ -d "$dir/.git" || -f "$dir/.git" ]] || exit 0
[[ -n "$branch" && "$branch" != "main" ]] || exit 0
if [[ -z "$(git -C "$dir" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
  exit 0
fi

git -C "$dir" diff --check >/dev/null 2>&1 || {
  echo "::warning title=Checkpoint skipped::The current worktree fails git diff --check; preserving it locally."
  exit 0
}
oc_guard_repo_publication "$dir" || exit 0
if git -C "$dir" diff --cached --quiet; then
  git -C "$dir" reset -q >/dev/null 2>&1 || true
  exit 0
fi
oc_repo_identity "$dir"
git -C "$dir" commit -m "checkpoint(oc): preserve session progress (attempt $attempt)" >/dev/null 2>&1 || {
  git -C "$dir" reset -q >/dev/null 2>&1 || true
  exit 0
}
if oc_git_push -C "$dir" origin "HEAD:refs/heads/$branch" >/dev/null 2>&1; then
  echo "Durable checkpoint pushed: $branch @ $(git -C "$dir" rev-parse HEAD)"
else
  echo "::warning title=Checkpoint push degraded::Checkpoint commit exists locally but could not be pushed."
fi
