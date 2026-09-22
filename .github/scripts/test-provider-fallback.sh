#!/usr/bin/env bash
# Deterministic regression/invariant coverage for the PR #113 false-fallback fix.
#
# Invariant under test: when the primary OpenCode attempt succeeds or has already
# published durable work, a non-fatal auxiliary provider warning (e.g. a Zen
# free-tier context error) must NOT create a fresh duplicate attempt.
#  - primary success + auxiliary FreeTierError        -> success preserved,
#                                                        provider_warning=true,
#                                                        completed, no route advance
#  - provider-unavailable AFTER a durable PR exists   -> result_state=published-after-provider-warning,
#                                                        treated as success, no route advance
#  - genuine failure with NO durable work             -> still advances the ladder
#                                                        (guard against over-correction)
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { echo "ASSERTION FAILED: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

mock="$tmp/bin"
mkdir -p "$mock"

initial_sha="$(git -C "$repo_root" rev-parse HEAD)"

write_mock() {
  local name="$1" body="$2"
  cat > "$mock/$name" <<EOF
#!/usr/bin/env bash
$body
EOF
  chmod +x "$mock/$name"
}

# --- [1/6] primary success + auxiliary Zen free-tier warning stays success ----
write_mock opencode 'echo "AI_APICallError: OpenCode'\''s free tier can only be used from within OpenCode"
echo "FreeTierError"
exit 0'
# Any accidental gh/prl call in the success path must fail the test loudly.
write_mock gh 'echo "mock gh must NOT be invoked while the primary attempt succeeds" >&2
exit 99'

out="$tmp/out"
live="$tmp/live"
set +e
PATH="$mock:$PATH" RUNNER_TEMP="$tmp" GITHUB_OUTPUT="$out" OC_INITIAL_SHA="$initial_sha" OPENCODE_AGENT_TIMEOUT_MINUTES=1 OPENCODE_API_KEY="test-secret" OC_PROGRESS_INTERVAL_SECONDS=1 bash "$script_dir/run-opencode-attempt.sh" 91 >"$live" 2>&1
rc=$?
set -e
[[ "$rc" == "0" ]] || fail "primary success + auxiliary warning must keep exit 0, got $rc"
grep -Fq "exit_code=0" "$out" || fail "exit_code=0 not recorded"
grep -Fq "termination_reason=completed" "$out" || fail "termination_reason=completed not recorded"
grep -Fq "provider_failure_kind=free-tier-context-warning" "$out" || fail "provider_failure_kind=free-tier-context-warning not recorded"
grep -Fq "provider_warning=true" "$out" || fail "provider_warning=true not recorded"
! grep -Fq "test-secret" "$live" || fail "secret leaked into live stream"
ok "run-opencode-attempt.sh preserves a successful primary exit despite auxiliary FreeTierError"

# --- [2/6] full pipeline: primary success + warning -> no fresh attempt ----
pipe_out="$tmp/pipe-a-out"
pipe_env="$tmp/pipe-a-env"
pipe_live="$tmp/pipe-a-live"
set +e
GITHUB_OUTPUT="$pipe_out" GITHUB_ENV="$pipe_env" GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" GITHUB_RUN_ID=12345 GITHUB_WORKSPACE="$repo_root" RUNNER_TEMP="$tmp" ATTEMPT=1 PROVIDER=opencode OC_SELECTED_MODEL=opencode/big-pickle OC_TARGET_MODE=local TARGET_NUMBER=89 BASE_REF=main INITIAL_SHA="$initial_sha" OC_INITIAL_SHA="$initial_sha" OPENCODE_API_KEY=test-secret OPENCODE_AGENT_TIMEOUT_MINUTES=1 OC_PROGRESS_INTERVAL_SECONDS=1 PATH="$mock:$PATH" bash "$script_dir/run-attempt-pipeline.sh" >"$pipe_live" 2>&1
pipe_rc=$?
set -e
[[ "$pipe_rc" == "0" ]] || fail "pipeline (success+warning) rc=$pipe_rc"
grep -Fq "agent_outcome=success" "$pipe_out" || fail "pipeline: agent_outcome=success missing"
grep -Fq "result_state=completed" "$pipe_out" || fail "pipeline: result_state=completed missing"
grep -Fq "provider_warning=true" "$pipe_out" || fail "pipeline: provider_warning=true missing"
grep -Fq "classify_outcome=not-applicable" "$pipe_out" || fail "pipeline: classify_outcome=not-applicable missing"
if grep -Eq "^OPENCODE_ROUTE_INDEX=[1-9]" "$pipe_env" 2>/dev/null; then fail "pipeline: a provider warning must not advance the route ladder"; fi
if grep -Fq "OPENCODE_EXCLUDED_PROVIDERS=opencode" "$pipe_env" 2>/dev/null; then fail "pipeline: a provider warning must not exclude the provider"; fi
ok "attempt pipeline preserves success and does NOT create a fresh attempt after a provider warning"

# --- [3/6] provider-unavailable AFTER a durable PR exists -> preserve, no duplicate ----
write_mock opencode 'echo "FreeTierError: OpenCode'\''s free tier can only be used from within OpenCode"
exit 75'
write_mock gh 'now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat <<JSON
[{ "number": 200, "url": "https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/pull/200", "headRefName": "opencode/issue89-thisrun-123", "headRefOid": "1111111111111111111111111111111111111111", "createdAt": "$now_iso" }]
JSON'

pipe_out2="$tmp/pipe-b-out"
pipe_env2="$tmp/pipe-b-env"
pipe_live2="$tmp/pipe-b-live"
set +e
GITHUB_OUTPUT="$pipe_out2" GITHUB_ENV="$pipe_env2" GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" GITHUB_RUN_ID=12346 GITHUB_WORKSPACE="$repo_root" RUNNER_TEMP="$tmp" ATTEMPT=2 PROVIDER=opencode OC_SELECTED_MODEL=opencode/big-pickle OC_TARGET_MODE=local TARGET_NUMBER=89 BASE_REF=main INITIAL_SHA="$initial_sha" OC_INITIAL_SHA="$initial_sha" OPENCODE_API_KEY=test-secret OPENCODE_AGENT_TIMEOUT_MINUTES=1 OC_PROGRESS_INTERVAL_SECONDS=1 PATH="$mock:$PATH" bash "$script_dir/run-attempt-pipeline.sh" >"$pipe_live2" 2>&1
pipe_rc2=$?
set -e
[[ "$pipe_rc2" == "0" ]] || fail "pipeline (published-after-provider-warning) rc=$pipe_rc2"
grep -Fq "agent_outcome=success" "$pipe_out2" || fail "published-after-warning: agent_outcome=success missing"
grep -Fq "result_state=published-after-provider-warning" "$pipe_out2" || fail "published-after-warning: result_state missing"
grep -Fq "provider_warning=true" "$pipe_out2" || fail "published-after-warning: provider_warning=true missing"
grep -Fq "classify_outcome=not-applicable" "$pipe_out2" || fail "published-after-warning: classify_outcome=not-applicable missing"
grep -Fq "termination_reason=provider-unavailable" "$pipe_out2" || fail "published-after-warning: termination_reason=provider-unavailable missing"
grep -Fq "pr_url=https://github.com/Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot/pull/200" "$pipe_out2" || fail "published-after-warning: pr_url missing"
grep -Fq "preserving that result and skipping fresh fallback" "$pipe_live2" || fail "published-after-warning: operator warning not emitted"
if grep -Eq "^OPENCODE_ROUTE_INDEX=[1-9]" "$pipe_env2" 2>/dev/null; then fail "published-after-warning must NOT create a fresh attempt (route advanced)"; fi
if grep -Fq "OPENCODE_EXCLUDED_PROVIDERS" "$pipe_env2" 2>/dev/null; then fail "published-after-warning must NOT exclude the provider"; fi
ok "provider-unavailable after durable PR publication is preserved as success; no duplicate attempt"

# --- [4/6] genuine failure with NO durable work still advances the ladder ----
write_mock gh "printf '[]\n'"
pipe_out3="$tmp/pipe-c-out"
pipe_env3="$tmp/pipe-c-env"
pipe_live3="$tmp/pipe-c-live"
set +e
GITHUB_OUTPUT="$pipe_out3" GITHUB_ENV="$pipe_env3" GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" GITHUB_RUN_ID=12347 GITHUB_WORKSPACE="$repo_root" RUNNER_TEMP="$tmp" ATTEMPT=3 PROVIDER=opencode OC_SELECTED_MODEL=opencode/big-pickle OC_TARGET_MODE=local TARGET_NUMBER=89 BASE_REF=main INITIAL_SHA="$initial_sha" OC_INITIAL_SHA="$initial_sha" OPENCODE_API_KEY=test-secret OPENCODE_AGENT_TIMEOUT_MINUTES=1 OC_PROGRESS_INTERVAL_SECONDS=1 PATH="$mock:$PATH" bash "$script_dir/run-attempt-pipeline.sh" >"$pipe_live3" 2>&1
pipe_rc3=$?
set -e
[[ "$pipe_rc3" == "0" ]] || fail "pipeline (genuine failure) rc=$pipe_rc3"
grep -Fq "agent_outcome=failure" "$pipe_out3" || fail "genuine failure: agent_outcome=failure missing"
grep -Fq "termination_reason=provider-unavailable" "$pipe_out3" || fail "genuine failure: termination_reason missing"
grep -Fq "classify_outcome=success" "$pipe_out3" || fail "genuine failure: classify_outcome=success missing"
grep -Eq "^OPENCODE_ROUTE_INDEX=1$" "$pipe_env3" || fail "genuine failure must still advance the route ladder"
grep -Fq "OPENCODE_ROUTE_HINT=openrouter" "$pipe_env3" || fail "genuine failure: Zen free-tier hint must still prefer OpenRouter"
ok "a real provider-unavailable failure with no durable work still advances the ladder (no over-correction)"

# --- [5/6] free-tier classification still requests OpenRouter when the attempt failed ---
safe="$tmp/safe.log"
printf "%s\n" "FreeTierError: OpenCode free tier context unavailable" > "$safe"
hint_env="$tmp/hint-env"
GITHUB_ENV="$hint_env" CURRENT_PROVIDER=opencode SAFE_LOG="$safe" OPENCODE_ROUTE_INDEX=0 OPENCODE_EXCLUDED_PROVIDERS="" bash "$script_dir/classify-provider-failure.sh"
grep -Fq "OPENCODE_ROUTE_HINT=openrouter" "$hint_env" || fail "classify: OpenRouter hint missing"
grep -Fq "OPENCODE_ROUTE_INDEX=1" "$hint_env" || fail "classify: route index not advanced"
ok "failed-attempt classification still prefers the OpenRouter lane"

# --- [5b/6] live model-not-found suggestion self-heals the next route ---
suggested_log="$tmp/suggested.log"
printf "%s\n" "Model not found: opencode/old-model-free." "Did you mean: mimo-v2.6-flash-free, ling-3.0-flash-fin-free?" > "$suggested_log"
suggested_env="$tmp/suggested-env"
GITHUB_ENV="$suggested_env" CURRENT_PROVIDER=opencode SAFE_LOG="$suggested_log" OPENCODE_ROUTE_INDEX=0 OPENCODE_EXCLUDED_PROVIDERS="" bash "$script_dir/classify-provider-failure.sh"
grep -Fq "OPENCODE_RECOVERY_MODEL=mimo-v2.6-flash-free" "$suggested_env" || fail "model suggestion not captured"
recovery_out="$tmp/recovery-out"
recovery_env="$tmp/recovery-env"
GITHUB_ENV="$recovery_env" GITHUB_OUTPUT="$recovery_out" OPENCODE_API_KEY=x OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_RECOVERY_MODEL=mimo-v2.6-flash-free OPENCODE_SELECTED_MODEL=opencode/old-model-free bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=opencode/mimo-v2.6-flash-free" "$recovery_out" || fail "recovery model route not selected"
ok "adaptive model fallback works on genuine model-not-found"

# --- [6/6] route ladder still selects github-copilot and OpenRouter lanes ---
env2="$tmp/env2"
out2="$tmp/out2"
GITHUB_ENV="$env2" GITHUB_OUTPUT="$out2" OPENCODE_API_KEY=x COPILOT_GITHUB_TOKEN=test-token OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_EXCLUDED_PROVIDERS=opencode bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=github-copilot/auto" "$out2" || fail "copilot fallback not selected"
router_out="$tmp/router-out"
router_env="$tmp/router-env"
GITHUB_ENV="$router_env" GITHUB_OUTPUT="$router_out" OPENCODE_API_KEY=x OPENROUTER_API_KEY=test-router OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_ROUTE_HINT=openrouter OPENCODE_EXCLUDED_PROVIDERS=opencode bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=openrouter/openrouter/free" "$router_out" || fail "openrouter lane not selected"
grep -Fq "provider=openrouter" "$router_out" || fail "openrouter provider not recorded"
ok "route selectors unchanged for genuine fallback lanes"

echo "provider-fallback regression suite: OK (primary-success and published-after-provider-warning never create a fresh duplicate attempt)"
