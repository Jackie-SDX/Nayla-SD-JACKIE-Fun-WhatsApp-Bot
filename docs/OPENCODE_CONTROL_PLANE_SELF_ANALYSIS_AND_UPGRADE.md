# OpenCode Control Plane — Self-Analysis and Enterprise Upgrades

Status: authored by the `/oc` agent on 2026-09-22 (issue #89)
Base commit analyzed: `4e354440b0cd195861dde6cec1beb4ea4b35dcc2`
Scope: this document analyzes the **OpenCode agent control plane only**
(`.github/`, `.opencode/`, `opencode.json`, related docs), not the WhatsApp
bot product code (`index.js`, `pair.js`). Its purpose is to give a senior
engineer everything needed to upgrade this agent to an enterprise-grade,
edge-cutting coding agent **without breaking what is already proven working**.

All facts below were read from the repository files and the live GitHub Actions
run history for `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot` on the authoring
date. Run evidence is listed in section 5.

---

## 1. Control-plane inventory

### 1.1 Workflows (`.github/workflows/`)

| File | Trigger | Purpose (proof-backed) |
| --- | --- | --- |
| `opencode.yml` (464 lines) | `issue_comment` + `pull_request_review_comment` | The single `/oc` and `/opencode` listener. Two jobs: the agent lane and `retry-failed-jobs` (control lane). Owns checkout, run marker, target resolution, release verification, cache restore/install, preflight, Composio session bootstrap, up to 3 route attempts, reconciliation, timeout continuation, human-handoff, routing summary, final status, observability record, and cleanup. |
| `enterprise-agent-validation.yml` (531 lines) | `pull_request`, `workflow_dispatch` | The **gate** every PR must pass. 12 validation steps assert file presence, syntax (JSON/YAML/`bash -n`), `npm test`, `npm run lint`, `npm run test:invariants`, and dozens of contract assertions (concurrency, dual-surface verification, evidence ingestion, attempt pipeline, remote target, config parity, route selector behavior, live-stream smoke test). |
| `opencode-cache.yml` | push to main, `workflow_dispatch`, schedule | Trusted cache creation for the pinned OpenCode binary. The interactive `/oc` path only restores and continues on a miss — it never writes the cache (supply-chain + cache-hygiene invariant). |

### 1.2 Composite action (`.github/actions/`)

- `oc-attempt/action.yml` → runs `.github/scripts/run-attempt-pipeline.sh` as its only step. One composite unit owns the full attempt lifecycle (audit item 5, issue #80): no copy-pasted step chains remain in `opencode.yml`.

### 1.3 Scripts (`.github/scripts/`, 27 + 1 awk filter)

Primary lifecycle:
- `select-opencode-route.sh` — zero-cost route ladder. Reads `OPENCODE_ZEN_FREE_MODELS` (default `big-pickle,mimo-v2.5-free`; only `big-pickle` or `*-free` accepted by `is_free_model()`), `OPENCODE_API_KEY`, `COPILOT_GITHUB_TOKEN`, `OPENCODE_ROUTE_INDEX`, `OPENCODE_RETRY_CURRENT_ROUTE`, `OPENCODE_ADVANCE_ROUTE`, `OPENCODE_EXCLUDED_PROVIDERS`, `OPENCODE_BAD_MODELS`. **No inference health probe** is performed during selection. Fresh bad-model records (≤ `OPENCODE_BAD_MODELS_MAX_AGE_HOURS`, default 24h) are skipped only at fresh selection (start=0); retry/advance still may target them. Expired records never move the ladder.
- `run-opencode-attempt.sh` — builds an **isolated worktree** from `OC_INITIAL_SHA` (`git worktree add --detach`), runs `opencode github run` (local) or `opencode run --dir <target-ws>` (remote) under `timeout --signal=TERM --kill-after=60s`, streams output through a FIFO + live filter, sanitizes every line (known secrets → `[REDACTED]`, plus regex redaction of `AIza*`, `ghp_`/`ghs_`/`github_pat_*`, `sk-or-v1-*`, `Bearer …`), writes heartbeats to a progress log every `OC_PROGRESS_INTERVAL_SECONDS`, clamps the effective timeout against the job budget minus a 120s safety margin, maps exit codes to `termination_reason` (124=`timeout`, 128–159=`signal`), and **injectively disables the Composio server** via `OPENCODE_CONFIG_CONTENT` when the session is inactive.
- `run-copilot-attempt.sh` — optional Copilot fallback lane, bounded by `COPILOT_MAX_AI_CREDITS` (60) and a `COPILOT_GITHUB_TOKEN`; applies its own secret sanitizer. Local-only lane.
- `classify-provider-failure.sh` — only classifies when a sanitized log exists, provider ≠ none, and termination was not timeout/signal. Model-specific errors (``model ... not found``/`unknown model`) advance the route. Account/availability failures (HTTP 401/403/429/500/502/503/504, `FreeTierError`, free-tier-only guard, `RESOURCE_EXHAUSTED`, `UNAVAILABLE`, quota/rate-limit) add the provider to `OPENCODE_EXCLUDED_PROVIDERS` for the remainder of the task and advance.
- `record-model-memory.sh` — writes `OPENCODE_BAD_MODELS` repo variable as `model=unix_epoch` CSV. Best-effort (never hard-fails). Never records timeout/signal events.
- `run-attempt-pipeline.sh` — the single-attempt orchestrator. **Hard invariant (lines 3–6):** `verify-agent-result.sh` and `recover-verify-failure.sh` MUST NEVER control route selection, `agent_outcome`, publication success, or fallback decisions; `EXPECTED_TARGET_HEAD` is audit-only; the agent result is authoritative for the attempt. Also enforces Copilot-lane local-only and runs publication (copilot/local + opencode/remote).

Verification / recovery:
- `verify-agent-result.sh` (546 lines) — independent verification. **Dual surface:** `commits/<sha>/check-runs` (Actions) AND `commits/<sha>/status` (external providers such as CircleCI). Fail-closed on any failure/timed_out/cancelled/action_required/startup_failure/stale conclusion or failure/error status context. Pending keeps polling (default wait 20 min, poll 20s). Empty status set = `none-observed` (never pending alone, never verifiable). All-skipped check-runs are never success. A green snapshot only becomes verified after one `OC_CI_VERIFY_SETTLE_SECONDS` (30s) settle re-check. Candidates are gathered from two windows: `branch_candidate_prs` (strict `opencode/issue<N>-*` / `oc/copilot-<N>-<run>-*` prefix) and `scan_candidate_prs` (PRs linked in the issue thread after `OC_RUN_START_ISO`, `allow_unprefixed`). Failure notices are idempotent (`issue_comments_marker`, `--paginate --slurp`). Remote mode verifies against the **target repo's** PR/branch/checks, never controller worktree state; a merged PR counts as verified; unobservable CI is never success.
- `recover-verify-failure.sh` — bounded recovery: reruns exactly the identified CI run once (`OC_VERIFY_MAX_RECOVERIES`), never a retry loop.

Publication / reconciliation:
- `publish-copilot-change.sh` — Copilot local publication onto `oc/copilot-<n>-<run_id>-<attempt>`.
- `publish-remote-opencode.sh` — controller-owned publication for remote targets back to the **target** repository (explicit non-logging `x-access-token` auth header; refuses nested git / secrets).
- `oc-publish-lib.sh` — shared publication library. `oc_git_push`/`oc_git_authed` use a per-invocation `http.<server>/.extraheader` (base64 `x-access-token:<token>`), never touching credential helpers or `.git/config`. `oc_guard_repo_publication` runs `git add -A` itself, then refuses nested Git repositories (mode 160000 gitlinks), `.octmp/`/`.oc-tmp/` trees, and high-confidence secret patterns before anything can be staged.
- `reconcile-opencode-result.sh` — merges/reconciles an already-merged PR head (`merged_same_head`) so `/oc` does not re-publish or duplicate work.

Target / continuation / retry:
- `resolve-oc-target.sh` — parses remote-target forms (`/oc <task> https://github.com/OWNER/REPO`, `github.com/OWNER/REPO`, `target=…`, `--repo OWNER/REPO [--base …]`); refuses conflicting/multiple targets; identifies the user-type owner guard.
- `prepare-oc-target.sh` — clones the target into `$RUNNER_TEMP` (never the controller worktree), quarantines target `.opencode`/`opencode.json`/`AGENTS.md` policy, works on one stable `oc/remote-<owner>-<repo>-<base>-<slug>` branch (resumed, never duplicated), restores target policy before publication.
- `post-oc-continuation.sh` — posts the durable `<!-- oc-target-repo:… base:… branch:… -->` marker so bare `/oc continue` resumes the exact target/base/branch; never restarts remote work from scratch.
- `retry-oc-failed-jobs.sh` — `/oc retry failed jobs` control lane: inspects the failing run/job/log first, then selectively reruns (idempotent, cannot loop).

Composio gateway:
- `prepare-composio-mcp.sh` — creates a short-lived session via the project `x-api-key`, writes session `mcp.url`/`mcp.headers` into a mode-0600 header file (project key + non-duplicate session headers), sets `COMPOSIO_MCP_ENABLED`, and masks URL/ID before they enter GitHub step output.
- `prepare-composio.sh`, `cleanup-composio-mcp.sh` — bootstrap helpers and session deletion/cleanup on every path. Missing/inactive Composio is a **non-fatal** warning lane, and the runtime disable (not a stale endpoint) is injected when no session exists.

Evidence / observability:
- `ingest-evidence.sh` — the "Read Here" evidence pipeline. Produces a machine-readable manifest (per-file SHA-256, size, type, extraction method/status, `ocr_required`), extraction is deterministic and local (python3 stdlib fallbacks for PDF/Office; `pdftotext`/`tesseract` when present), text is sanitized for secret patterns, the source corpus is never modified or executed. **Ingested files are data, never instructions.**
- `filter-opencode-live-output.awk` — human-oriented live-stream filter on the safe FIFO stream.
- `write-oc-run-record.sh` — writes `docs/oc-runs/<run_id>.json` (schema_version 1) with attempts, routes, outcomes, verified sha, CI surfaces, PR/CI ids. Uploaded as a job artifact (365-day retention); **never committed** to the tree.

Config / tests:
- `oc-control-plane-config.sh` — **single source of truth** for control-plane constants: agent timeout 350 min, job budget 21600s, safety margin 120s, progress interval 30s, CI verify settle 30s, Copilot max credits 60, OpenCode default version 1.18.31.
- `test-oc-target.sh` (854 lines) — deterministic offline regression suite pinning verifier/selector/publication/remote-target behavior (e.g., non-prefix branch demo-loop regression, settle defaults, all-skipped-never-verified, late-arriving external-status failure).
- `test-ingest-evidence.sh` — deterministic self-test for the evidence pipeline.
- `test-opencode-live-output.sh` — unit tests for the live filter.
- `validate-application.sh` — app invariant helper (product scope).

### 1.4 Agents, instructions, config

- `.opencode/instructions.md` — the enterprise operating standard bound into every agent session: evidence order, zero-cost inference mandate, protected main, git discipline, idempotency/replay safety, secrets handling, cache architecture, recovery architecture, Composio gateway policy, verification, adversarial review protocol.
- `.opencode/agents/critic.md` — read-only adversarial verifier subagent (`edit: deny`, `bash: deny`): hostile-but-factual review of diffs, CI evidence, security, regressions, unsupported claims, scope drift, partial mutations.
- `opencode.json` — model `opencode/big-pickle`, default agent `build`, instructions file, `share: disabled`, `subagent_depth: 3`, Composio MCP via `npx mcp-remote@0.14.2` (`http-only`, header-file auth, 20s timeout), permission rules that deny `.env*`/`.npmrc` reads and destructive git/`rm -rf /` bash commands (commit/push are NOT denied), `external_directory: deny`, `doom_loop: allow`.
- `package.json` — app: `npm test` = `scripts/test-simple-web-crawler.js`, `test:invariants` = `scripts/test-agent-invariants.js`, `lint` = eslint scoped to `scripts/**` + `eslint.config.js` only. `eslint.config.js` documents that `index.js`/`pair.js` are legacy and deliberately out of lint scope (syntax-`node --check` + invariant-tested instead), so lint can never block a fix on pre-existing debt.

---

## 2. End-to-end lifecycle of a `/oc` command

1. Owner comments `/oc <task>` on an issue. `opencode.yml` filter: `user.type == 'User'` and author == repository owner, exact `/oc ` / `/opencode` prefix, not a retry command. Concurrency group `oc-agent-<issue>-true`, `cancel-in-progress: false`.
2. Initial state captured (`OC_INITIAL_SHA`, run-start ISO, job-start epoch); idempotent run marker comment posted (`<!-- oc-run-id … -->`).
3. Target resolved (local vs remote); OpenCode release resolved from pinned version and SHA-256 verified; cache restored, else installed from the verified release artifact.
4. Preflight credentials (Zen API key required for the opencode lane; Copilot optional; Composio optional; UNIVERSAL_TOKEN preferred).
5. Composio session bootstrapped (`COMPOSIO_MCP_ENABLED` truthy only on success).
6. Route 1 selected (big-pickle) → `oc-attempt` runs: isolated worktree → agent with live filtered output + heartbeat + budget clamp → sanitized log.
7. On success and opencode/local: publication is self-owned by `opencode github run`; CI verification runs but **never** controls the route (advisory for local opencode; authoritative for remote).
8. On failure with a classifiable reason and not timeout/signal: classify → maybe exclude provider; record bad-model memory; select route 2 (mimo-v2.5-free) → attempt 2; route 3 (Copilot auto, if configured) → attempt 3.
9. Terminal lanes: timeout continuation marker (`/oc continue` resumes), human handoff comment when all attempts exhausted (never claims success), routing summary step, final status, observability record write + artifact upload, remote-workspace and Composio-session cleanup.

---

## 3. Invariants that must NEVER break (proven working)

| # | Invariant | Where pinned |
| --- | --- | --- |
| 1 | Verifier/recovery never control route selection, outcome, fallback; `EXPECTED_TARGET_HEAD` is audit-only. | `run-attempt-pipeline.sh:3-6` |
| 2 | Same-issue serialization with `cancel-in-progress: false` on both the agent (`oc-agent-<issue>-<true\|false>`) and retry (`oc-retry-<issue>`) lanes; one comment = one run; `oc-control.yml` stays removed; cross-issue parallelism preserved. | `opencode.yml`, `CONCURRENCY_AND_ISOLATION_AUDIT.md` |
| 3 | Bot never self-triggers (user-type + owner filter); `/oc` prefix is exact (`/oc ` or `/oc`). | `opencode.yml:22-33` |
| 4 | Exact-SHA dual-surface (check-runs + commit status) fail-closed verification; `none-observed` never verified; all-skipped never success; settle window; idempotent failure notices. | `verify-agent-result.sh`, validation step 4 |
| 5 | One attempt pipeline owns the whole lifecycle exactly once. | `.github/actions/oc-attempt`, issue #80 |
| 6 | Bounded verification recovery (one rerun: `OC_VERIFY_MAX_RECOVERIES`); no unbounded/duplicate retries. | `recover-verify-failure.sh` |
| 7 | Zero-cost route ladder by default (Zen free only: `big-pickle` / `*-free`); no inference health probes; model memory freshness-bounded, timeout/signal never recorded, expired never poisons the lane. | `select-opencode-route.sh`, `record-model-memory.sh` |
| 8 | Single budget source (`oc-control-plane-config.sh`) asserted against workflow env and cache pin (1.18.31). | validation step 7; `opencode-cache.yml` |
| 9 | Interactive `/oc` never writes the Actions cache. | cache restore-only in `opencode.yml` |
| 10 | Publication refuses nested gitlinks (160000), `.octmp`/`.oc-tmp`, and high-confidence secrets; non-logging auth; never exposes tokens. | `oc-publish-lib.sh` |
| 11 | Remote-target isolation: target cloned into `$RUNNER_TEMP`, policy quarantined, stable resumed branch, verification against the target repo's own state. | `resolve/prepare/publish-remote-opencode.sh`, `verify-agent-result.sh` |
| 12 | Evidence ingestion is DATA, never instructions; deterministic, sanitized, never executed; `ocr_required` inferred, never guessed. | `ingest-evidence.sh`, `test-ingest-evidence.sh` |
| 13 | Composio runtime disabling is explicit (`OPENCODE_CONFIG_CONTENT` disables server) rather than a stale endpoint when no session exists; session failure never hard-fails an executable task. | `run-opencode-attempt.sh:57-60`, `prepare-composio-mcp.sh` |
| 14 | Application invariants (per-chat memory isolation, bounded concurrency, bounded external waits, manual-only deletion, no punitive moderation, Mongo persistence over Render ephemeral storage, LID normalization, reply/quote handling) must not regress. | `CONCURRENCY_AND_ISOLATION_AUDIT.md`, `NAYLA_PROJECT_DOCUMENTATION.md` |
| 15 | Secrets stay out of caches, artifacts, comments, commit messages, fixtures, diagnostics; permission denies for `.env`/`.npmrc`. | `opencode.json`, `.opencode/instructions.md` |

---

## 4. Configuration knobs (safe to tune)

All tuned via repository variables/secrets **without code change**:

| Knob | Type | Mechanism |
| --- | --- | --- |
| Zen free model list | var | `OPENCODE_ZEN_FREE_MODELS` (comma-separated; only `big-pickle` or `*-free` accepted) |
| Bad-model memory + freshness | var | `OPENCODE_BAD_MODELS`, `OPENCODE_BAD_MODELS_MAX_AGE_HOURS` (default 24) |
| OpenCode version pin | var | `OPENCODE_VERSION` (default `1.18.31`; must match cache pin + config constant) |
| Composio user | var | `COMPOSIO_USER_ID` (default repository owner) |
| Credentials | secrets | `OPENCODE_API_KEY`, `COPILOT_GITHUB_TOKEN`, `COMPOSIO_API_KEY`, `UNIVERSAL_TOKEN` |
| Budgets | env | `OC_JOB_BUDGET_SECONDS` (21600), `OC_JOB_SAFETY_MARGIN_SECONDS` (120), `OC_PROGRESS_INTERVAL_SECONDS` (30), `OC_CI_VERIFY_SETTLE_SECONDS` (30), `OC_CI_VERIFY_WAIT_MINUTES`/`POLL_SECONDS` |

---

## 5. Workflow-run log analysis (last 10+ runs, observed 2026-09-22)

| Run | Workflow | Event | Head | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| 35723520324 | `opencode` | issue_comment | main | in_progress | **This** self-analysis task |
| 35723540841 | `opencode` | issue_comment | main | skipped | Workflow-originated noise comment; skipped instantly (command-aware group works) |
| 35714977971 | `opencode` | issue_comment | main | skipped | Noise/duplicate trigger skipped |
| 35714975865 | `enterprise-agent-validation` | pull_request | `opencode/issue89-20260922100523` | **failure** | **Root cause:** the "OpenCode-only branch with handoff kit ready" head (`842954c`) removed `index.js`, `package.json`, `scripts/`, `pair.js`, `package-lock.json` etc.; the validate job's required-file `test -f` checks for `package.json`, `eslint.config.js`, `scripts/test-simple-web-crawler.js`, `scripts/test-agent-invariants.js` then fail (`##[error] Process completed with exit code 1.`). The control-plane gate hard-codes the product tree. |
| 35714037750 | `opencode` | issue_comment | main | skipped | Noise skipped |
| 35714023847 | `opencode` | issue_comment | main | success | Verified /oc run |
| 35713472166 | `opencode` | issue_comment | main | skipped | Noise skipped |
| 35713470865 | `enterprise-agent-validation` | pull_request | `opencode/issue89-20260922095519` | success | Prior bundle PR passed the gate |
| 35713096665 | `opencode` | issue_comment | main | skipped | Noise skipped |
| 35713082045 | `opencode` | issue_comment | main | success | Verified /oc run |
| 35712660978 | `opencode` | issue_comment | main | skipped | Noise skipped |
| 35712545163 | `opencode` | issue_comment | main | skipped | Noise skipped |
| 35712529782 | `opencode` | issue_comment | main | success | Verified /oc run |
| 35688842480 | `opencode-cache` | schedule | main | success | Trusted cache population OK |

Observations from the run history:

- **The noise-skip design works.** The large number of `skipped` `opencode` runs is the command-aware concurrency group + exact-prefix filter deliberately dropping workflow-originated marker comments in seconds instead of queueing them behind the active agent run. This is a feature, not churn.
- **The single real failure is instructive.** Run `35714975865` proves the validation gate enforces a full-repo shape assumption: any "OpenCode-only" bundling that deletes the product tree fails the gate. If handoff bundles are meant to be OpenCode-only, the gate must be parameterized (make `package.json`/`scripts/*` required only when present), or the bundle keeps the product tree.
- **`opencode-cache` schedule runs stay green** — the supply-chain validated install path is healthy.
- **Verification tail-events in history** (not in the last 10): the demo-loop regression (issue #71, run `35595874054`) that rejected unprefixed BR #76 was fixed by the two-window candidate scan; the `createdAt` false-failure bug (issue #79, caused run `35598028680` to re-run the same route against an already-merged green PR #77) was fixed in main `80b7bf2`; the crawler `scanAnchors()` fix landed at `4e35444` via PR #88.

---

## 6. Upgrade roadmap (tiered; nothing below breaks an invariant above)

### Tier 1 — Safe additive (no behavior change; lowest risk)

1. **Run-record aggregation dashboard (documented follow-up).** `docs/oc-runs/README.md` states "No aggregation workflow is implemented yet". Implement a read-only aggregator that joins the uploaded `oc-run-record-*` artifacts into `docs/oc-runs/index.md` (or a summary issue). Schema v1 already exposes everything needed (routes, outcomes, verified sha, CI surfaces). This is additive: builds trend/ROI data for the engineering org.
2. **Deepen observability fields** in `write-oc-run-record.sh`: add `attempt_elapsed_seconds`, `effective_timeout_seconds`, and `OPENCODE_BAD_MODELS` transitions per attempt so model-memory churn is auditable.
3. **Smoke-test hardening on every PR**: `enterprise-agent-validation.yml` already smoke-tests `run-opencode-attempt.sh` with a mock binary (redaction, heartbeat, exit-code mapping, budget clamp). Extend the same mock pattern to `select-opencode-route.sh` + `classify-provider-failure.sh` + `record-model-memory.sh` (they are currently asserted via inline Python that shells them out — move to a dedicated `test-route-ladder.sh` to pin behavior deterministically).
4. **Docs**: add a `docs/OPERATIONS_RUNBOOK.md` with the exact commands the senior engineer needs to diagnose a failed run (`gh run view --log-failed`, artifact download, run-record decode) — knowledge capture, no code change.
5. **Add real log-trace quality gates**: assert in validation that sanitized logs never contain live secrets markers (the smoke test already asserts the redaction path; extend the pattern to the `verify-agent-result.sh` failure-comment redaction using the same rule set).
6. **Crawl/Firecrawl/E2B routing docs**: the operating standard names usable research surfaces; codify acceptance criteria in `docs/` so future tool additions must first be proven with a real operation before they are added to the standard.

### Tier 2 — Guarded (touch proven machinery; only land behind a green `test-oc-target.sh` + full validation)

7. **Parameterize the required-file gate** to decouple control-plane-only bundles from product files (directly addresses run `35714975865`). Introduce an env (`CONTROL_PLANE_ONLY=1`) or a manifest check that treats `package.json`/`scripts/*`/`index.js` as required only when present, while keeping the strict control-plane list hard-required. Update `test-oc-target.sh` accordingly and add an offline regression for the bundle shape.
8. **Per-attempt independent verifier evidence string**: `verify-agent-result.sh` already resolves the exact PR/head; surface `verified_sha` + `ci_surfaces` into the issue thread comment so a human never has to guess which SHA was verified.
9. **Budget telemetry into step summary**: emit elapsed-vs-budget per attempt in the routing-summary table (data is already captured, just not displayed).
10. **Route ladder extension via variable only**: adding a third free Zen model is already supported by `OPENCODE_ZEN_FREE_MODELS`; the only validation change needed (if any) is none — confirm with an offline selector test that mirrors the existing subprocess checks.
11. **OpenCode upgrade path**: bumping the pinned binary must be done in `oc-control-plane-config.sh` + workflow env + cache pin + `vars.OPENCODE_VERSION` together (parity assert enforces this). Establish a version-upgrade checklist and an offline smoke run before flipping the default.

### Tier 3 — Aspirational (larger design; do NOT attempt without a written design + audit)

12. **Sandboxed pre-flight (E2B-style isolated runtime)** for risky application changes before they are published: run `npm test` + invariants inside a disposable sandbox so agent-produced code is validated in an isolated environment. This must remain additive and must never replace the real GitHub Actions `enterprise-agent-validation` gate as the authoritative verifier (per `run-attempt-pipeline.sh:3-6` the agent result stays authoritative for the attempt).
13. **Semantic diff-safety analysis**: add a pre-publication guard step that classifies every staged path (control-plane vs product vs docs) and refuses accidental cross-domain changes in a single PR, mirroring `oc_guard_repo_publication`'s philosophy.
14. **Provider-agnostic telemetry**: stream per-attempt structured events (route, latency, tokens/credits, outcome) to a read-only observability sink. The schema v1 record is the seed; a follow-up aggregator can back-fill.
15. **Policy-as-code for the operating standard**: keep `.opencode/instructions.md` authoritative, but add a machine-checkable contract (like the validation Python asserts) that new invariants get mirrored between the instruction doc, the workflows, and the tests, so future edits cannot silently drift.

### Explicitly NOT recommended
- Same-issue parallelism: rejected and documented (`CONCURRENCY_AND_ISOLATION_AUDIT.md §2`) — merge-race and evidence-ordering hazards.
- Moving validation authority into the agent attempt pipeline (would violate invariant #1).
- Linting `index.js` as an error gate (documented as legacy; would block fixes on pre-existing debt). If desired, add a **warn-only** eslint pass scoped to new lines/changed hunks only, never as a required check.
- Direct-push bypasses of main (branch protection `enforce_admins: true` is legitimate and must be respected — use PRs).

---

## 6.1 Implemented follow-up — provider-aware Copilot fallback

The control plane now treats the observed Zen `FreeTierError`/403 context rejection as a provider-unavailable transition when the OpenCode process itself returns exit 0. The attempt emits `termination_reason=provider-unavailable`, the classifier advances to the next provider, and model-memory recording does not poison the OpenCode model for a provider-wide failure. GitHub Actions also grants the Copilot Requests permission and can use the short-lived workflow token when no dedicated Copilot token is supplied. A deterministic regression test pins the 403 -> provider-unavailable -> Copilot transition.

## 6.2 Implemented follow-up — two-brain peer collaboration

The hybrid architecture now supports deliberate in-task collaboration, not only failover. OpenCode can summon Copilot with `.github/scripts/invite-copilot-peer.sh`; Copilot works in the SAME isolated worktree, while publication and final verification remain controller responsibilities. Peer availability, installation, or model failure is fail-open, so collaboration never becomes a task blocker. A separate bounded peer credit budget is used.

## 6.3 Implemented follow-up — OpenRouter recovery

A Zen free-tier context rejection now emits an OpenRouter recovery hint. When `OPENROUTER_API_KEY` exists, the next attempt can switch the SAME OpenCode runtime to `openrouter/openrouter/free`; otherwise the existing Copilot route remains available. This keeps the three-attempt budget while increasing the chance that OpenCode remains alive long enough to invite Copilot.

## 6.4 Implemented follow-up — adaptive model recovery

The selector now captures provider-supplied `Did you mean:` free-model suggestions and tries the suggested model exactly once on the next bounded route. The default Zen secondary candidate now matches the runtime-observed `mimo-v2.6-flash-free`; future catalog drift can self-heal without speculative model probes.

## 7. Verification checklist for the senior engineer

After any control-plane change, before merge, run:

```bash
# Deterministic offline regressions (fast, local)
bash .github/scripts/test-oc-target.sh          # verifier/selector/publication/remote-target contracts
bash .github/scripts/test-ingest-evidence.sh     # evidence pipeline self-test
bash .github/scripts/test-opencode-live-output.sh# human-oriented live filter
bash .github/scripts/validate-application.sh

# Full project gates (mirrors what CI runs)
npm test && npm run test:invariants && npm run lint

# CI parity (the gate runs these exactly): JSON/YAML + bash -n for every control-plane script,
# python contract asserts (see enterprise-agent-validation.yml validate steps), and the
# live streaming/budget smoke test with a mock opencode binary.
```

Then open a PR; `enterprise-agent-validation` on the PR head must go green before merge onto the protected `main`.

---

## 8. Evidence ledger

- Repository state: main `4e354440b0cd195861dde6cec1beb4ea4b35dcc2` (fetched via `git rev-parse`); run marker sha matches.
- Run history: `gh run list --limit 20` (sections 5).
- Run 35714975865 failure: `gh run view 35714975865 --log-failed` confirmed `##[error]Process completed with exit code 1.` in the "Validate files and syntax" step; PR head `842954c` tree confirmed missing `package.json`, `scripts/`, `index.js`, `pair.js`, `package-lock.json`, `eslint.config.js`.
- Branch protection: `gh api …/branches/main/protection` → `enabled: true`, `enforce_admins: true`, required status checks (strict, no configured contexts/checks).
- Source files read: all workflows, all 27 scripts + awk filter, `opencode.json`, `.opencode/instructions.md`, `.opencode/agents/critic.md`, `eslint.config.js`, `package.json`, all `docs/*` including `docs/oc-runs/README.md`.

All claims above are either directly observed repository state/CI logs or `main`-committed documentation; nothing is inferred API behavior.