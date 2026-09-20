#!/usr/bin/env bash
set -euo pipefail

if [[ -z "$(git status --short)" ]]; then
  echo "Copilot completed successfully with no repository changes."
  exit 0
fi

git diff --check
git add -A
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
title="$(jq -r '.issue.title // .pull_request.title // "OpenCode task"' "$GITHUB_EVENT_PATH" | tr '\n' ' ' | cut -c1-72)"
git commit -m "oc: $title"
gh auth setup-git
git push --set-upstream origin "$(git branch --show-current)"
body="$(printf '%s\n\n%s\n%s\n\n%s' \
  "Automated /oc task from issue or pull-request comment #$TARGET_NUMBER." \
  "Fallback execution: GitHub Copilot CLI with bounded AI-credit usage." \
  "The fallback worker ran on an isolated branch and was prohibited from Git commit/push/reset/clean and GitHub CLI mutations." \
  "Review the resulting diff and CI checks before merging.")"
pr_url="$(gh pr create --base "$BASE_REF" --head "$(git branch --show-current)" --title "oc: $title" --body "$body")"
echo "Published verified Copilot fallback changes as: $pr_url"