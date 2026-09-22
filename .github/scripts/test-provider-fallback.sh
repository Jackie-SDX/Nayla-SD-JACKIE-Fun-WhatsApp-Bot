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
GITHUB_ENV="$env2" GITHUB_OUTPUT="$out2" OPENCODE_API_KEY=x COPILOT_GITHUB_TOKEN=test-token OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.5-free" OPENCODE_ROUTE_INDEX=1 OPENCODE_EXCLUDED_PROVIDERS=opencode bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=github-copilot/auto" "$out2"

out3="$tmp/out3"
env3="$tmp/env3"
GITHUB_ENV="$env3" GITHUB_OUTPUT="$out3" COPILOT_GITHUB_TOKEN=test-token OPENCODE_ZEN_FREE_MODELS="big-pickle,mimo-v2.5-free" bash "$script_dir/select-opencode-route.sh"
grep -Fq "route=github-copilot/auto" "$out3"


echo "[5/5] full attempt pipeline advances after Zen 403"
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

echo "provider fallback regression: OK"
