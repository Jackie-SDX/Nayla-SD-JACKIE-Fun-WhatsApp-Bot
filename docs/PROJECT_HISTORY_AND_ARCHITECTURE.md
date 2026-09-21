# Project History and Architecture

Status: RECONSTRUCTED from remote evidence (issues, PRs, docs, git object state) at
commit `72a04739cf24d8a7b65202faf1b28b0782ea8873` (2026-09-21).
Evidence-type convention: `[FACT]` = directly observed/reproducible from this repo;
`[INFERRED]` = reasoned from facts but not directly observable here.

## 1. What this repository is

This repository hosts two things in one tree:

1. **The product**: a WhatsApp companion bot (`index.js`) built on Baileys — chat,
   "vibe" personality memory, web search, image generation, photo/sticker/voice
   handling, movie-mode, gamification, MongoDB-persisted memory. `[FACT]`
2. **The control plane**: a GitHub-Actions-hosted autonomous OpenCode agent platform
   (`opencode.yml`, `oc-control.yml`, `.github/scripts/*`) that turns `/oc` comments
   into evidence-backed autonomous engineering runs. `[FACT]`

## 2. Repository lineage

- Repository facts: `[FACT]` not a fork, no parent repository, created 2026-07-05.
- Git history: `[FACT]` squashed to a single commit `72a04739cf24d8a7b65202faf1b28b0782ea8873`
  ("fix(oc): verify remote target by exact published head"). Therefore no previous
  commit history is recoverable from git; history below is reconstructed from
  GitHub-side artifacts (issues, PRs, docs, workflow evolution).
- No tags or releases exist. `[FACT]`

## 3. Autonomous-agent era timeline (workflow evidence)

All PRs below merge to `main` and are listed with merged-At where observable `[FACT]`.
From 2026-09-20 the repository shows an accelerating, tightly-coupled hardening arc.
The timeline is inferred from PR order/titles plus the surviving doc audits
(`ENTERPRISE_AGENT_AUDIT.md`, `GITHUB_NATIVE_COPILOT_AUDIT.md`,
`HYBRID_AGENT_ARCHITECTURE_AUDIT.md`).

### 3.1 Platform bootstrap (top of history)
- PR #2 `feat: harden OpenCode enterprise agent with free-model failover` — early
  enterprise agent with zero-cost model failover. `[FACT]`
- PRs #8–#11: OpenCode release digest normalization, reactive quota-safe provider
  routing, Copilot-CLI-native runtime, Copilot fallback lane. `[FACT]`
- PRs #12–#22, #9: OpenCode Zen primary agent restored with GitCopilot fallback;
  Composio MCP bootstrap finalized end-to-end (session-backed Streamable HTTP, project
  API key, bound automation user, agentic capability discovery); crawler hardened.
  `[FACT]`
- PRs #24–#28: multi-model agent council and validator alignment with OpenCode
  event/result surface; removal of the legacy production discovery path; verified
  publication requirement (PR #33). `[FACT]`

### 3.2 Council and collaboration era — "HYBRID" document
- PRs #36–#38: OpenCode + Copilot collaborate in one agentic loop; council completion
  markers made wrapper-owned. `[FACT]`
- The `HYBRID_AGENT_ARCHITECTURE_AUDIT.md` doc records the two-agent orchestration
  design. `[INFERRED from doc + PR #36]`
- The `GITHUB_NATIVE_COPILOT_AUDIT.md` doc covers the Copilot CLI native execution lane
  and credit bounding. `[INFERRED]`

### 3.3 Enterprise control-plane hardening — "ENTERPRISE" document
- PR #27 `feat: harden OpenCode automation into enterprise control plane` and PR #45
  `feat: elevate autonomous agentic runtime`: the platform took its current enterprise
  shape (recovery architecture, evidence ledger, cache architecture,
  `ENTERPRISE_AGENT_AUDIT.md`). `[FACT]`
- PRs #49–#51, #54: recursive recovery repair, credential protection, long-running
  autonomous recovery with checkpoints. `[FACT]`
- PR #56 `enterprise e2e self-test regression harness`: `oc-enterprise-e2e-self-test.yml`
  (application test + package-name invariant). `[FACT]`
- PR #58 prevents bot-authored comment recursion (owner/login + user-type filter).
  `[FACT]`
- PR #60 exports verifier status to the final gate; PR #61 validates agent branches on
  push (`enterprise-agent-validation.yml`). `[FACT]`
- PRs #65/#63 `setupOpenCode.md`: a condensed /oc setup guide for friendly users.
  `[FACT]`
- PRs #66–#68 `central remote-target repository mode`: `/oc <task> github.com/O/R`,
  controller-owned branch + publication, and the exact published-head verifier
  (PR #68 = the current squashed HEAD). `[FACT]`

## 4. Acceptance and E2E benchmark issues (the audit trail)

Closed issues (all closed, no PR attached) mark completed acceptance loops:
- #23 REPO AUDIT, #44 /oc acceptance — mini enterprise repository audit, #46 /oc
  recursive acceptance, #55 autonomous enterprise recovery benchmark, #59 final
  no-recursion acceptance, #62 BASIC_TEST. Open: #64 remote-target mode feature,
  #69 CPP PROJECT, #71 AUTONOMOUS CODER (this mission). `[FACT]`
- Dependabot PRs #3–#7 (unmerged) cover github-actions/actions version bumps and npm
  dependency front-runners (pino, groq-sdk, sharp, mongoose). `[FACT]`

## 5. Application architecture (surviving product evidence, index.js)

`[FACT]` as directly read from `index.js` comments and code:
- Baileys multi-device WhatsApp session (LID identity handling), MongoDB persistence;
  Render filesystem is ephemeral and never treated as durable storage.
- AI provider chain with automatic failover when a provider is busy; per-chat rolling
  ~50-message conversation memory (`ACTIVE_CONTEXT_CAP`), archived to MongoDB at cap,
  per-chat Map keyed by `jid`, cleaned up on bot removal; "vibe" (personality) memory
  + capped per-chat facts; Mongo TTL archiving.
- Load-shedding guard bounds queue growth; bounded external calls; media placeholders
  handled without regressions (quoted image fix); no automated deletion; no punitive
  moderation; manual-only deletion.
- Image generation / movie mode / gamification (best-effort, non-critical).

## 6. Control-plane architecture (current, as verified)

- Trigger layer: `opencode.yml` (main agent) + `oc-control.yml` (`/oc retry failed jobs`)
  + `enterprise-agent-validation.yml` (validate job on `audit/**`,`feature/**`,`fix/**`,
  `oc/**`) + `oc-enterprise-e2e-self-test.yml` (app tests) + `opencode-cache.yml`
  (versioned OpenCode cache, digest-verified).
- Route selector: zero-cost OpenCode Zen ladder
  (`OPENCODE_ZEN_FREE_MODELS` = `big-pickle`, `mimo-v2.5-free`) → optional Copilot CLI
  bounded by `COPILOT_MAX_AI_CREDITS`. Recovery is time/evidence-bounded.
- Verification: `verify-agent-result.sh` now evaluates BOTH `commits/<sha>/check-runs`
  and `commits/<sha>/status` surfaces, fails closed on any failing external provider
  status or check-run, settles pending states for a window, and records
  `verified_sha`/`ci_surfaces`/observation boundaries. See
  `verify-agent-result.sh` and `test-oc-target.sh` regressions.
- Evidence ingestion ("Read Here" mode): `ingest-evidence.sh` + `test-ingest-evidence.sh`
  — deterministic local extraction (SHA-256 inventory, PDF/docx/xlsx/pptx/text/strings,
  OCR-need detection, secret-pattern redaction); never executes ingested content and
  never modifies the source corpus.
- Remote-target mode: target cloned into `$RUNNER_TEMP`, policy quarantined, controlled
  branch per (repo, base, task), controller-owned publication guard (refuses gitlinks
  and `.octmp` scratch), verification against the target repo's own PR/head state.
- Composio gateway: session-backed Streamable HTTP MCP through `mcp-remote` bridge,
  short-lived authenticated session, `x-api-key` project header, session deleted on
  cleanup; optional capability, never a hard-fail for otherwise runnable tasks.
- Concurrency/isolation: same-issue serialization (`cancel-in-progress: false`),
  cross-issue parallelism, unique per-run branches, owner user-type recursion guard,
  per-chat product memory isolation. See `docs/CONCURRENCY_AND_ISOLATION_AUDIT.md`.

## 7. Facts vs. inference ledger

| Claim | Type | Evidence |
| --- | --- | --- |
| Not a fork; created 2026-07-05 | FACT | `gh api repos/.../repo` parent null, created_at |
| History squashed to one commit `72a04739…` | FACT | `git log` single node in fresh clone |
| No tags/releases | FACT | `gh api repos/...` tags/releases empty |
| PR titles/merged state as listed | FACT | `gh api pulls?state=closed` (see §3) |
| Issue titles/state | FACT | `gh api issues?state=all` (see §4) |
| Bot code invariants | FACT | `index.js` source read directly |
| Timeline ordering/dating semantics | INFERRED | PR numbers + merged_at ordering; sequential commit squashes preclude intra-day causal reading |
| Doc documents match described designs | INFERRED | cross-checked 3 audit docs exist and PR numbers align |

## 8. Verification notes

The full verification surface for this report is: pushed PR head verified exactly by the
verifier (`verified_sha`), the `validate` check of `enterprise-agent-validation.yml`
(syntax, file existence, JSON/YAML/JS/Python assertions), and the
`oc-enterprise-e2e-self-test.yml` application suite with the `whatsapp-vibe-moderator`
package-name invariant. Pending/skipped mandatory checks are NOT treated as success.