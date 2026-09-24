#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mock="$tmp/bin"
mkdir -p "$mock"
cat > "$mock/opencode" <<'EOF'
#!/usr/bin/env bash
echo "AI_APICallError: OpenCode's free tier can only be used from within OpenCode"
echo "FreeTierError"
exit 0
EOF
chmod +x "$mock/opencode"

out="$tmp/out"
live="$tmp/live"
set +e
PATH="$mock:$PATH" RUNNER_TEMP="$tmp" GITHUB_OUTPUT="$out" OC_INITIAL_SHA="$(git -C "$repo_root" rev-parse HEAD)" OPENCODE_AGENT_TIMEOUT_MINUTES=1 OPENCODE_API_KEY="test-secret" OC_PROGRESS_INTERVAL_SECONDS=1 bash "$script_dir/run-opencode-attempt.sh" 91 >"$live" 2>&1
rc=$?
set -e
[[ "$rc" == "75" ]] || { echo "expected 75, got $rc"; exit 1; }
grep -Fq "termination_reason=provider-unavailable" "$out"
grep -Fq "provider_failure_kind=free-tier-context" "$out"
! grep -Fq "test-secret" "$live"

safe="$tmp/safe.log"
printf "%s
" "FreeTierError: OpenCode's free tier can only be used from within OpenCode" > "$safe"
envfile="$tmp/env"
GITHUB_ENV="$envfile" CURRENT_PROVIDER=opencode SAFE_LOG="$safe" OPENCODE_ROUTE_INDEX=0 OPENCODE_EXCLUDED_PROVIDERS="" bash "$script_dir/classify-provider-failure.sh"
grep -Fq "OPENCODE_EXCLUDED_PROVIDERS=opencode" "$envfile"
grep -Fq "OPENCODE_ROUTE_INDEX=1" "$envfile"

out2="$tmp/out2"
env2="$tmp/env2"
GITHUB_ENV="$env2" GITHUB_OUTPUT="$out2" OPENCODE_API_KEY=x COPILOT_GITHUB_TOKEN=test-token OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_EXCLUDED_PROVIDERS=opencode bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=opencode/big-pickle" "$out2"

out3="$tmp/out3"
env3="$tmp/env3"
GITHUB_ENV="$env3" GITHUB_OUTPUT="$out3" COPILOT_GITHUB_TOKEN=test-token OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=opencode/mimo-v2.6-flash-free" "$out3"

out_primary="$tmp/out-primary"
env_primary="$tmp/env-primary"
GITHUB_ENV="$env_primary" GITHUB_OUTPUT="$out_primary" OPENCODE_API_KEY=x OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=opencode/mimo-v2.6-flash-free" "$out_primary"

echo "[model] MiMo 2.6 is first, Big Pickle remains second"


echo "[3/8] Zen context failure requests OpenRouter"
safe_hint="$tmp/safe-hint.log"
printf "%s\n" "FreeTierError: OpenCode free tier context unavailable" > "$safe_hint"
hint_env="$tmp/hint-env"
GITHUB_ENV="$hint_env" CURRENT_PROVIDER=opencode SAFE_LOG="$safe_hint" OPENCODE_ROUTE_INDEX=0 OPENCODE_EXCLUDED_PROVIDERS="" bash "$script_dir/classify-provider-failure.sh"
grep -Fq "OPENCODE_ROUTE_HINT=openrouter" "$hint_env"
grep -Fq "OPENCODE_ROUTE_INDEX=1" "$hint_env"

echo "[4/8] OpenRouter selects the same OpenCode runtime"
router_out="$tmp/router-out"
router_env="$tmp/router-env"
GITHUB_ENV="$router_env" GITHUB_OUTPUT="$router_out" OPENCODE_API_KEY=x OPENROUTER_API_KEY=test-router OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_ROUTE_HINT=openrouter OPENCODE_EXCLUDED_PROVIDERS=opencode bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=openrouter/openrouter/free" "$router_out"
grep -Fq "provider=openrouter" "$router_out"

echo "[5/8] full attempt pipeline advances after Zen 403"
pipe_out="$tmp/pipe-out"
pipe_env="$tmp/pipe-env"
set +e
GITHUB_OUTPUT="$pipe_out" GITHUB_ENV="$pipe_env" GITHUB_REPOSITORY="Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot" GITHUB_RUN_ID=12345 GITHUB_WORKSPACE="$repo_root" RUNNER_TEMP="$tmp" PROVIDER=opencode OC_SELECTED_MODEL=opencode/big-pickle OC_TARGET_MODE=local TARGET_NUMBER=89 BASE_REF=main INITIAL_SHA="$(git -C "$repo_root" rev-parse HEAD)" OC_INITIAL_SHA="$(git -C "$repo_root" rev-parse HEAD)" OPENCODE_API_KEY=test-secret OPENCODE_AGENT_TIMEOUT_MINUTES=1 OC_PROGRESS_INTERVAL_SECONDS=1 PATH="$mock:$PATH" bash "$script_dir/run-attempt-pipeline.sh"
pipe_rc=$?
set -e
[[ "$pipe_rc" == "0" ]] || { echo "pipeline returned $pipe_rc"; exit 1; }
grep -Fq "agent_outcome=failure" "$pipe_out"
grep -Fq "termination_reason=provider-unavailable" "$pipe_out"
grep -Fq "classify_outcome=success" "$pipe_out"
grep -Fq "OPENCODE_ROUTE_INDEX=1" "$pipe_env"
grep -Fq "OPENCODE_EXCLUDED_PROVIDERS=opencode" "$pipe_env"
! grep -Fq "big-pickle=" "$pipe_env"


echo "[6/8] Gemini advisory is optional and fail-open"
bash -n "$script_dir/gemini-advisory-peer.sh"
advisory_out="$tmp/advisory-out"
GITHUB_OUTPUT="$advisory_out" RUNNER_TEMP="$tmp" \
  GEMINI_API_KEY="" GEMINI_API_KEY_1="" GEMINI_API_KEY_2="" \
  OPENROUTER_API_KEY="" GROQ_API_KEY="" \
  bash "$script_dir/gemini-advisory-peer.sh"
grep -Fq "gemini_advisory_status=unavailable" "$advisory_out"
! grep -Fq "gemini_advisory_status=completed" "$advisory_out"
echo "[6/8] advisory fail-open contract: OK"

echo "[7/8] live model-not-found suggestion self-heals the next route"
suggested_log="$tmp/suggested.log"
printf "%s\n" "Model not found: opencode/old-model-free. Did you mean: mimo-v2.6-flash-free, ling-3.0-flash-fin-free?" > "$suggested_log"
suggested_env="$tmp/suggested-env"
GITHUB_ENV="$suggested_env" CURRENT_PROVIDER=opencode SAFE_LOG="$suggested_log" OPENCODE_ROUTE_INDEX=0 OPENCODE_EXCLUDED_PROVIDERS="" bash "$script_dir/classify-provider-failure.sh"
grep -Fq "OPENCODE_RECOVERY_MODEL=mimo-v2.6-flash-free" "$suggested_env"
recovery_out="$tmp/recovery-out"
recovery_env="$tmp/recovery-env"
GITHUB_ENV="$recovery_env" GITHUB_OUTPUT="$recovery_out" OPENCODE_API_KEY=x OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.6-flash-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_RECOVERY_MODEL=mimo-v2.6-flash-free OPENCODE_SELECTED_MODEL=opencode/old-model-free bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=opencode/mimo-v2.6-flash-free" "$recovery_out"
echo "[8/8] adaptive model fallback regression: OK"
