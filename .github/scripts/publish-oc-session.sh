#!/usr/bin/env bash
set -euo pipefail
repo="$(printenv GITHUB_REPOSITORY || true)"
base="$(printenv BASE_REF || printf main)"
branch="${OC_SESSION_BRANCH:-}"
state_file="${OC_SESSION_STATE_FILE:-${RUNNER_TEMP:-/tmp}/oc-session-state.json}"
publish_requested="${PUBLISH_REQUESTED:-false}"
[[ "$publish_requested" == true ]] || { echo "PR publication not requested; durable branch remains available."; exit 0; }
[[ -n "$repo" && -n "$branch" ]] || { echo "::error title=Publication prerequisites missing::No durable session branch was resolved." >&2; exit 2; }

emit_out(){ printf '%s=%s\n' "$@">> "${GITHUB_OUTPUT:-/dev/null}"; }

head_sha="$(git rev-parse "$branch" 2>/dev/null || true)"
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error title=Session publication blocked::Stable branch $branch is unavailable locally." >&2; exit 1; }

if ! git push --set-upstream origin "$branch"; then
  echo "::error title=Session push failed::Could not push $branch." >&2
  exit 1
fi

existing="$(gh pr list --repo "$repo" --head "$branch" --base "$base" --state open --limit 10 --json number,url,headRefOid 2>/dev/null || printf '[]')"
pr_number="$(jq -r '.[0].number // 0' <<<"$existing")"
pr_url="$(jq -r '.[0].url // ""' <<<"$existing")"

if [[ ! "$pr_number" =~ ^[1-9][0-9]*$ ]]; then
  title="$(jq -r '.issue.title // .pull_request.title // "OpenCode task"' "$GITHUB_EVENT_PATH" 2>/dev/null | tr '\n' ' ' | cut -c1-72)"
  [[ -n "$title" ]] || title="OpenCode task"
  pr_url="$(gh pr create --repo "$repo" --base "$base" --head "$branch" --title "oc: $title" --body "$(printf 'Created by explicit /oc publication request.\\n\\n- Durable session branch: %s\\n- Base: %s\\n- Future /oc continue requests reuse this session.\\n- Merge is explicit.' "$branch" "$base")")"
  pr_number="$(gh pr view "$pr_url" --repo "$repo" --json number --jq '.number')"
fi

head_sha="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid')"
[[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || { echo "::error title=Publication head resolution failed::Could not resolve the exact PR head." >&2; exit 1; }

emit_out published true
emit_out pr_number "$pr_number"
emit_out pr_url "$pr_url"
emit_out head_sha "$head_sha"
echo "Published durable session as PR #$pr_number at $head_sha"
