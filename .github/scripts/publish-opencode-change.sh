#!/usr/bin/env bash
set -euo pipefail

initial_sha="${INITIAL_SHA:?}"
target_number="${TARGET_NUMBER:?}"
base_ref="${BASE_REF:?}"
branch="${OPENCODE_BRANCH:?}"
evidence_dir="${COUNCIL_EVIDENCE_DIR:?}"

git diff --check
git diff --check "$initial_sha"
git merge-base --is-ancestor "$initial_sha" HEAD

if [[ -z "$(git status --short)" ]]; then
  echo "::error title=OpenCode publication blocked::The verified council run produced no repository changes."
  printf 'published=false\npr_url=\n' >> "$GITHUB_OUTPUT"
  exit 1
fi

git add -A
title="$(jq -r '.issue.title // .pull_request.title // "OpenCode council task"' "$GITHUB_EVENT_PATH" | tr '\n' ' ' | cut -c1-72)"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
gh auth setup-git
git commit -m "oc: $title"
git push --set-upstream origin "$branch"

body="$(cat "$evidence_dir/pr-body.md")"
pr_url="$(gh pr create --base "$base_ref" --head "$branch" --title "oc: $title" --body "$body")"
printf 'published=true\npr_url=%s\n' "$pr_url" >> "$GITHUB_OUTPUT"
echo "Published verified OpenCode council changes as: $pr_url"
