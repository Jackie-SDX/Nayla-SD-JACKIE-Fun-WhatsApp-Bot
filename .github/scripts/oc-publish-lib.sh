#!/usr/bin/env bash
# Shared controller-owned Git publication support.
#
# Authentication
# --------------
# Controller publication uses the same explicit, non-logging mechanism that
# GitHub's own actions/checkout uses: an Authorization header carrying a
# base64-encoded `x-access-token:<token>` on the git invocation itself. The
# header is scoped to a single git call with `-c`, so it never touches
# credential helpers, never is written into .git/config, and cannot collide
# with a stale credential helper from another tool. The token value itself is
# never printed, exported, or committed. The credential actually available to
# the workflow is used: GH_TOKEN (UNIVERSAL_TOKEN when configured, otherwise
# the scoped github.token), falling back to GITHUB_TOKEN.
#
# Publication guards
# ------------------
# Nested Git repositories (mode 160000 gitlinks) and temporary/test trees such
# as .octmp/ are refused so they can never be staged or published by accident.

set -euo pipefail

OC_PUBLISH_TOKEN=""
OC_PUBLISH_AUTH_HEADER=""

oc_publish_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    OC_PUBLISH_TOKEN="$GH_TOKEN"
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    OC_PUBLISH_TOKEN="$GITHUB_TOKEN"
  else
    echo "::error title=Publication credential missing::No GH_TOKEN or GITHUB_TOKEN is available for controller Git publication." >&2
    return 1
  fi
  if [[ "${#OC_PUBLISH_TOKEN}" -lt 20 ]]; then
    echo "::error title=Publication credential invalid::The available GitHub credential is too short to be a valid token." >&2
    return 1
  fi
}

# Populates OC_PUBLISH_AUTH_HEADER. Never echoed by this library.
oc_publish_auth_header() {
  oc_publish_token || return 1
  OC_PUBLISH_AUTH_HEADER="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$OC_PUBLISH_TOKEN" | base64 | tr -d '\n')"
}

# Runs a git command authenticated only for this single invocation.
#   oc_git_authed fetch origin main
oc_git_authed() {
  oc_publish_auth_header || return 1
  local git_server="$GITHUB_SERVER_URL"
  [[ -n "$git_server" ]] || git_server="https://github.com"
  GIT_TERMINAL_PROMPT=0 git -c credential.helper= -c core.askPass= -c "http.$git_server/.extraheader=$OC_PUBLISH_AUTH_HEADER" "$@"
}

# Pushes using the explicit auth mechanism; never relies on credential helpers.
#   oc_git_push --set-upstream origin feature/x
oc_git_push() {
  oc_git_authed push "$@"
}

# Stops publication when the staged tree contains structures that must never
# be staged or published: nested Git repositories (mode 160000 gitlinks) and
# temporary/test directories such as .octmp/. Also refuses high-confidence
# secret material. Runs `git add -A` itself so the check is authoritative, and
# unstages everything when it refuses.
#
# Usage: oc_guard_repo_publication [repo-dir]
oc_guard_repo_publication() {
  local dir="${1:-.}"
  if [[ ! -d "$dir/.git" && ! -f "$dir/.git" ]]; then
    echo "::error title=Publication guard error::$dir is not a Git repository." >&2
    return 1
  fi
  git -C "$dir" add -A >/dev/null 2>&1 || true

  if git -C "$dir" ls-files -s | grep -Eq '^[0-9]+ 160000 '; then
    echo "::error title=Nested repository publication blocked::Refusing to publish a nested Git repository (mode 160000 gitlink). Remove the nested .git directory and re-run." >&2
    git -C "$dir" reset -q || true
    return 1
  fi
  if git -C "$dir" ls-files | grep -Eq '(^|/)\.octmp(/|$)|(^|/)\.oc-tmp(/|$)'; then
    echo "::error title=Temporary tree publication blocked::Refusing to publish paths under .octmp/ or .oc-tmp/." >&2
    git -C "$dir" reset -q || true
    return 1
  fi
  if git -C "$dir" diff --cached --binary | grep -Eiq "(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{20,}|-----BEGIN (OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----)"; then
    echo "::error title=Secret material detected::Refusing to publish a staged diff containing a high-confidence credential pattern." >&2
    git -C "$dir" reset -q || true
    return 1
  fi
  return 0
}

# Ensures a repository has the identity needed for committing.
oc_repo_identity() {
  local dir="${1:-.}"
  if [[ -z "$(git -C "$dir" config user.name 2>/dev/null || true)" ]]; then
    git -C "$dir" config user.name "github-actions[bot]"
    git -C "$dir" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  fi
}