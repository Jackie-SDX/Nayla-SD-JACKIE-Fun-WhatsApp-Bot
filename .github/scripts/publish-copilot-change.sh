#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/oc-publish-lib.sh"

if [[ -z "$(git status --short)" ]]; then
  echo "::error title=Copilot publication blocked::The fallback agent exited successfully but produced no repository changes."
  printf 'published=false\npr_url=\n' >> "$GITHUB_OUTPUT"
  exit 1
fi


reject_sensitive_publication() {
  local path base
  while IFS= read -r path; do
    base="${path##*/}"
    case "$base" in
      .env|.env.*)
        case "$base" in
          .env.example|.env.sample) ;;
          *) echo "::error title=Sensitive publication path blocked::Refusing to publish a secret-bearing file."; return 1 ;;
        esac
        ;;
      .npmrc|id_rsa|id_ed25519|*.pem|*.key|*.p12|*.pfx)
        echo "::error title=Sensitive publication path blocked::Refusing to publish a secret-bearing file."; return 1
        ;;
      creds.json|auth_info*|*.session|*.session-*)
        echo "::error title=Sensitive publication path blocked::Refusing to publish WhatsApp/device session credentials."; return 1
        ;;
    esac
    case "$path" in
      *session_auth/*|*/auth_info/*|*/auth_info-*/*)
        echo "::error title=Sensitive publication path blocked::Refusing to publish inside a WhatsApp session directory."; return 1
        ;;
    esac
  done < <(git ls-files -m -o --exclude-standard)
}

reject_sensitive_publication

# Stages the tree and refuses nested Git repositories (.octmp fixtures, mode
# 160000 gitlinks), temporary trees, and secret-bearing diffs.
oc_guard_repo_publication .
if [[ -z "$(git diff --cached --name-only)" ]]; then
  echo "::error title=Copilot publication blocked::Nothing was staged for publication."
  printf 'published=false\npr_url=\n' >> "$GITHUB_OUTPUT"
  exit 1
fi

git diff --check
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
# Remove any provider-owned GitHub auth header before controller publication.
git config --local --unset-all "http.${GITHUB_SERVER_URL:-https://github.com}/.extraheader" 2>/dev/null || true
git config --local --unset-all "http.extraheader" 2>/dev/null || true
title="$(jq -r '.issue.title // .pull_request.title // "OpenCode task"' "$GITHUB_EVENT_PATH" | tr '\n' ' ' | cut -c1-72)"
git commit -m "oc: $title"
# Explicit non-logging auth: single-invocation Authorization header holding an
# explicit x-access-token; never a mutable credential helper.
oc_git_push --set-upstream origin "$(git branch --show-current)"
body="$(printf '%s\n\n%s\n%s\n\n%s' \
  "Automated /oc task from issue or pull-request comment #$TARGET_NUMBER." \
  "Fallback execution: GitHub Copilot CLI with bounded AI-credit usage." \
  "The fallback worker ran on an isolated branch and was prohibited from Git commit/push/reset/clean and GitHub CLI mutations." \
  "Review the resulting diff and CI checks before merging.")"
pr_url="$(gh pr create --base "$BASE_REF" --head "$(git branch --show-current)" --title "oc: $title" --body "$body")"
if [[ -z "$pr_url" ]]; then
  echo "::error title=Copilot publication failed::gh pr create returned no pull-request URL."
  printf 'published=false\npr_url=\n' >> "$GITHUB_OUTPUT"
  exit 1
fi
printf 'published=true\npr_url=%s\n' "$pr_url" >> "$GITHUB_OUTPUT"
echo "Published verified Copilot fallback changes as: $pr_url"