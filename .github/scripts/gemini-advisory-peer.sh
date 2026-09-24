#!/usr/bin/env bash
set -u

attempt="$(printenv GEMINI_ADVISORY_ATTEMPT 2>/dev/null || true)"
[ -n "$attempt" ] || attempt="advisory"
oc_attempt="$(printenv OC_ATTEMPT 2>/dev/null || true)"
[ "$attempt" = "advisory" ] && [ -n "$oc_attempt" ] && attempt="$oc_attempt"

runner_temp="$(printenv RUNNER_TEMP 2>/dev/null || true)"
[ -n "$runner_temp" ] || runner_temp="/tmp"
out_file="$(printenv GITHUB_OUTPUT 2>/dev/null || true)"
[ -n "$out_file" ] || out_file="/dev/null"
review_file="$(printenv GEMINI_ADVISORY_OUTPUT 2>/dev/null || true)"
[ -n "$review_file" ] || review_file="$runner_temp/gemini-advisory-$attempt.md"
plan_file="$(printenv GEMINI_PLAN_FILE 2>/dev/null || true)"
context_file="$(printenv GEMINI_CONTEXT_FILE 2>/dev/null || true)"
worktree="$(printenv GEMINI_WORKTREE 2>/dev/null || true)"
[ -n "$worktree" ] || worktree="$PWD"
model="$(printenv GEMINI_ADVISORY_MODEL 2>/dev/null || true)"
[ -n "$model" ] || model="gemini-3.5-flash-lite"
providers_csv="$(printenv GEMINI_ADVISORY_PROVIDER_ORDER 2>/dev/null || true)"
[ -n "$providers_csv" ] || providers_csv="gemini,openrouter,groq"
max_calls="$(printenv GEMINI_ADVISORY_MAX_CALLS 2>/dev/null || true)"
[ "$max_calls" -eq "$max_calls" ] 2>/dev/null || max_calls=3
[ "$max_calls" -gt 0 ] 2>/dev/null || max_calls=3
min_interval="$(printenv GEMINI_ADVISORY_MIN_INTERVAL_SECONDS 2>/dev/null || true)"
[ "$min_interval" -eq "$min_interval" ] 2>/dev/null || min_interval=15
[ "$min_interval" -ge 0 ] 2>/dev/null || min_interval=15
state_file="$runner_temp/gemini-advisory-rate.state"

mkdir -p "$runner_temp"
rm -f "$review_file"

emit() { printf '%s=%s\n' "$1" "$2" >> "$out_file"; }

gemini_keys="$runner_temp/gemini-keys-$attempt"
groq_keys="$runner_temp/groq-keys-$attempt"
: > "$gemini_keys"
: > "$groq_keys"

key="$(printenv GEMINI_API_KEY 2>/dev/null || true)"
[ -n "$key" ] && printf '%s\n' "$key" >> "$gemini_keys"
for name in $(compgen -A variable 2>/dev/null | grep -E '^GEMINI_API_KEY_[0-9]+$' | sort -V); do
  key="$(printenv "$name" 2>/dev/null || true)"
  [ -n "$key" ] && printf '%s\n' "$key" >> "$gemini_keys"
done

openrouter_key="$(printenv OPENROUTER_API_KEY 2>/dev/null || true)"

key="$(printenv GROQ_API_KEY 2>/dev/null || true)"
[ -n "$key" ] && printf '%s\n' "$key" >> "$groq_keys"
for name in $(compgen -A variable 2>/dev/null | grep -E '^GROQ_API_KEY_[0-9]+$' | sort -V); do
  key="$(printenv "$name" 2>/dev/null || true)"
  [ -n "$key" ] && printf '%s\n' "$key" >> "$groq_keys"
done

if [ ! -s "$gemini_keys" ] && [ -z "$openrouter_key" ] && [ ! -s "$groq_keys" ]; then
  emit gemini_advisory_status unavailable
  emit gemini_advisory_provider none
  emit gemini_advisory_file ""
  echo "[OC][advisory] no optional review provider configured; continuing with OpenCode only"
  exit 0
fi

request="$(printenv GEMINI_ADVISORY_REQUEST 2>/dev/null || true)"
[ -n "$request" ] || request="$(printenv OC_COMMAND_TEXT 2>/dev/null || true)"

packet="$runner_temp/gemini-review-packet-$attempt.md"
{
  printf '%s\n' "# Advisory request" "$request" ""
  printf '%s\n' "# OpenCode proposed plan"
  if [ -n "$plan_file" ] && [ -f "$plan_file" ]; then cat "$plan_file"; else echo "(No plan file was produced.)"; fi
  printf '%s\n' "" "# Repository state"
  if [ -d "$worktree/.git" ]; then
    git -C "$worktree" status --short 2>/dev/null | head -120 || true
    git -C "$worktree" diff --stat 2>/dev/null | head -80 || true
    git -C "$worktree" log -5 --oneline 2>/dev/null || true
  fi
  printf '%s\n' "" "# Issue/task context"
  if [ -n "$context_file" ] && [ -f "$context_file" ]; then
    tail -c 90000 "$context_file" 2>/dev/null || true
  fi
} > "$packet"

prompt_file="$runner_temp/gemini-review-prompt-$attempt.md"
cat > "$prompt_file" <<'PROMPT'
Act as an independent senior engineering advisor to an autonomous coding agent.

Do not implement changes. Do not provide hidden chain-of-thought. Review only the observable task context, the proposed plan, repository state, and evidence in the packet.

Check correctness, security, regressions, missing requirements, feasibility, and validation quality. Propose concrete safer/smaller fixes where needed.

OpenCode remains the sole engineer. Treat this review as advisory evidence, not authority.

Return concise JSON with:
{
  "assessment": "proceed|revise|blocked",
  "confidence": 0.0,
  "critical_issues": ["..."],
  "important_suggestions": ["..."],
  "tests": ["..."],
  "reasoning_summary": "brief evidence-based explanation; no hidden chain-of-thought"
}
Do not invent facts.
PROMPT
{
  echo
  echo "--- REVIEW PACKET ---"
  tail -c 120000 "$packet"
  echo
  echo "--- END REVIEW PACKET ---"
} >> "$prompt_file"

rate_limit() {
  now="$(date +%s)"
  last=0
  count=0
  if [ -f "$state_file" ]; then read -r last count < "$state_file" || true; fi
  [ "$last" -eq "$last" ] 2>/dev/null || last=0
  [ "$count" -eq "$count" ] 2>/dev/null || count=0
  if [ $((now-last)) -ge 60 ]; then count=0; fi
  [ "$count" -lt "$max_calls" ] || return 1
  if [ "$last" -gt 0 ] && [ $((now-last)) -lt "$min_interval" ]; then
    sleep_for=$((min_interval-(now-last)))
    [ "$sleep_for" -gt 0 ] && sleep "$sleep_for"
  fi
  now="$(date +%s)"
  count=$((count+1))
  printf '%s %s\n' "$now" "$count" > "$state_file"
}

sanitize() {
  printf '%s' "$1" | sed -E \
    -e 's/(AIza[[:alnum:]_-]{20,})/[REDACTED_GOOGLE_KEY]/g' \
    -e 's/(sk-or-v1-[[:alnum:]_-]{20,})/[REDACTED_EXTERNAL_API_KEY]/g' \
    -e 's/(gh[ps]_[[:alnum:]_]{20,}|github_pat_[[:alnum:]_]{20,})/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/(Bearer[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g'
}

save_review() {
  provider="$1"
  used_model="$2"
  body="$3"
  {
    echo "# Independent advisory review"
    echo
    echo "- Provider: $provider"
    echo "- Model: $used_model"
    echo
    sanitize "$body"
  } > "$review_file"
  emit gemini_advisory_status completed
  emit gemini_advisory_provider "$provider"
  emit gemini_advisory_file "$review_file"
  echo "[OC][advisory] review completed by $provider/$used_model"
}

gemini_call() {
  key="$1"
  rate_limit || return 75
  payload="$runner_temp/gemini-payload-$attempt.json"
  response="$runner_temp/gemini-response-$attempt.json"
  jq -n --arg prompt "$(cat "$prompt_file")" '{
    contents:[{parts:[{text:$prompt}]}],
    generationConfig:{temperature:0.2,responseMimeType:"application/json"}
  }' > "$payload" || return 2
  code="$(curl -sS --connect-timeout 5 --max-time 45 \
    -H "x-goog-api-key: $key" \
    -H "Content-Type: application/json" \
    -X POST "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent" \
    --data-binary "@$payload" -o "$response" -w '%{http_code}' 2>/dev/null || true)"
  if [ "$code" != "200" ]; then
    echo "[OC][advisory] Gemini HTTP $code"
    return 1
  fi
  text="$(jq -r '[.candidates[0].content.parts[]?.text] | join("")' "$response" 2>/dev/null || true)"
  [ -n "$text" ] && [ "$text" != "null" ] || return 2
  save_review gemini "$model" "$text"
}

openrouter_call() {
  key="$1"
  rate_limit || return 75
  payload="$runner_temp/openrouter-payload-$attempt.json"
  response="$runner_temp/openrouter-response-$attempt.json"
  jq -n --arg prompt "$(cat "$prompt_file")" '{
    model:"openrouter/free",
    messages:[{role:"user",content:$prompt}],
    temperature:0.2
  }' > "$payload" || return 2
  code="$(curl -sS --connect-timeout 5 --max-time 45 \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -X POST "https://openrouter.ai/api/v1/chat/completions" \
    --data-binary "@$payload" -o "$response" -w '%{http_code}' 2>/dev/null || true)"
  [ "$code" = "200" ] || return 1
  text="$(jq -r '.choices[0].message.content // empty' "$response" 2>/dev/null || true)"
  [ -n "$text" ] || return 2
  save_review openrouter "openrouter/free" "$text"
}

groq_call() {
  key="$1"
  rate_limit || return 75
  model_id="$(printenv GROQ_ADVISORY_MODEL 2>/dev/null || true)"
  [ -n "$model_id" ] || model_id="openai/gpt-oss-20b"
  payload="$runner_temp/groq-payload-$attempt.json"
  response="$runner_temp/groq-response-$attempt.json"
  jq -n --arg prompt "$(cat "$prompt_file")" --arg model "$model_id" '{
    model:$model,
    messages:[{role:"user",content:$prompt}],
    temperature:0.2
  }' > "$payload" || return 2
  code="$(curl -sS --connect-timeout 5 --max-time 45 \
    -H "Authorization: Bearer $key" \
    -H "Content-Type: application/json" \
    -X POST "https://api.groq.com/openai/v1/chat/completions" \
    --data-binary "@$payload" -o "$response" -w '%{http_code}' 2>/dev/null || true)"
  [ "$code" = "200" ] || return 1
  text="$(jq -r '.choices[0].message.content // empty' "$response" 2>/dev/null || true)"
  [ -n "$text" ] || return 2
  save_review groq "$model_id" "$text"
}

for provider in $(printf "%s" "$providers_csv" | tr "," " "); do
  case "$provider" in
    gemini)
      while IFS= read -r key; do
        [ -n "$key" ] && gemini_call "$key" && exit 0
      done < "$gemini_keys"
      ;;
    openrouter)
      [ -n "$openrouter_key" ] && openrouter_call "$openrouter_key" && exit 0
      ;;
    groq)
      while IFS= read -r key; do
        [ -n "$key" ] && groq_call "$key" && exit 0
      done < "$groq_keys"
      ;;
  esac
done

emit gemini_advisory_status unavailable
emit gemini_advisory_provider none
emit gemini_advisory_file ""
echo "::warning title=Advisory reviewer::No optional advisory provider completed successfully; OpenCode continues as sole engineer"
exit 0
