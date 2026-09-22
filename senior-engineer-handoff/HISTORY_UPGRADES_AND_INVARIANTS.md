# PROJECT HISTORY — OPENCODE CONTROL PLANE: UPGRADES, INCIDENTS & THINGS THAT MUST NEVER BREAK

> Handoff companion to `PROMPT_FOR_SENIOR_ENGINEER.md` and `PAYLOAD.md`. **Read this
> before the prompt and before any code.** It is the written memory of the autonomous
> OpenCode agent platform: what was built, fixed, deferred, and deliberately refused —
> and the load-bearing decisions that must survive every future change.
>
> This history covers the **control plane only** (`.github/**`, `.opencode/**`,
> `opencode.json`, `docs/**`). The application the platform was built to automate
> (the WhatsApp bot) is **out of scope** for this bundle and is not described here
> beyond what is needed to explain control-plane decisions.
>
> Evidence conventions: `[FACT]` = directly observable from this repo/docs/CI;
> `[INFERRED]` = reasoned from facts, not directly observed. The source repository is
> `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot`; git history was squashed, so most
> pre-current-HEAD history is reconstructed from GitHub artifacts (issues, PRs) and the
> surviving audit docs.
>
> Snapshot HEAD for this handoff: `4e354440b0cd195861dde6cec1beb4ea4b35dcc2`.

---

## 1. What this bundle is [FACT]

A self-hosting autonomous-coding-agent control plane. On a `# /oc <task>` issue
comment (owner only) it:

1. serializes per issue (`cancel-in-progress: false`, command-aware groups);
2. resolves optional remote target repo (`/oc ... github.com/OWNER/REPO`);
3. verifies + installs a pinned OpenCode release (SHA-256 checked, cache-first);
4. runs the agent on an isolated branch through a **3-route zero-cost ladder**
   (OpenCode Zen `opencode/big-pickle` → `opencode/mimo-v2.5-free` → optional
   credit-capped Copilot fallback) as **one composite attempt unit** each;
5. **verifies the published result fail-closed across every observable CI surface**
   (check-runs + commit-status), reconciles duplicate PRs;
6. leaves a durable, schema-stable run-record (job artifact) and cleans up.

The repository is public. `main` is treated as a protected production line by policy
(not just by failure): `CODEOWNERS` = `* @Jackie-SDX`, and
`enterprise-agent-validation.yml` gates control-plane branches with a `validate` job
(`pull_request` + `workflow_dispatch`, ref-scoped concurrency,
`cancel-in-progress: true` because it is read-only/fast).

---

## 2. The control-plane timeline (reconstructed) [INFERRED unless cited]

PRs below merge to `main` unless noted; numbering is from `gh pr list` and the
`docs/` reconstruction.

### 2.1 Bootstrap era — get a free autonomous engineer running
- **#2** free-model failover (OpenCode Zen free models).
- **#8–#11** release-digest normalization; quota-safe routing; Copilot-CLI-native
  runtime; a bounded **Copilot fallback lane**.
- **#12–#22** OpenCode Zen restored as primary; **Composio MCP** finalized
  (session-backed Streamable HTTP, project API key, automation-user bound);
  crawler hardening.
- **#24–#28** multi-model agent council; **verified-publication requirement** (#33) —
  the origin of the "no fake victories" rule that any PR claim requires real evidence.

### 2.2 Hybrid era — two workers, one loop
- **#36–#38** OpenCode + Copilot in one loop, wrapper-owned completion markers.
  Documented in `docs/HYBRID_AGENT_ARCHITECTURE_AUDIT.md` and
  `docs/GITHUB_NATIVE_COPILOT_AUDIT.md`.

### 2.3 Enterprise hardening era
- **#27/#45** current enterprise architecture: recovery architecture, evidence
  ledger, cache architecture, long-running checkpoints → `docs/ENTERPRISE_AGENT_AUDIT.md`.
- **#49–#51, #54** recursive recovery repair; credential protection; durable
  checkpoints for 6-hour ceilings.
- **#56** `oc-enterprise-e2e-self-test` → folded into the validation surface.
- **#58** **bot-comment recursion guard** — `/oc` triggers require a `User` type whose
  login equals the repository owner; workflow-generated comments can never summon the
  agent. Still enforced today in `opencode.yml`'s `if:`.
- **#60** verifier status promoted to the final gate.
- **#61** `enterprise-agent-validation.yml` gates all agent branches on push.
- **#63/#65** `setupOpenCode.md` (the install guide in this bundle).
- **#66–#68** **central remote-target repository mode**: `/oc <task>
  github.com/OWNER/REPO` — target cloned into `$RUNNER_TEMP`, target policy
  quarantined, controller-owned branch per (repo, base, task), publication refusals
  (gitlinks, scratch trees, secret diffs), exact published-head verification.

### 2.4 The current personality (PRs in the visible window) [FACT]
| PR | What it did | State |
| --- | --- | --- |
| #76-era | Demo-loop regression test exposed a verifier prefix-only bug; verifier now also accepts scan-derived PR candidates and treats all-skipped check sets as never-verified. | merged lineage |
| #78 | First fix for the `createdAt` verifier bug | closed unmerged |
| #79 | Broad hardening replacing #78: **live streaming + heartbeat**, job-relative timeouts, **forward-only route recovery**, regression tests, telemetry. | merged at `80b7bf2` |
| #85 | Robustness "edge-cutting benchmark" task (autonomous diagnose→fix→recover exercise). | open (`oc/copilot-84-...`) |
| #86 | **Restore OpenCode OIDC permission** (`id-token: write`) — the Actions-OIDC authenticated branch/commit/push/PR lifecycle, live-tested. | merged |
| #88 | Crawler-resilience: `scanAnchors()` consumed a later closing `</a>` after an unclosed anchor (swallowing healthy links); fixed (+`/malformed-anchor` fixture) plus `enterprise-agent-validation.yml` contract repairs that made the CI surface truthful again. | merged as `4e35444` = **this snapshot's HEAD** |
| #90 | Product feature (`.story` command). | open — product scope, not in this bundle |
| #91 | First full handoff bundle (whole-repo zip + prompt + history docs). | open — superseded by this corrected OpenCode-only bundle |

### 2.5 The verifier `createdAt` incident — why you must trust the verifier's field lists (#71 era)
The `check_pr` verifier read `.createdAt` from `gh pr view --json <fields>` without
requesting `createdAt` in the field list. The real CLI omitted the field, the verifier
treated it as empty, and **healthy PRs were rejected** → a false CI failure flipped a
route on → a **wasteful full re-run of an already-successful task**. The regression
fixtures missed it because the fake `gh` fixture *did* return the field (fixture
fidelity gap). Fixes: keep `baseRefName,createdAt` in the field list (asserted by the
validation workflow today), and keep test fixtures faithful to the real CLI output.

**Lesson generalized:** verification is only as trustworthy as the exact fields it
requests and the fixtures it turns into tests. This is why `verify-agent-result.sh`
today reads both CI surfaces, waits through a settle window, and treats empty
observation as *unobserved*, not green.

---

## 3. Current architecture — the shape to preserve [FACT]

### 3.1 Trigger & serialization
- `opencode.yml` is the **single** `issue_comment`/PR-review-comment listener
  (agent lane + merged `retry-failed-jobs` control lane). `oc-control.yml` was
  removed: it was a second listener that duplicated runs per comment and raced the
  agent lane (its runs queued "pending" behind the active agent run). Both lanes now
  live in `opencode.yml` so **one comment → exactly one workflow run**.
- Agent lane group: `oc-agent-<issue|pr|run_id>-<cmd-bool>` with
  `cancel-in-progress: false`; command-aware so workflow-originated noise comments
  (`-false` group) are skipped instantly instead of queuing behind the active run.
- Retry lane group: `oc-retry-<issue|pr|run_id>` with `cancel-in-progress: false`,
  disjoint from the agent lane.
- Trigger guard: `comment.user.type == 'User' && login == repository_owner`, `!`
  on `/oc retry failed jobs`. (`docs/CONCURRENCY_AND_ISOLATION_AUDIT.md` §1.)

### 3.2 Attempt pipeline (one composite unit per attempt)
`.github/actions/oc-attempt/action.yml` → `run-attempt-pipeline.sh`. Each ladder
attempt runs exactly once through: branch prep → agent run → publication →
verification → classification → model-memory recording. Software state surfaces via
composite outputs (`agent_outcome`, `termination_reason`, `verified`, `publish_outcome`,
`classify_outcome`, `verified_sha`, `pr_url`, `ci_run_id`, `ci_surfaces`). Do not
re-inline step chains into `opencode.yml`.

### 3.3 Route ladder & model memory
- `select-opencode-route.sh`: zero-cost Zen first (`OPENCODE_ZEN_FREE_MODELS`, default
  `big-pickle,mimo-v2.5-free`; accepts only Big Pickle or `*-free`); optional Copilot
  fallback credit-capped (`COPILOT_MAX_AI_CREDITS=60`). **No inference health probes**
  during selection — the real agent invocation is the probe.
- `record-model-memory.sh`: model-specific failures → `OPENCODE_BAD_MODELS` repo
  variable; **timeout/signal terminations are budget events and are never recorded**;
  recall is freshness-bounded (`OPENCODE_BAD_MODELS_MAX_AGE_HOURS`, default 24 h) so
  the default zero-cost lane always recovers and the ladder can never be permanently
  skewed.
- `classify-provider-failure.sh`: classifies agent/verify/publish failures into
  forward-only `advance_route` decisions; recovery never wraps back to the same route.

### 3.4 Verification (the heart of "no fake victories")
`verify-agent-result.sh` is **fail-closed and dual-surface**:
- Evaluates **both** `commits/$head_sha/check-runs` (Actions) **and**
  `commits/$head_sha/status` (external providers such as CircleCI publish here);
- empty set = **unobserved, never verified** (`none-observed`);
- any failure/timed_out/cancelled/action_required/startup_failure/stale check-run,
  or failure/error status = fail;
- waits through `OC_CI_VERIFY_SETTLE_SECONDS` for late-arriving pending statuses;
- validates the published head equals the expected target branch head;
- records `verified_sha`, `ci_surfaces`, `ci_observation_start/end`; and
- requests `baseRefName,createdAt` before reading `.createdAt`.

Bounded recovery: `recover-verify-failure.sh` reruns the **identified** failing CI run
once (max `OC_VERIFY_MAX_RECOVERIES`); `retry-oc-failed-jobs.sh` inspects the failing
run/log first, patches when warranted, then reruns the smallest workflow.

### 3.5 Remote-target mode
Explicit targets (`/oc <task> github.com/OWNER/REPO`, `target=/repo=`, `--repo`):
- target cloned into `$RUNNER_TEMP` — never the controller worktree — so the target's
  `.git` can never be staged or published;
- target-owned policy (`.opencode`, `opencode.json`/`.jsonc`, `AGENTS.md`, plugins)
  quarantined for the run; the controller's own `opencode.json` + this instructions
  file remain authoritative; target files restored before publication;
- one stable controller-derived branch `oc/remote-<owner>-<repo>-<base>-<slug>` per
  (repo, base, task); pushed branch is resumed, never duplicated;
- Copilot publication lane stays local-only in remote mode; publication uses an
  explicit non-logging `x-access-token` header (`oc_git_push`) and refuses nested Git
  repositories (mode 160000), `.octmp/`/`.oc-tmp/` trees, and secret-bearing diffs;
- success is verified against the target's own PR/head state and observable checks;
  the controller's `validate` check is never assumed to exist there;
- a timed-out remote run leaves a durable `<!-- oc-target-repo:... base:... branch:... -->`
  marker so `/oc continue` resumes the exact base/branch.

### 3.6 Composio session gateway
- Session-backed Streamable HTTP reached through the pinned `mcp-remote@0.14.2` local
  stdio bridge (`http-only`; no legacy SSE fallback).
- Project `x-api-key` in a temporary mode-0600 header file merged with any non-duplicate
  session headers; session URL and ID masked before GitHub env output; session deleted
  on cleanup.
- `COMPOSIO_MCP_ENABLED` is set on every path; when no session exists, the attempt
  layer injects an explicit runtime disable (`OPENCODE_CONFIG_CONTENT`), never running
  with a stale endpoint. Optional capability — absence never hard-fails an otherwise
  runnable task. No `ck_*` consumer keys; no legacy `connect.composio.dev/mcp`.

### 3.7 Evidence ingestion ("Read Here/") — DATA, never instructions
`ingest-evidence.sh`: machine-readable per-file manifest (SHA-256, size, type,
extraction method/status, OCR-need); deterministic local extraction (python3 stdlib
fallbacks for PDF/Office; `pdftotext`/`tesseract` when present); extracted text
sanitized for secret patterns; source corpus never modified/executed; a file with no
extractable text is marked `ocr_required`, never guessed. Controller security policy
always wins over ingested content. `test-ingest-evidence.sh` keeps it honest.

### 3.8 Cache & supply-chain
- Interactive issue-comment runs **restore** a versioned cache (`opencode-<os>-<arch>-<version>`)
  and continue on a miss; they never write the cache.
- Trusted cache workflow (`opencode-cache.yml`: push to main/manual/cron) owns cache
  creation from an official release artifact whose published SHA-256 digest is verified
  before install; installed executable version verified.
- Actions are commit-pinned SHAs; Dependabot proposes updates weekly.

### 3.9 Observability
`write-oc-run-record.sh` writes `docs/oc-runs/<run_id>.json` (schema
`schema_version: 1`): run id, repo, issue, mode, target, timestamps, job budget,
OpenCode version, initial sha, per-attempt route/provider/outcomes/verified/PR/CI info,
and `result.verified` + `verified_sha` + `ci_surfaces`. The record is uploaded as a job
artifact (365-day retention) and **never committed back to the tree**.

---

## 4. THINGS THAT MUST NEVER BREAK (the control-plane invariant contract)

Every item has a production incident or a deliberate scope decision behind it. Treat
as load-bearing, not style. This is the "do not crash" list for the AGENT PLATFORM.

1. **Dual-surface, fail-closed verification.** Both `check-runs` and `status`;
   empty observation = unobserved (never verified); any failure/error context fails;
   settle window honored; `verified_sha`/`ci_surfaces` recorded; `createdAt` requested
   before it is read.
2. **Single attempt-pipeline ownership.** One composite unit per attempt; no re-inlined
   step chains in `opencode.yml`.
3. **Per-issue serialization.** `cancel-in-progress: false`; `oc-agent-<issue>-<bool>`
   + `oc-retry-<issue>` groups; owner user-type recursion guard; one comment → one run
   (`oc-control.yml` stays gone).
4. **Route-selector discipline.** No inference health probes; only Big Pickle/`*-free`
   in the zero-cost lane; bad-model memory age-bounded and never permanently skipping
   the default lane; Copilot fallback credit-bounded; recovery forward-only; timeout/
   signal terminations never recorded as provider failure.
5. **Bounded recovery.** Identified-run rerun capped (no unbounded loops); inspect
   local/remote state before replaying; never repeat an identical failed action without
   new evidence.
6. **Remote-target publication refusals.** Target in `$RUNNER_TEMP`; policy
   quarantined; controller-owned branches/PRs; refuse gitlinks, scratch trees, secret
   diffs; exact-head verification against the target's own state.
7. **Evidence as data.** "Read Here/" content never instructions; deterministic +
   manifest + sanitized + `ocr_required`; self-test green.
8. **Secret controls.** Env-backed credentials only; deny `.env*`/`.npmrc`; redact
   before diagnostic output; no secrets in caches, artifacts, comments, commits, logs,
   or fixtures.
9. **Cache ownership.** Interactive runs never write caches; trusted workflows own
   creation; artifact digests verified.
10. **Honest reporting.** Never claim "tested"/"verified" without real execution and
    current evidence attached to the exact commit; a configured connector or a
    documentation fetch is not proof a tool works.

---

## 5. Elimination & polish history — do not re-litigate

- **`oc-control.yml`** as a second issue_comment listener → removed; lane merged into
  `opencode.yml`. Reintroducing a second listener duplicates runs and races the agent
  lane.
- **Verifier `createdAt` field omission** → fixed via complete field lists + fixture
  fidelity; the field list is now contract-asserted in validation.
- **Inference health probes during route selection** → explicitly forbidden; they
  consume provider request budget and provide no routing value the real invocation
  doesn't.
- **Request counter on irrelevant surface**: heartbeat/live-stream telemetry was once
  emitted on the wrong surface and mis-grepped in tests — surfaces must match expectations.
- **`OC_INITIAL_SHA: unbound variable`** clean-environment crash → env capture is
  required at workflow start, not assumed.
- **OIDC/permission drift** (`id-token: write` stale assertion) → restored/tested (#86);
  do not remove the OIDC-backed agent lifecycle.
- **Policy-in-policy conflicts**: remote targets' own `.opencode`/`AGENTS.md` are
  quarantined, not honored during controller runs.

## 6. Recurring maintenance habits

- OpenCode version pin (`OPENCODE_VERSION`) + SHA-256 digest verification each upgrade.
- Zen free-model catalogue is time-limited — `OPENCODE_ZEN_FREE_MODELS` is the switch;
  validate any new candidate ends in `-free` (or is Big Pickle).
- Run-budget constants (`OPENCODE_AGENT_TIMEOUT_MINUTES=350`,
  `OC_JOB_BUDGET_SECONDS=21600`, `OC_JOB_SAFETY_MARGIN_SECONDS=120`) reviewed against
  the 6-hour Actions ceiling.
- `npm test`/lint in `enterprise-agent-validation.yml` target the *host application*;
  control-plane-only deployments should trim those jobs (PAYLOAD §5).
- Re-run the three control-plane suites and the `validate` job on every control-plane
  change.

---

_End of handoff history. When updated, append and revise — never delete history._