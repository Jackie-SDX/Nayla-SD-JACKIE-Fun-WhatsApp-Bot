#!/usr/bin/env bash
set -uo pipefail

attempt="${1:?attempt}"
initial_sha="${INITIAL_SHA:?}"
target_number="${TARGET_NUMBER:-0}"
base_ref="${BASE_REF:-main}"
model="${MODEL:?}"
root="${RUNNER_TEMP:-/tmp}/opencode-council-${GITHUB_RUN_ID:-local}-${attempt}"
mkdir -p "$root"
chmod 700 "$root"

task="$(jq -r '.comment.body // empty' "$GITHUB_EVENT_PATH")"
task="$(printf '%s' "$task" | sed -E '1s#^/(oc|opencode)[[:space:]]*##')"
printf '%s\n' "$task" > "$root/task.md"

branch="opencode/council-issue${target_number}-${GITHUB_RUN_ID}-${attempt}"
printf 'evidence_dir=%s\n' "$root" >> "$GITHUB_OUTPUT"
printf 'branch=%s\n' "$branch" >> "$GITHUB_OUTPUT"
if git ls-remote --heads origin "refs/heads/$branch" | grep -q .; then
  echo "::error title=Unsafe council replay::Remote branch $branch already exists."
  exit 1
fi

failed_cleanup() {
  rc=$?
  echo "Council attempt ${attempt} failed; restoring baseline ${initial_sha}."
  git reset --hard "$initial_sha" >/dev/null 2>&1 || true
  git clean -fd >/dev/null 2>&1 || true
  git switch --detach "$initial_sha" >/dev/null 2>&1 || true
  git branch -D "$branch" >/dev/null 2>&1 || true
  exit "$rc"
}
trap failed_cleanup EXIT

run_stage() {
  local stage="$1" stage_model="$2" prompt="$3" output="$4"
  bash .github/scripts/run-opencode-council-stage.sh "$stage" "$stage_model" "$prompt" "$output"
}

cat > "$root/architect.prompt" <<EOF
Original GitHub task:
$task

Baseline SHA:
$initial_sha

Perform the independent architecture/correctness review. Do not modify files or repository state.
EOF
run_stage architect-reviewer opencode/big-pickle "$root/architect.prompt" "$root/architect.log" || exit 1

cat > "$root/adversarial.prompt" <<EOF
Original GitHub task:
$task

Baseline SHA:
$initial_sha

Perform the independent adversarial/security/reliability review. Do not see or infer the other reviewer's conclusions.
Do not modify files or repository state.
EOF
run_stage adversarial-reviewer opencode/mimo-v2.5-free "$root/adversarial.prompt" "$root/adversarial.log" || exit 1

{
  echo "Original GitHub task:"; cat "$root/task.md"; echo
  echo "=== ARCHITECT REVIEW ==="; cat "$root/architect.log"; echo
  echo "=== ADVERSARIAL REVIEW ==="; cat "$root/adversarial.log"; echo
  echo "Reconcile these independent reports by evidence, not vote. Produce a minimal implementation plan. Mark unresolved high-impact claims BLOCKED."
} > "$root/adjudicator.prompt"
run_stage adjudicator opencode/big-pickle "$root/adjudicator.prompt" "$root/adjudicator.log" || exit 1
grep -q 'COUNCIL_DECISION=READY' "$root/adjudicator.log" || { echo '::error title=Council blocked::Adjudicator did not authorize implementation.'; exit 1; }

git switch -c "$branch"

run_build() {
  local prompt_file="$1" output_file="$2" raw
  raw="$(mktemp "${RUNNER_TEMP:-/tmp}/opencode-build-raw.XXXXXX")"
  set +e
  opencode run --standalone --auto --agent build --model "$model" "$(cat "$prompt_file")" >"$raw" 2>&1
  local rc=$?
  set -e
  python3 - "$raw" "$output_file" <<'PY'
import os,re,sys
from pathlib import Path
s,d=map(Path,sys.argv[1:])
raw=s.read_text(errors='replace')
for k in ('OPENCODE_API_KEY','COMPOSIO_API_KEY','GITHUB_TOKEN','COPILOT_GITHUB_TOKEN','COMPOSIO_MCP_URL','COMPOSIO_MCP_HEADERS_FILE'):
    v=os.environ.get(k)
    if v: raw=raw.replace(v,'[REDACTED]')
raw=re.sub(r'(gh[ps]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})','[REDACTED_GITHUB_TOKEN]',raw)
raw=re.sub(r'(AIza[A-Za-z0-9_-]{20,})','[REDACTED_GOOGLE_KEY]',raw)
raw=re.sub(r'(Bearer\s+)[^\s]+',r'\1[REDACTED]',raw)
d.write_text(raw)
PY
  rm -f "$raw"
  return "$rc"
}

cat > "$root/build.prompt" <<EOF
Original GitHub task:
$task

Baseline SHA:
$initial_sha

=== CANONICAL ADJUDICATION ===
$(cat "$root/adjudicator.log")

Implement only the accepted minimal plan.
Work only in this isolated branch.
Do not commit, push, use gh, or mutate GitHub state.
Preserve existing application and security invariants.
EOF
run_build "$root/build.prompt" "$root/build.log" || exit 1

last_validation="$root/validation-0.log"
last_issue="$root/adjudicator.log"
for cycle in 0 1 2; do
  echo "Council verify/correction cycle $cycle."
  if ! INITIAL_SHA="$initial_sha" bash .github/scripts/validate-application.sh >"$root/validation-${cycle}.log" 2>&1; then
    cp "$root/validation-${cycle}.log" "$root/validation-failed.log"
    last_validation="$root/validation-${cycle}.log"
  else
    last_validation="$root/validation-${cycle}.log"
  fi

  {
    echo "Original GitHub task:"; cat "$root/task.md"; echo
    echo "Baseline SHA: $initial_sha"; echo "Current HEAD: $(git rev-parse HEAD)"; echo
    echo "=== CANONICAL/ACTIVE ADJUDICATION ==="; cat "$root/adjudicator.log"; echo
    echo "=== BUILD OUTPUT ==="; cat "$root/build.log"; echo
    echo "=== DETERMINISTIC VALIDATION ==="; cat "$last_validation"; echo
    echo "Verify the actual working tree and delta. Treat every prior claim as untrusted."
  } > "$root/verifier-${cycle}.prompt"

  verifier_rc=0
  run_stage verifier opencode/mimo-v2.5-free "$root/verifier-${cycle}.prompt" "$root/verifier-${cycle}.log" || verifier_rc=$?
  if [[ "$verifier_rc" -eq 0 ]] && grep -q 'COUNCIL_VERDICT=PASS' "$root/verifier-${cycle}.log" && ! grep -q 'COUNCIL_VERDICT=FAIL' "$root/verifier-${cycle}.log"; then
    final_cycle="$cycle"
    break
  fi

  if (( cycle == 2 )); then
    echo '::error title=Council verifier blocked publication::Verifier did not pass within two correction loops.'
    exit 1
  fi

  {
    echo "Original GitHub task:"; cat "$root/task.md"; echo
    echo "=== PREVIOUS ADJUDICATION ==="; cat "$root/adjudicator.log"; echo
    echo "=== FAILED VALIDATION ==="; cat "$last_validation"; echo
    echo "=== FAILED VERIFIER ==="; cat "$root/verifier-${cycle}.log"; echo
    echo "Re-adjudicate only material validation/verifier findings. Produce a minimal correction plan. If no safe correction can be established, output BLOCKED."
  } > "$root/readjudicator-${cycle}.prompt"
  run_stage adjudicator opencode/big-pickle "$root/readjudicator-${cycle}.prompt" "$root/readjudicator-${cycle}.log" || exit 1
  grep -q 'COUNCIL_DECISION=READY' "$root/readjudicator-${cycle}.log" || exit 1
  cp "$root/readjudicator-${cycle}.log" "$root/adjudicator.log"

  {
    echo "Original GitHub task:"; cat "$root/task.md"; echo
    echo "=== CORRECTION ADJUDICATION ==="; cat "$root/adjudicator.log"; echo
    echo "Correct only newly adjudicated findings."
    echo "Do not commit, push, use gh, or mutate GitHub state."
  } > "$root/correction-${cycle}.prompt"
  run_build "$root/correction-${cycle}.prompt" "$root/build-correction-${cycle}.log" || exit 1
  cp "$root/build-correction-${cycle}.log" "$root/build.log"
done

changed=false
[[ -n "$(git status --short)" ]] && changed=true
final_cycle="${final_cycle:-2}"

cat > "$root/pr-body.md" <<EOF
## OpenCode council verification

- Architecture reviewer: executed independently.
- Adversarial reviewer: executed independently with a different model.
- Adjudicator: emitted READY before implementation.
- Deterministic validation: passed.
- Fresh verifier: emitted PASS.
- Correction cycles used: $final_cycle.
- Baseline SHA: `$initial_sha`.
- Trigger target: #$target_number.

The outer workflow owns commit, push, and PR publication. Council agents did not receive GitHub credentials.
EOF

printf 'evidence_dir=%s\n' "$root" >> "$GITHUB_OUTPUT"
printf 'branch=%s\n' "$branch" >> "$GITHUB_OUTPUT"
printf 'changed=%s\n' "$changed" >> "$GITHUB_OUTPUT"
printf 'verified=true\n' >> "$GITHUB_OUTPUT"

trap - EXIT
echo "OpenCode council attempt ${attempt} verified successfully."
