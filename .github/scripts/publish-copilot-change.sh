#!/usr/bin/env bash
set -euo pipefail

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
    esac
  done < <(git ls-files -m -o --exclude-standard)
  git add -A
  if git diff --cached --binary | grep -Eiq "(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{20,}|-----BEGIN (OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----)"; then
    echo "::error title=Secret material detected::Refusing to publish a staged diff containing a high-confidence credential pattern."
    git reset >/dev/null
    return 1
  fi
}

reject_sensitive_publication

git diff --check
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
if [[ -z "$pr_url" ]]; then
  echo "::error title=Copilot publication failed::gh pr create returned no pull-request URL."
  printf 'published=false\npr_url=\n' >> "$GITHUB_OUTPUT"
  exit 1
fi
printf 'published=true\npr_url=%s\n' "$pr_url" >> "$GITHUB_OUTPUT"
echo "Published verified Copilot fallback changes as: $pr_url"