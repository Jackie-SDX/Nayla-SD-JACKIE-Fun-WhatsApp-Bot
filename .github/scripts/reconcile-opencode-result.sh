#!/usr/bin/env bash
set -euo pipefail

base_ref="${BASE_REF:-main}"
branch="$(git branch --show-current 2>/dev/null || true)"
head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -n "$branch" && "$branch" != "$base_ref" && "$branch" != "HEAD" && -n "$head_sha" ]] || exit 0

merged_same_head="$(gh pr list --head "$branch" --base "$base_ref" --state merged --limit 50 --json number,headRefOid | jq -r --arg sha "$head_sha" '.[] | select(.headRefOid == $sha) | .number' | head -n 1)"
[[ -n "$merged_same_head" ]] || exit 0

open_prs="$(gh pr list --head "$branch" --base "$base_ref" --state open --limit 20 --json number | jq -r '.[].number')"
[[ -n "$open_prs" ]] || exit 0

for pr in $open_prs; do
  gh pr close "$pr" --comment "Closed automatically by /oc reconciliation: branch head $head_sha was already merged through PR #$merged_same_head. No new commit exists on this branch after that merge."
done