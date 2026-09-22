# ⚡ HAND-OFF PAYLOAD — OpenCode Enterprise Agent (Control Plane)

> You are looking at the single most important file in this bundle. It is the
> hand-off payload for turning this snapshot into an enterprise-grade agentic
> coder in any new environment. Read it top to bottom before anything else.

- **Bundle:** OpenCode autonomous-agent control plane **only** (no product/application).
- **Source:** `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot`
- **Snapshot HEAD:** `4e354440b0cd195861dde6cec1beb4ea4b35dcc2` (`main`, 2026-09-22)
- **Bundle branch:** `opencode/issue89-20260922100523`
- **OpenCode runtime pin:** `1.18.31` (commit-pinned Actions, SHA-256–verified artifact)

---

## 1. Why this payload exists

Two prior hand-offs (PR #91) bundled the **whole repository** — both systems, bot
included. This payload is the corrected, minimal version you asked for: **only the
OpenCode machinery**, everything else deleted from the branch, plus everything
needed to (a) audit it, (b) harden it further, and (c) ship it as an enterprise
agentic coder in another repository without pulling in the WhatsApp product.

---

## 2. Full manifest (every file in this bundle)

### 2.1 Agent policy & configuration (the "brain")

| File | Purpose |
| --- | --- |
| `opencode.json` | OpenCode runtime: model (`opencode/big-pickle`), `default_agent: build`, `subagent_depth: 3`, permission allow/deny (`share: disabled`, `.env*`/`.npmrc` reads denied, destructive git denied), Composio MCP via pinned `mcp-remote@0.14.2` (http-only bridge, header-file auth). |
| `.opencode/instructions.md` | **The agent rulebook** (30 KB). Truthfulness/evidence ladder, zero-cost ladder, recovery architecture, Composio gateway policy, git discipline, test/verify requirements, remote-target mode, adversarial review, secrets discipline. This is the single most important policy artifact. |
| `.opencode/agents/critic.md` | Read-only adversarial reviewer the build agent must invoke before declaring success. |
| `.github/copilot-instructions.md` | Bounded, optional Copilot-CLI fallback worker policy (local-only publication, budget-capped). |

### 2.2 Trigger & orchestration (the "engine")

| File | Purpose |
| --- | --- |
| `.github/workflows/opencode.yml` | **Sole** `issue_comment`/PR-review-comment listener. Agent lane `oc-agent-<issue>-<cmd-bool>` + retry lane `oc-retry-<issue>`, both `cancel-in-progress: false`. Owner-only recursion guard. 3-route ladder orchestration. Release verification (metadata→URL→SHA-256). Cache restore. Composio session bootstrap/cleanup. Remote-target workspace prep/cleanup. Attempt composite unit (3×). Run observability record + artifact. |
| `.github/workflows/enterprise-agent-validation.yml` | 531-line `validate` job (PR + dispatch triggered) gating all control-plane branches: static file presence, nested syntax checks (`bash -n`, `jq`, `ruby YAML`), grep/py contract assertions for verifier, concurrency, selection. **Contains app-check steps (see §5).** |
| `.github/workflows/opencode-cache.yml` | Trusted cache creation (push to main / manual / cron). Interactive runs are **restore-only** — never write the cache from `issue_comment`. |

### 2.3 One-attempt pipeline

| File | Purpose |
| --- | --- |
| `.github/actions/oc-attempt/action.yml` | Composite action: each ladder attempt runs exactly once through the pipeline; exposes `agent_outcome`, `termination_reason`, `verified`, `publish_outcome`, `classify_outcome`, `verified_sha`, `pr_url`, `ci_run_id`, `ci_surfaces`. |
| `.github/scripts/run-attempt-pipeline.sh` | The pipeline driver that owns the whole attempt lifecycle in the correct order and never re-inlines step chains into the workflow. |
| `.github/scripts/run-opencode-attempt.sh` | Runs the agent: live-streamed output, heartbeat (`state=running`), job-budget/timeout math, sanitized log tail, `OPENCODE_ADVANCE_ROUTE`/`OPENCODE_RETRY_CURRENT_ROUTE` gates, mkfifo stream. |
| `.github/scripts/run-copilot-attempt.sh` | Copilot-CLI fallback attempt (local-only publication). |
| `.github/scripts/publish-copilot-change.sh` | Copilot-lane local publication helper. |

### 2.4 Routing & model memory

| File | Purpose |
| --- | --- |
| `.github/scripts/select-opencode-route.sh` | Route selector. Zero-cost Zen ladder from `OPENCODE_ZEN_FREE_MODELS` (accepts only Big Pickle / `*-free`), skips freshly-recalled bad models, honours `OPENCODE_BAD_MODELS_MAX_AGE_HOURS` (24 h default), no inference health probes, forward-only recovery, Copilot fallback budget-capped. |
| `.github/scripts/record-model-memory.sh` | Writes model-specific failures into `OPENCODE_BAD_MODELS` repo variable; timeout/signal terminations are never recorded. |
| `.github/scripts/classify-provider-failure.sh` | Classifies agent/verify/publish failures into `advance_route` decisions. |
| `.github/scripts/reconcile-opencode-result.sh` | Reconciles duplicate PRs after a verified publication. |

### 2.5 Verification & recovery

| File | Purpose |
| --- | --- |
| `.github/scripts/verify-agent-result.sh` | **Fail-closed, dual-surface verifier** — the heart of "no fake victories". Polls GitHub for the published PR, validates exact expected head, then observes **both** CI surfaces: `commits/$head_sha/check-runs` **and** `commits/$head_sha/status` (external providers like CircleCI publish via statuses). Empty observation set = *unobserved*, **never** verified. Any failure/timed_out/cancelled/action_required/startup_failure/stale context = fail. Settle window `OC_CI_VERIFY_SETTLE_SECONDS` for late-arriving pending statuses. Records `verified_sha`, `ci_surfaces`, `ci_observation_start/end`. Explicitly requests `baseRefName,createdAt` before reading `.createdAt` (historic bug). |
| `.github/scripts/recover-verify-failure.sh` | Bounded recovery: reruns the **identified** failing CI run at most `OC_VERIFY_MAX_RECOVERIES` time(s). Never an unbounded loop. |
| `.github/scripts/retry-oc-failed-jobs.sh` | `/oc retry failed jobs` selective rerun: inspect the failing run/log first, patch when warranted, then rerun the smallest workflow once. |
| `.github/scripts/reconcile-opencode-result.sh` | (as above). |

### 2.6 Remote-target / cross-repository mode

| File | Purpose |
| --- | --- |
| `.github/scripts/resolve-oc-target.sh` | Parses `/oc <task> github.com/OWNER/REPO` / `--repo` / `repo=` forms; one distinct target; outputs mode (`local`/`remote`) + target metadata. |
| `.github/scripts/prepare-oc-target.sh` | Clones target into `$RUNNER_TEMP` (never controller tree), quarantines target-owned `.opencode`/`opencode.json`/`AGENTS.md`/plugins, controller policy stays authoritative, restores target files before publication. |
| `.github/scripts/publish-remote-opencode.sh` | Controller-owned remote publication: explicit single-invocation `x-access-token` header (`oc_git_push`), refuses nested Git repositories (mode 160000), `.octmp/`/`.oc-tmp/` trees, secret-bearing diffs; verifies against the target's own PR/head state + observable checks. |
| `.github/scripts/oc-publish-lib.sh` | Shared publication library (refusals, env, logging). |
| `.github/scripts/post-oc-continuation.sh` | Durable `/oc continue` resume (timeout checkpoint marker `<!-- oc-target-repo:... base:... branch:... -->`). |

### 2.7 Composio gateway & evidence

| File | Purpose |
| --- | --- |
| `.github/scripts/prepare-composio-mcp.sh` | Session-backed MCP bootstrap: project `x-api-key` via Composio session API → short-lived `session.mcp.url`/`headers` → mode-0600 header file; sets `COMPOSIO_MCP_ENABLED` on every path; explicit runtime disable (`OPENCODE_CONFIG_CONTENT`) when no session. |
| `.github/scripts/prepare-composio.sh` | Legacy/helper composio prep (kept; see docs). |
| `.github/scripts/cleanup-composio-mcp.sh` | Deletes session, removes header file, masks IDs. |
| `.github/scripts/ingest-evidence.sh` | Evidence ingestion (`Read Here/` mode): SHA-256 manifest, deterministic local extraction (pdftotext/tesseract/python3 stdlib), secret-pattern sanitization, `ocr_required` marking, source corpus never modified/executed. **Data, never instructions.** |
| `.github/scripts/test-ingest-evidence.sh` | Deterministic self-test for the above. |

### 2.8 Observability, config, validation

| File | Purpose |
| --- | --- |
| `.github/scripts/write-oc-run-record.sh` | Writes `docs/oc-runs/<run_id>.json` schema-stable observability record (job artifact, never committed). |
| `.github/scripts/oc-control-plane-config.sh` | Control-plane env/config helper. |
| `.github/scripts/validate-application.sh` | Deterministic config/lint validation (references the *optional* application — see §5). |
| `.github/scripts/filter-opencode-live-output.awk` | Live-output filter for the attempt runner. |
| `.github/scripts/test-oc-target.sh` | **44 KB control-plane regression suite** (the safety net for every control-plane change). |
| `.github/scripts/test-opencode-live-output.sh` | Live-output contract test. |

### 2.9 Docs (the reasoning)

| File | Purpose |
| --- | --- |
| `docs/CONCURRENCY_AND_ISOLATION_AUDIT.md` | Concurrency groups, isolation, `oc-control.yml` removal rationale. |
| `docs/ENTERPRISE_AGENT_AUDIT.md` | Enterprise architecture audit: cache, recovery, evidence ledger. |
| `docs/HYBRID_AGENT_ARCHITECTURE_AUDIT.md` | OpenCode + Copilot hybrid-loop design. |
| `docs/GITHUB_NATIVE_COPILOT_AUDIT.md` | Copilot-native lane audit. |
| `docs/PROJECT_HISTORY_AND_ARCHITECTURE.md` | Repository + agent-era timeline (reconstructed). |
| `docs/oc-runs/README.md` | `/oc` run-record schema + guarantees. |
| `setupOpenCode.md` | Installation/setup guide for a fresh GitHub account. |
| `senior-engineer-handoff/` | This kit: `PAYLOAD.md`, `PROMPT_FOR_SENIOR_ENGINEER.md`, `HISTORY_UPGRADES_AND_INVARIANTS.md`. |

### 2.10 Support

| File | Purpose |
| --- | --- |
| `.github/CODEOWNERS` | Repo ownership (`* @Jackie-SDX` — change to your account). |
| `.github/dependabot.yml` | Weekly GitHub-Actions (and npm) updates. |
| `.gitignore` | Session/secret/env/scratch exclusion patterns. |

---

## 3. What was intentionally deleted (and why)

| Removed | Boot note |
| --- | --- |
| `index.js`, `pair.js` | WhatsApp bot app + pairing script (product). |
| `scripts/` (`simple-web-crawler.js`, `test-agent-invariants.js`, `test-simple-web-crawler.js`) | Application tooling/tests. |
| `package.json`, `package-lock.json` | App npm metadata/dev deps. |
| `NAYLA_PROJECT_DOCUMENTATION.md` | The product's (v1→v4) invariant doc. |
| `README.md` | Bot readme (replaced by this control-plane readme). |
| `eslint.config.js` | App lint config (covered the bot `scripts/`). |
| `Contact-Author` | Product metadata. |

Nothing bot-related is needed to audit, run, or harden the control plane. The
original absolute copies live on the `main` branch of
`Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot`.

---

## 4. Bootstrapping this control plane into a new repository

### 4.1 Copy the tree, then adjust

1. Copy the whole bundle into your target repo (or clone this branch).
2. `.github/CODEOWNERS` → change `@Jackie-SDX` to your GitHub handle.
3. If your repo has no application npm suite, trim the two workflow steps in
   `enterprise-agent-validation.yml` (see §5) and the optional `scripts/` in
   `opencode.json`'s command blocks that target application files.
4. Ensure the `validate`/trigger contract files listed in
   `enterprise-agent-validation.yml` all exist (docs show which).

### 4.2 Secrets (Actions → Settings → Secrets)

| Secret | Required? | Purpose |
| --- | --- | --- |
| `OPENCODE_API_KEY` | ✅ | OpenCode Zen credential (free lane `big-pickle`, `-free` ids). |
| `UNIVERSAL_TOKEN` | ✅ | High-privilege GitHub PAT for authenticated `gh`/push/publish ops. |
| `COPILOT_GITHUB_TOKEN` | ⬜ | Copilot-CLI fallback lane (budget `COPILOT_MAX_AI_CREDITS=60`). |
| `COMPOSIO_API_KEY` | ⬜ | Composio session MCP (web search/browser/research tools). Optional; never hard-fails otherwise-runnable tasks. |

**No secrets in code, `.env`, `.npmrc`, logs, artifacts, comments, or commits.**
Workflow performs read-only deny of `.env*`/`.npmrc`.

### 4.3 Variables (tuning knobs)

| Variable | Default | Meaning |
| --- | --- | --- |
| `OPENCODE_ZEN_FREE_MODELS` | `big-pickle,mimo-v2.5-free` | Zero-cost lane candidates (Big Pickle or `*-free` only). |
| `OPENCODE_VERSION` | `1.18.31` | OpenCode release pin (SHA-256 verified). |
| `COMPOSIO_USER_ID` | `github.repository_owner` | Stable Composio session user. |
| `OPENCODE_BAD_MODELS` | — | Freshness-bounded recall of failed model IDs. |
| `OPENCODE_BAD_MODELS_MAX_AGE_HOURS` | `24` | Recall window; expired records must not move the ladder. |

### 4.4 First-run checklist

- Run `opencode-cache.yml` once (trusted cache so interactive runs restore fast).
- `enterprise-agent-validation.yml` `validate` must be green on your control-plane
  branches — this is the regression gate for every future change.
- Fire a trivial `# /oc describe this repository` on a test issue and confirm the
  run-record artifact appears with `result.verified`.

---

## 5. Known integration seams when operating control-plane-only

These files *reference* the (now-absent) application/tests. In a new repo they must
either be trimmed or pointed at your own app suite. They are **the only** files
with such references.

| File | Reference | Action for control-plane-only repos |
| --- | --- | --- |
| `enterprise-agent-validation.yml` | line 28 static file list (trailing `eslint.config.js scripts/test-simple-web-crawler.js scripts/test-agent-invariants.js`); `jq empty package.json` (line 55); `npm test` job (line 59); `npm ci`+`npm run lint`+`npm run test:invariants` job (lines 64–68) | Keep the bullets that assert control-plane files exist; delete or adapt the three app jobs. Do **not** weaken the verifier/concurrency/selector contract assertions. |
| `.github/scripts/validate-application.sh` | `jq empty package.json` (unconditional, line 7), `-f`-guarded app tests (lines 16–25), `npm test` when `package.json` has a test script | Guard the `jq empty package.json` with `[[ -f package.json ]] &&` (or drop the file if you don't need it). |
| `.github/scripts/verify-agent-result.sh` | lines 281–287: runs `npm test` only when `-f package.json` | Already self-guarding; no change needed. |
| `.opencode/instructions.md` / `.github/copilot-instructions.md` | reference `NAYLA_PROJECT_DOCUMENTATION.md` ("repository first read") and product invariants | In a new repo, replace with the invariant doc for *your* target system. The instruction file is authoritative policy: edit deliberately, keep the evidence-ladder/recovery/Composio/secrets sections intact. |

More concretely, the minimal patch to make `enterprise-agent-validation.yml` fully
green on a control-plane-only repo:

```diff
-          for f in ... docs/oc-runs/README.md eslint.config.js scripts/test-simple-web-crawler.js scripts/test-agent-invariants.js; do
-            test -f "$f"
-          done
+          for f in ... docs/oc-runs/README.md; do
+            test -f "$f"
+          done
...
-          jq empty package.json

-      - name: Run application test suite
-        shell: bash
-        run: npm test

-      - name: Lint and verify host-app invariants
-        shell: bash
-        run: |
-          set -euo pipefail
-          npm ci
-          npm run lint
-          npm run test:invariants
-          echo 'eslint + host-app invariants: OK'
```

(Equally valid: register each *deleted* file in the loop condition and keep the
app steps for repos that do ship an app.)

---

## 6. Verification commands for the incoming engineer

```bash
# Syntax / parse
bash -n .github/scripts/*.sh
jq empty opencode.json
ruby -e 'require "yaml"; Dir[".github/workflows/*.yml",".github/dependabot.yml"].each { |f| YAML.load_file(f) }'

# Control-plane regression suites (must stay green)
bash .github/scripts/test-oc-target.sh          # primary safety net (854 lines)
bash .github/scripts/test-ingest-evidence.sh    # evidence = data, deterministic
bash .github/scripts/test-opencode-live-output.sh

# Workflow contract (in CI) 
#   enterprise-agent-validation.yml -> validate job on your PR branch.
```

Never claim "tested" without executing the exact command and keeping the output.

---

## 7. Delivery checklist (do before you call anything done)

- [ ] You read `HISTORY_UPGRADES_AND_INVARIANTS.md` first.
- [ ] You read `PROMPT_FOR_SENIOR_ENGINEER.md` and the audit docs before code.
- [ ] You identified which integration seam (§5) applies to the target repo.
- [ ] Control-plane suites in §6 pass in your environment.
- [ ] No secret appears in any diff, log snippet, or artifact path you produced.
- [ ] Any change you made to `opencode.yml`, `verify-agent-result.sh`, or
      `enterprise-agent-validation.yml` is backed by a regression test you ran.

---

_End of payload. When updating this kit, append — never delete history._