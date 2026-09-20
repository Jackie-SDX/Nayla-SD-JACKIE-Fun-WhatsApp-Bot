#!/usr/bin/env bash
# Controller-owned publication for remote-target /oc runs.
#
# Runs inside the prepared target workspace, restores the target's own OpenCode
# policy files (quarantined by prepare-oc-target.sh) so the published branch
# only carries the agent's changes, removes the controller policy installed for
# the run, guards the staged tree against nested repositories and temporary
# trees, commits, pushes with the explicit non-logging auth mechanism, then
# creates or reuses the target pull request.
#
# Env: OC_TARGET_REPO, OC_TARGET_BASE, OC_TARGET_BRANCH, OC_TARGET_WORKSPACE,
#      OC_TARGET_STATE, GH_TOKEN, TARGET_NUMBER, BASE_REF, GITHUB_EVENT_PATH

set -euo pipefail

emit_out() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/oc-publish-lib.sh"

repo="${OC_TARGET_REPO:?OC_TARGET_REPO is required}"
base="${OC_TARGET_BASE:-main}"
branch="${OC_TARGET_BRANCH:?OC_TARGET_BRANCH is required}"
ws="${OC_TARGET_WORKSPACE:?OC_TARGET_WORKSPACE is required}"
state_file="${OC_TARGET_STATE:-}"
target_number="${TARGET_NUMBER:-}"
target_base_ref="${BASE_REF:-}"

if [[ ! -d "$ws/.git" ]]; then
  echo "::error title=Remote publication blocked::Target workspace $ws is not a Git repository." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
fi

title="$(jq -r '.issue.title // .pull_request.title // "OpenCode remote-target task"' "$GITHUB_EVENT_PATH" 2>/dev/null | tr '\n' ' ' | cut -c1-72)"
[[ -n "$title" ]] || title="OpenCode remote-target task"

# Restore the target's own quarantined policy files first, then remove the
# controller policy that was installed for the run. The target keeps its
# repository exactly as it is apart from the agent's change.
restore_quarantine() {
  local qdir list rel dest
  qdir="${OC_TARGET_QUARANTINE:-}"
  list="$(jq -r '.quarantine_list // ""' "$state_file" 2>/dev/null || true)"
  installed="$(jq -r '.installed_list // ""' "$state_file" 2>/dev/null || true)"
  if [[ -n "$installed" && -f "$installed" ]]; then
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      rm -rf "$ws/$rel"
    done < "$installed"
  fi
  if [[ -n "$list" && -f "$list" ]]; then
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      if [[ -e "$qdir/$rel" ]]; then
        mkdir -p "$ws/$(dirname "$rel")"
        mv "$qdir/$rel" "$ws/$rel"
      fi
    done < "$list"
  fi
}
restore_quarantine

if [[ -z "$(git -C "$ws" status --short)" ]]; then
  echo "Remote target workspace has no changes after this run."
  existing="$(gh pr list --repo "$repo" --head "$branch" --base "$base" --state open --limit 10 --json number,url 2>/dev/null | jq -r '.[0].url // ""' 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    echo "Reusing already-published target pull request: $existing"
    emit_out published true
    emit_out pr_url "$existing"
    emit_out head_sha "$(git -C "$ws" rev-parse HEAD)"
    exit 0
  fi
  echo "::error title=Remote publication blocked::No changes were produced and no existing target pull request is open." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
fi

oc_guard_repo_publication "$ws" || {
  emit_out published false
  emit_out pr_url ""
  exit 1
}

if [[ -z "$(git -C "$ws" diff --cached --name-only)" ]]; then
  echo "::error title=Remote publication blocked::Nothing was staged for publication." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
fi

git -C "$ws" diff --check || {
  echo "::error title=Remote publication blocked::git diff --check failed in the target workspace." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
}

oc_repo_identity "$ws"

git -C "$ws" commit -q -m "oc: $title" || {
  echo "::error title=Remote commit failed::Could not create the target commit." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
}
head_sha="$(git -C "$ws" rev-parse HEAD)"

oc_git_push -C "$ws" --set-upstream origin "HEAD:$branch" || {
  echo "::error title=Remote push failed::Could not push $branch to $repo. Check that the workflow credential can write to the target repository." >&2
  emit_out published false
  emit_out pr_url ""
  exit 1
}
echo "Pushed remote target branch: $repo@$branch ($head_sha)"

pr_url="$(gh pr create --repo "$repo" --base "$base" --head "$branch" --title "oc: $title" --body "$(printf 'Automated /oc remote-target task from the controller repository.\n\n- Target repository: %s\n- Target base: %s\n- Branch: %s\n- The change was produced and published by controller-owned OpenCode logic.\n\nReview the resulting diff and the target repository'\''s own CI checks before merging.' "$repo" "$base" "$branch")" 2>/dev/null || true)"
if [[ -z "$pr_url" ]]; then
  existing="$(gh pr list --repo "$repo" --head "$branch" --base "$base" --state open --limit 10 --json number,url 2>/dev/null | jq -r '.[0].url // ""' 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    echo "Reusing existing target pull request: $existing"
    emit_out published true
    emit_out pr_url "$existing"
    emit_out head_sha "$head_sha"
    exit 0
  fi
  echo "::warning title=Target PR not created::The branch was pushed but no pull request could be created in $repo."
  emit_out published true
  emit_out pr_url ""
  emit_out head_sha "$head_sha"
  exit 0
fi

echo "Published remote target change as: $pr_url"
emit_out published true
emit_out pr_url "$pr_url"
emit_out head_sha "$head_sha"