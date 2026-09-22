#!/usr/bin/env bash
# Prepares an isolated remote-target workspace for a task-isolated /oc run.
#
# - Clones the target repository into RUNNER_TEMP (never into the controller
#   worktree, so its .git can never be staged by a later publication step).
# - Quarantines target-owned OpenCode policy (.opencode, opencode.json/.jsonc,
#   AGENTS.md, plugins) away from the run and installs the controller's
#   OpenCode config/instructions into the workspace, so the controller's
#   enterprise policy is authoritative for the target run. Target policy files
#   are restored before publication so the target keeps its own files.
# - Creates one stable branch per (repo, base, task) and reuses an existing
#   branch on resume, so /oc continue continues the exact branch.
#
# The workspace is intentionally left in place for the agent and publisher
# steps; the workflow's "Clean up remote target workspace" step removes it.
#
# Env: OC_TARGET_REPO, OC_TARGET_BASE, OC_TARGET_BRANCH, OC_TARGET_RESUME,
#      OC_TARGET_TASK, OC_CONTROLLER_ROOT, RUNNER_TEMP, GH_TOKEN
# Test seam: OC_TARGET_CLONE_URL overrides the clone source (a local file://
#            URL is used by test-oc-target.sh; default https://github.com/$repo.git)

set -euo pipefail

emit_env() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; }
emit_out() { printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; }

repo="${OC_TARGET_REPO:?OC_TARGET_REPO is required}"
base="${OC_TARGET_BASE:-main}"
resume="${OC_TARGET_RESUME:-0}"
task="${OC_TARGET_TASK:-}"
controller_root="${runner_temp="${RUNNER_TEMP:-/tmp}"
clone_url="${OC_TARGET_CLONE_URL:-https://github.com/$repo.git}"

if [[ ! "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*[A-Za-z0-9]/[A-Za-z0-9][A-Za-z0-9_.-]*[A-Za-z0-9]$ ]]; then
  echo "::error title=Invalid remote target::Target must be OWNER/REPO: $repo" >&2
  exit 2
fi
if [[ ! "$base" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "::error title=Invalid target base::Base must be a valid Git ref name: $base" >&2
  exit 2
fi

owner="${repo%%/*}"
repo_name="${repo#*/}"
slug="$(printf '%s@%s#%s' "$repo" "$base" "$task" | sha256sum | cut -c1-12)"
default_branch="oc/remote-${owner}-${repo_name}-${base}-${slug}"
branch="${OC_TARGET_BRANCH:-$default_branch}"
if [[ ! "$branch" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "::error title=Invalid target branch::Derived branch name is not a valid Git ref: $branch" >&2
  exit 2
fi

workdir="$(mktemp -d "$runner_temp/oc-target-XXXXXX")"

echo "Preparing remote target workspace for $repo (base=$base, branch=$branch)"

source "$(dirname "$0")/oc-publish-lib.sh"

oc_git_authed clone --no-checkout --single-branch --branch "$base" "$clone_url" "$workdir/ws" >/dev/null 2>&1 || {
  echo "::error title=Target clone failed::Could not clone $clone_url at base '$base' with the available workflow credential." >&2
  rm -rf "$workdir"
  exit 1
}
ws="$workdir/ws"
git -C "$ws" checkout -q "$base"
git -C "$ws" config user.name "github-actions[bot]"
git -C "$ws" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Reuse an existing stable branch on resume (or when a prior attempt already
# pushed it) instead of starting duplicate work from scratch. Branch queries
# run against the target workspace's origin; the controller-repository origin
# in cwd is never consulted.
if remote_sha="$(cd "$ws" && oc_git_authed ls-remote --exit-code origin "refs/heads/$branch" 2>/dev/null | awk '{print $1}')" && [[ -n "$remote_sha" ]]; then
  oc_git_authed -C "$ws" fetch -q origin "refs/heads/$branch:refs/remotes/origin/$branch"
  git -C "$ws" checkout -q -B "$branch" "origin/$branch"
  resume="1"
else
  git -C "$ws" checkout -q -b "$branch"
fi

# Keep the target repository's own OpenCode configuration, AGENTS.md, plugins,
# and project instructions intact. Enterprise runtime safety is supplied by the
# task prompt rather than by replacing target-local policy.
state_file="$workdir/.oc-target-state.json"
cat > "$state_file" <<EOF
{"mode":"remote","repo":"$repo","base":"$base","branch":"$branch","workspace":"$ws","resume":"$resume","task_file":"$workdir/task.txt"}
EOF
printf '%s' "$task" > "$workdir/task.txt"


emit_env OC_TARGET_WORKSPACE "$ws"
emit_env OC_TARGET_STATE "$state_file"
emit_env OC_TARGET_TASK_FILE "$workdir/task.txt"
emit_env OC_TARGET_BRANCH "$branch"
emit_env OC_TARGET_BASE "$base"
emit_env OC_TARGET_REPO "$repo"
emit_env OC_TARGET_RESUME "$resume"

emit_out workspace "$ws"
emit_out state_file "$state_file"
emit_out branch "$branch"
emit_out base "$base"
emit_out repo "$repo"
emit_out resume "$resume"

echo "Remote target workspace ready: $ws (branch=$branch, resume=$resume)"