#!/usr/bin/env bash
set -euo pipefail
# Model memory (route hygiene item 6): after an OpenCode agent attempt fails for
# model-specific reasons, remember the base model name in the OPENCODE_BAD_MODELS
# repository variable (model=unix_epoch CSV) so later /oc tasks skip it. Entries
# older than OPENCODE_BAD_MODELS_MAX_AGE_HOURS are dropped at read time, and the
# write path is deliberately best-effort: a missing credential/permission must
# never hard-fail the run.

provider="${CURRENT_PROVIDER:-none}"
model="${MODEL:-}"
agent_outcome="${AGENT_OUTCOME:-}"
termination_reason="${TERMINATION_REASON:-completed}"
bad_csv="${OPENCODE_BAD_MODELS:-}"
max_age_hours="${OPENCODE_BAD_MODELS_MAX_AGE_HOURS:-24}"
repo="${GITHUB_REPOSITORY:-}"

[[ "$provider" == "opencode" ]] || exit 0
[[ "$agent_outcome" == "failure" ]] || exit 0
[[ "$termination_reason" != "timeout" && "$termination_reason" != "signal" ]] || exit 0

base="${model##*/}"
[[ -n "$base" && "$base" != "opencode" ]] || exit 0
[[ "$max_age_hours" =~ ^[0-9]+$ ]] || max_age_hours=24

now="$(date +%s)"
keep=""
if [[ -n "$bad_csv" ]]; then
  entry=""
  while IFS=',' read -r entry; do
    [[ -n "$entry" ]] || continue
    name="${entry%%=*}"
    ts="${entry#*=}"
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    [[ "$name" == "$base" ]] && continue
    keep="${keep}${keep:+,}${entry}"
  done <<< "$bad_csv"
fi
new="${keep}${keep:+,}${base}=$now"

if [[ -z "$repo" ]]; then
  echo "No repository configured; skipping model-memory update."
  exit 0
fi

if ! gh variable set OPENCODE_BAD_MODELS --repo "$repo" --body "$new"; then
  echo "::warning title=Model memory not persisted::Could not update OPENCODE_BAD_MODELS on $repo (missing credentials or permission)."
  exit 0
fi

if [[ "$new" == "$bad_csv" ]]; then
  echo "Model memory unchanged for ${base}=$now (already bounded by expiry)."
else
  echo "Recorded failed OpenCode model memory: ${base}=$now"
fi