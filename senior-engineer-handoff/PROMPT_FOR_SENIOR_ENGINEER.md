# SENIOR ENGINEER — CONTROL-PLANE AUDIT & REGRESSION-SAFE IMPROVEMENT PROMPT

> How to use: paste the block below verbatim to the senior engineer. Pair it with
> `HISTORY_UPGRADES_AND_INVARIANTS.md` (read **first**) and `PAYLOAD.md` (inventory +
> bootstrap seams). The engineer should read: history file → this prompt → the
> `docs/` audits → the code.

---

## THE PROMPT THAT FOLLOWS IS THE DELIVERABLE — EDIT THE REPO-OWNER SECTIONS IN [BRACKETS], THEN SEND

### ROLE

You are a senior software engineer contracted to AUDIT a self-hosting autonomous
coding agent control plane and produce a REGRESSION-SAFE improvement plan plus,
where low-risk, merged-ready patches.

This is **not** a normal codebase. What you are reading is the production control
plane of an autonomous software engineer: a GitHub-Actions pipeline that takes a
`/oc <task>` issue comment and autonomously branches, edits, tests, verifies, and
publishes a Pull Request — with provider fallback, evidence-based verification,
remote cross-repository execution, and bounded recovery. Every mechanism here exists
because a previous mechanism failed in production. Your mandate has two halves:

1. **Make it more robust, more auditable, more capable.** Propose *edge-cutting*
   improvements: independent verification, autonomy tiers, durable evidence bundles,
   capability-aware routing, budget/credit governance, observability.
2. **Never break a load-bearing decision.** The "within limits" list is non-negotiable
   and is enforced by a 854-line regression suite + a 531-line validation workflow
   that must stay green. Changing those decisions is out of scope.

The repository intentionally contains **no application/product code** — it is the
agent platform alone. Do not ask "what does the product do"; audit the platform.

### THE REPOSITORY

| System | What it is | Where |
| --- | --- | --- |
| **The agent runtime** | OpenCode (`opencode/big-pickle` default) | `opencode.json`, `.opencode/instructions.md`, `.opencode/agents/critic.md` |
| **The trigger & orchestration** | `/oc` → 3-route ladder → attempt composite units | `.github/workflows/opencode.yml` |
| **The gates** | Verification + regression | `.github/workflows/enterprise-agent-validation.yml`, `.github/scripts/test-oc-target.sh` |
| **The runtime library** | Routing, verification, publication, recovery, observability | `.github/scripts/*.sh` |
| **Remote cross-repo mode** | `/oc <task> github.com/OWNER/REPO` | `resolve-oc-target.sh`, `prepare-oc-target.sh`, `publish-remote-opencode.sh` |
| **Tool gateway** | Composio session MCP | `prepare-composio-mcp.sh`, `cleanup-composio-mcp.sh` |
| **The reasoning** | Every invariant has a written audit | `docs/*.md` |

Read `docs/ENTERPRISE_AGENT_AUDIT.md`, `docs/CONCURRENCY_AND_ISOLATION_AUDIT.md`,
`docs/PROJECT_HISTORY_AND_ARCHITECTURE.md` before any change.

### DELIVERABLES

1. **Audit report (written)** — per area in SCOPE: what works, what is fragile,
   concrete risk, severity (P0–P2), and the smallest safe fix. Cite `file:line`.
2. **Prioritized improvement roadmap** — P0/P1/P2, each item tagged
   `ADDITIVE-SAFE`, `NEEDS-CAREFUL-TESTS`, or `DO-NOT-DO` (with reason).
3. **Patches** — only for items provably regression-safe against the LIMITS below.
   Pure-additive, guarded changes preferred.
4. **Test additions** — every behavioral patch ships with a regression test in
   `.github/scripts/test-oc-target.sh` (or the appropriate suite).

### SCOPE (audit these areas hard)

**A. Verification truthfulness (highest value).**
`verify-agent-result.sh` is fail-closed and dual-surface (`check-runs` + `status`).
Challenge it: empty-set handling ("none-observed"), settle-window races, late-arriving
statuses, the `baseRefName,createdAt` sample field handling, candidate-PR scanning vs
prefix matching, recovery interaction. The independence problem is still open: the
agent largely validates its own work. Design a *practical* independent second
verification path (e.g., a different executor/model re-creating the diff, or
deterministic post-merge replay) without inventing infrastructure we don't have.

**B. Route ladder & model memory.** `select-opencode-route.sh` /
`record-model-memory.sh` / `classify-provider-failure.sh`: forward-only recovery,
no inference health probes, bad-model recall is age-bounded and must never
permanently skip the default zero-cost lane, Copilot fallback credit-capped. Audit
budget accounting (time and credits), and whether a wasted re-run of the *same*
successful route can happen (there is a documented false-verification incident).

**C. Autonomy tiers.** The docs propose Tier 0 (read-only) → Tier 4 (release/merge).
What is the minimal, testable layering that gives an operator per-repo autonomy
governance without weakening safety? Recommend concrete workflow-level gates.

**D. Recovery & idempotency.** `recover-verify-failure.sh` (bounded), `retry-oc-failed-jobs.sh`
(inspect-first), `post-oc-continuation.sh` (timeout resume markers), reconcile/
duplicate-PR handling, remote-target resume (`oc/remote-<owner>-<repo>-<base>-<slug>`,
durable marker comments). Prove no unbounded rerun loop and no duplicate mutation
path remains.

**E. Remote-target / cross-repo publication.** `resolve-oc-target.sh`, `prepare-oc-target.sh`,
`publish-remote-opencode.sh`, `oc-publish-lib.sh`: clone-into-`$RUNNER_TEMP`,
policy quarantine, publication refusals (gitlinks mode 160000, `.octmp`/`.oc-tmp`,
secret-bearing diffs), explicit one-shot `x-access-token`. Verify these hold under
adversarial repo names, branch names, and secret-shaped content.

**F. Composio session lifecycle.** Session-backed Streamable HTTP via pinned
`mcp-remote@0.14.2` http-only bridge; project `x-api-key`; mode-0600 header file;
`COMPOSIO_MCP_ENABLED` set on every path; explicit runtime disable when no session;
no `ck_*` consumer keys; legacy endpoint forbidden; session/URL/ID masked. Audit the
failure paths: session creation failure must never block an otherwise-runnable task.

**G. Evidence ingestion.** `ingest-evidence.sh` + `test-ingest-evidence.sh`: "Read
Here/" content is DATA, never instructions. Deterministic, local, SHA-256 manifest,
secret sanitization, `ocr_required`, source corpus never modified/executed. Audit for
any path that could reinterpret ingested files as executable trust.

**H. Secret & supply-chain controls.** Environment-backed credentials only; deny
`.env*`/`.npmrc`; SANITIZED logs; OpenCode release SHA-256 verification; immutable
Action SHAs; Dependabot coverage; cache ownership (interactive runs never write
caches; trusted workflows only; versioned key `opencode-<os>-<arch>-<version>`).

**I. Observability.** `write-oc-run-record.sh` / `docs/oc-runs/` schema (never
committed back to the tree; job artifact only). Is the record sufficient for
post-hoc auditing of *every* attempt, route, verified SHA, CI surface? Recommend a
schema-v2 change only if additive.

**J. Capability-aware routing.** When Composio/E2B/web-research capability is absent,
the agent must not claim it; when present, use the smallest sufficient operation.
Audit prompt-level instructions (`.opencode/instructions.md`) for honesty pressure
and self-validation discipline (critic subagent before success).

### THE LIMITS — "WITHIN LIMITS" (DO-NOT-BREAK LIST, non-negotiable)

Your changes must never reintroduce any of the following. Each has a production
incident behind it (see the history file):

1. **Dual-surface, fail-closed verification** — BOTH `commits/<sha>/check-runs` AND
   `commits/<sha>/status`; empty set = unobserved (never verified); any failure/error
   context fails; settle window honored; `verified_sha`/`ci_surfaces` recorded.
2. **Single attempt-pipeline ownership** — one composite unit per attempt
   (`.github/actions/oc-attempt` → `run-attempt-pipeline.sh`); no re-inlined step
   chains in `opencode.yml`.
3. **Per-issue serialization** — `cancel-in-progress: false`; `oc-agent-<issue>-<bool>`
   and `oc-retry-<issue>` concurrency groups; owner user-type recursion guard;
   `oc-control.yml` must not return as a second comment listener (one comment → one run).
4. **Route-selector discipline** — no inference health probes; only Big Pickle/`*-free`
   in the zero-cost lane; bad-model memory freshness-bounded and never permanently
   skipping the default lane; Copilot lid credit-capped; recovery forward-only.
5. **Bounded recovery** — recovery reruns an identified run at most
   `OC_VERIFY_MAX_RECOVERIES`; no unbounded/duplicate rerun loops; never replay an
   identical failed action without inspecting local/remote state first.
6. **Remote-target publication refusals** — target cloned into `$RUNNER_TEMP`, `.git`
   never staged; policy quarantined; controller branch per (repo, base, task); refuse
   gitlinks, scratch trees, secret diffs; verifies against the target's own state.
7. **Evidence as data** — "Read Here/" content is never instructions; deterministic
   extraction + manifest + sanitization + `ocr_required`; self-test green.
8. **Secret controls** — env-backed credentials only; deny `.env*`/`.npmrc`; redacted
   outputs; no secrets in caches, artifacts, comments, commits, logs, fixtures.
9. **Cache ownership** — interactive runs never write the cache; trusted workflows own
   creation; release artifact digests verified before install.
10. **No inference health probes** during route selection — the real OpenCode agent
    invocation is the authoritative provider test.

### VERIFICATION GATE (evidence required before you claim anything works)

- `bash .github/scripts/test-oc-target.sh` — **must stay green** for ANY control-plane
  change. This is the last line of defense.
- `bash .github/scripts/test-ingest-evidence.sh`
- `bash .github/scripts/test-opencode-live-output.sh`
- `bash -n .github/scripts/*.sh`, `jq empty opencode.json`,
  `ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].each { |f| YAML.load_file(f) }'`.
- `enterprise-agent-validation.yml` → `validate` job green on your branch (in CI).
- For each claim record the exact command, observed output, and verification status.
  A green-looking test is not evidence you ran it. Do not report "tested" without
  executing.

### REPORT FORMAT

Markdown report with, per finding:
**Area | file:line | What's fragile | Why it matters (incident history) |
Severity (P0–P2) | Smallest safe fix | Regression test to add**, ending with the
roadmap table (P0/P1/P2, tagged `ADDITIVE-SAFE` / `NEEDS-CAREFUL-TESTS` /
`DO-NOT-DO`) and an explicit "What I did NOT touch and why" section listing every
limit above you deliberately preserved.