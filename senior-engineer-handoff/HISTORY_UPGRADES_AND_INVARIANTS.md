# PROJECT HISTORY — UPGRADES, INCIDENTS & THINGS THAT MUST NEVER BREAK

> Handoff companion to `PROMPT_FOR_SENIOR_ENGINEER.md`. Read this before the prompt
> and before any code. It is the written memory of this repository: what was built,
> fixed, deferred, and deliberately refused — and the load-bearing decisions that must
> survive every future change.
>
> Evidence convention: `[FACT]` = directly observable from this repo/CI/docs;
> `[INFERRED]` = reasoned from facts, not directly observed. Line/citation anchors are
> against `NAYLA_PROJECT_DOCUMENTATION.md` (the product doc) and `docs/*.md` (the
> control-plane docs) unless noted otherwise.
>
> Snapshot HEAD for this handoff: `4e354440b0cd195861dde6cec1beb4ea4b35dcc2`.

---

## 1. What this repository is [FACT]

One tree, two systems, deliberately operated by an autonomous agent:

1. **The product** — the "Nayla" WhatsApp companion bot (`index.js`, 5400 lines, single
   file): Baileys multi-device session, MongoDB persistence, multi-provider AI failover,
   image/vision/audio/emoji/gamification features, per-chat "vibe" memory.
2. **The control plane** — a GitHub-Actions "autonomous software engineer" platform:
   `/oc` issue comments trigger OpenCode agent runs with a zero-cost model ladder,
   evidence-based verification, remote-target isolation, bounded recovery, and CI
   regression suites. This is the thing that produced this very handoff.

Git history is squashed to a single commit (`72a04739…` earlier; now `4e35444`), so all
"history" below is reconstructed from GitHub-side artifacts (issues, PRs, docs,
workflow evolution) and the surviving audit docs. The repository is public. No branches
are protected at the GitHub settings level, but `main` is treated as a protected,
production line by policy — `CODEOWNERS` = `* @Jackie-SDX`, Dependabot covers GitHub
Actions + npm, and `enterprise-agent-validation.yml` gates all `audit/**`, `feature/**`,
`fix/**`, `oc/**` branches with a `validate` job.

---

## 2. The product: how it evolved (v1 → v4)

The product doc preserves history by *appending, never deleting* (v4 is the current
version). Summary of the arcs, each one a real production incident that became an
invariant:

- **Multi-provider AI failover (§5)** — up to 10 rotating keys per provider, a
  provider chain (Groq → Gemini cluster → OpenRouter), per-provider **cooldown** with
  two tiers: 60s for transient timeouts, **30 min for auth failures** (§18.11,
  a permanently bad key won't fix itself). An overall **hard deadline** bounds the
  worst-case wait.
- **Reliability / crash-safety (§7)** — the origins of nearly every invariant:
  - §7.1 `runHeavyTask()` concurrency limiter (bounded queues — the load-shedding guard).
  - §7.2 timeouts were the **root cause of the worst production incident**; external
    calls without explicit timeouts are the file's most-replayed failure mode (§13.6).
  - §7.3 the **"zombie process" fix** — deliberately-crashed-on DVD state; a handful of
    specific fatal errors are legitimate exceptions to "never crash" (§14).
  - §7.4 `sock.sendMessage` itself needed a timeout.
  - §7.6 duplicate anti-spam was over-aggressive; §7.7 error classification was
    over-broad; §7.8 the summary rule.
  - §7.9–7.11 **session/connection staleness is its own failure class**: WhatsApp Web
    protocol version drift (405 errors), reconnection backoff + stability confirmation,
    and the periodic full-folder session sync (the "Bad MAC" root fix). A bot can look
    healthy at the application layer and be silently disconnected underneath.
  - §7.12 group-config persistence retry + periodic reverification ("a retry-and-warn-
    honestly pattern beats a single silent attempt").
  - §7.13 raid protection (mass-join detection) + membership cleanup — first automated
    response to a mass-join event.
  - §7.14 command responses now feed conversational memory.
- **Ephemeral storage problem (§3, §3.1)** — Render's filesystem is disposable; MongoDB
  (free M0 ~512MB) is the persistence layer: Baileys session, per-chat memory (archived
  at `ACTIVE_CONTEXT_CAP`), group config, activity logs (TTL 8 days). `.health` reports
  real Mongo usage — storage AND memory cap awareness are design principles (§14).
- **Moderation pivot (§12.6, §20.1)** — the standing decision: **no automated deletion,
  no punitive moderation**. `.ignore` (permanent), two-strike "shut up", and `.mute`
  must be airtight. A real bug once let the duplicate-spam nudge fire *before* all
  silence checks, leaking a message from muted/ignored senders; fixed by ordering the
  duplicate check after every silence check (§20.1).
- **Memory isolation (§12.8)** — facts leaked between a DM and unrelated groups once;
  every memory feature now defaults to the narrowest per-chat/per-sender scope.
- **Identity is not one format (§13.2, §20.2)** — WhatsApp multi-device uses classic and
  `@lid` JIDs; comparisons are LID-aware via `isSelfJid()`/`isJidInList()`. The
  `.kick`/`.promote`/`.demote` self-target guard was a later real bug (§20.2).
- **The single most impactful fix (§20.6)** — `deviceSentMessage` quoting: replying to
  the bot's own messages (which arrive via a linked device, so WhatsApp wraps them in
  `deviceSentMessage`) silently extracted NOTHING for every quote-dependent feature
  (`.eli5`, "what's this?", image analysis…). One line — adding `"deviceSentMessage"`
  to `unwrapMessageContent()`'s `wrapperTypes` — fixed the whole class at once because
  every quoted-content function funnels through that shared helper. A permanent
  diagnostic warning stays behind it (§20.7): treat it as the starting point for the
  next unknown wrapper type.
- **Bare-media placeholders (§18.13, §19.2, §20.4)** — internal placeholder strings
  (`"[image, no caption]"`, `"[sticker]"`, `"[file: …]"`…) are literal text to the AI.
  Video/document placeholders are excluded entirely from the conversation buffer;
  image/sticker/voice placeholders are kept (they carry signal) but must never be pushed
  to a model as a real caption and must not false-trigger the duplicate-spam nudge.
- **Honest decline paths (§15, §18.12)** — PDF/document/video analysis was **explicitly
  deferred** (architecture + disk-lifecycle risk) and the bot honestly declines those
  asks. Server-side fetching of user-supplied URLs was **refused** (SSRF/memory
  surface); only domain-name parsing exists. Video understanding excluded by request.
- **Deliberately NOT built (§15)** — giant hardcoded command menu, "fake awards",
  separate emotion-memory DB, Together/Cohere/CF/HF/DeepSeek providers, full-day
  transcript newspaper, standalone `.bot`/`.info` (aliased to `.health`).
- **TTS (§17.7, §18.9, §18.10)** — ElevenLabs (free tier) → StreamElements fallback
  → plain text. Real OGG/Opus via optional `ffmpeg-static` (mp3+`ptt:true` is provably
  broken in WhatsApp clients); a bad voice-ID edge (free accounts can't use library
  voices) became dynamic voice resolution.
- **Model/gemini upkeep (§18.8, §2.1, §7.9)** — `gemini-2.5-flash` → `gemini-flash-latest`
  alias after confirmed production 404s; Baileys version & WhatsApp Web protocol drift
  are genuine recurring maintenance.

### Known live bugs, still open (§19) [FACT]

| # | Bug | Location/mechanism |
| --- | --- | --- |
| 19.1 | `EMOJI_REGEX` uses a shared **global-flagged regex with `.test()`**, so `lastIndex` carries state between calls → occasional false "no emoji" verdicts when stripping emoji | `applyEmojiPolicy()`, `const EMOJI_REGEX = /\p{Extended_Pictographic}/gu` |
| 19.2 | Duplicate-spam detector keys on the **bare-media placeholder string**, so three uncaptioned photos in a row can trigger the "same message" nudge | `checkDuplicateSpam()` over placeholder `text` |
| 19.3 | Cosmetic leftover naming ("Groq", "Gemini") where the chain is provider-neutral — readability hazard for debugging only | `evaluateMessageWithGroq()`, `recordGeminiFailure()`, old log lines |

### Known recurring bug *patterns* (§13) — read before touching identity, media, or prompts

Never use `Object.keys(content)[0]` to detect message type; always check classic AND
`@lid` JIDs; never put a literal copyable example phrase in an AI system prompt
(13.3); dot-commands with args must not use exact string equality (13.4); reply-target
resolution can resolve to the bot itself (13.5); every external call needs a timeout
(13.6); don't infer a specific root cause from a generic status code (13.7); crash
handlers that swallow everything hide bugs (13.8); shared global regex state travels
(13.9); `unwrapMessageContent()` must know every WhatsApp envelope (13.10); **verify a
pasted third-party AI diagnosis against the real schema before applying it** (13.11 — a
confident, jargon-correct diagnosis was structurally impossible and did nothing).

---

## 3. The control plane: the autonomous-agent era [FACT]

Reconstructed from PR/issue evidence and the surviving audit docs
(`docs/PROJECT_HISTORY_AND_ARCHITECTURE.md`, `docs/ENTERPRISE_AGENT_AUDIT.md`,
`docs/HYBRID_AGENT_ARCHITECTURE_AUDIT.md`, `docs/GITHUB_NATIVE_COPILOT_AUDIT.md`,
`docs/CONCURRENCY_AND_ISOLATION_AUDIT.md`). PRs merge to `main` unless noted.

**Bootstrap:** PR #2 free-model failover → #8–#11 release-digest normalization,
quota-safe routing, Copilot-CLI-native runtime + Copilot fallback lane → #12–#22 OpenCode
Zen primary restored + Composio MCP bootstrap finalized (session-backed Streamable HTTP,
project API key, bound automation user) + crawler hardening → #24–#28 multi-model agent
council, verified-publication requirement (#33).

**Collaboration era ("HYBRID"):** #36–#38 OpenCode + Copilot in one loop, wrapper-owned
completion markers; documented in `HYBRID_AGENT_ARCHITECTURE_AUDIT.md` +
`GITHUB_NATIVE_COPILOT_AUDIT.md`.

**Enterprise control-plane hardening:** #27/#45 current enterprise shape (recovery
architecture, evidence ledger, cache architecture, `ENTERPRISE_AGENT_AUDIT.md`) →
#49–#51, #54 recursive recovery repair, credential protection, long-running checkpoints
→ #56 `oc-enterprise-e2e-self-test.yml` → #58 bot-comment recursion guard (login +
user-type filter) → #60 verifier status to the final gate → #61 `enterprise-agent-
validation.yml` validates all agent branches on push → #63/#65 `setupOpenCode.md` →
#66–#68 **central remote-target repository mode** (target cloned into `$RUNNER_TEMP`,
policy quarantined, controller-owned branch + publication, exact published-head
verification).

**Most recent hardening (the current personality):**

- PR #76 merged the demo-loop regression test and exposed a verifier prefix-only bug —
  the verifier now also accepts scan-derived PR candidates from the issue-comment window
  and treats all-skipped check sets as never-verified.
- **The verifier `createdAt` incident (#71-era):** the `check_pr` verifier read
  `.createdAt` without requesting it in the `gh pr view --json` field list; the CLI
  omitted the field, so healthy PRs were rejected (a false CI failure), which flipped a
  route on and caused a **wasteful full re-run of the same successful task**. The
  regression fixtures missed it because the fake `gh` returned the field. PR #78
  (the first fix) was closed unmerged; the broader **PR #79 hardening** (live streaming
  + heartbeat, job-relative timeouts, forward-only route recovery, regression tests,
  telemetry) replaced it and merged at `80b7bf2`.
- **PR #88** — the crawler resilience benchmark: `scanAnchors()` consumed a later
  closing `</a>` after an unclosed anchor (swallowing healthy links), fixed with a
  `/malformed-anchor` fixture, plus `enterprise-agent-validation.yml` contract repairs
  that made the CI surface truthful again. Merged as the current HEAD `4e35444`.
- **PR #89-era runs (this thread):** the agent stayed on route 1 (`opencode/big-pickle`)
  for ~27 min, found the `scanAnchors()` bug, recovered from three real CI failures, and
  was independently audited via a ChatGPT shared chat — which caught the verifier bug
  (above), rated run `35661872936` 9.7/10, and used this very comment stream as a
  live-log demonstration.

### Control-plane architecture — current shape [FACT]

- **Trigger:** `opencode.yml` is the **single** `issue_comment` listener
  (`oc-agent-<issue>-<true|false>` agent lane with `cancel-in-progress: false`,
  command-aware so workflow-generated comments skip instantly; merged `oc-retry-<issue>`
  retry lane; owner user-type recursion guard; `oc-control.yml` must NOT return as a
  second listener).
- **Attempt pipeline:** every ladder attempt is ONE composite unit
  (`.github/actions/oc-attempt/action.yml` → `run-attempt-pipeline.sh`): branch prep,
  agent run, publication, verification, classification, model-memory recording each run
  exactly once per attempt. Software state surfaces via composite outputs +
  `write-oc-run-record.sh` observability record (job artifact, never committed).
- **Route ladder:** zero-cost OpenCode Zen first (`OPENCODE_ZEN_FREE_MODELS`,
  default `big-pickle,mimo-v2.5-free`; the selector accepts Big Pickle or `*-free`
  IDs only), optional Copilot CLI fallback bounded by `COPILOT_MAX_AI_CREDITS`. Route
  selection performs **no inference health probes**. Failed model IDs are remembered in
  `OPENCODE_BAD_MODELS` but only while fresh (`OPENCODE_BAD_MODELS_MAX_AGE_HOURS`,
  default 24h) so the default zero-cost lane always recovers.
- **Verification:** `verify-agent-result.sh` (546 lines) is **fail-closed and
  dual-surface**: it checks BOTH `commits/<sha>/check-runs` AND `commits/<sha>/status`
  (external providers like CircleCI publish via statuses, not Actions check-runs), treats
  an empty set as unobserved, fails on any failure/timed_out/cancelled/action_required/
  startup_failure/stale or error context, waits through a settle window
  (`OC_CI_VERIFY_SETTLE_SECONDS`) for late statuses, and records
  `verified_sha`/`ci_surfaces`/observation boundaries. It requests `createdAt`
  explicitly before reading it. Bounded recovery: `recover-verify-failure.sh` reruns the
  identified CI run at most `OC_VERIFY_MAX_RECOVERIES`; `retry-oc-failed-jobs.sh`
  inspects the failing run first, patches when warranted, then reruns the smallest
  workflow. No identical failed action is replayed without new evidence.
- **Remote targets:** `/oc <task> github.com/OWNER/REPO` — target cloned into
  `$RUNNER_TEMP`, `.git` never staged, target policy quarantined for the run, one stable
  controller-derived branch per (repo,base,task), Copilot lane local-only in remote
  mode, publication refuses gitlinks, `.octmp`/`.oc-tmp` trees, and secret-bearing
  diffs, verifies against the target's own PR/head state. Timed-out remote runs leave a
  durable marker comment so `/oc continue` resumes the exact base/branch.
- **Composio:** session-backed Streamable HTTP MCP via pinned `mcp-remote@0.14.2`
  http-only local stdio bridge; project `x-api-key` header in a mode-0600 temp header
  file (deleted in cleanup); session/URL/ID masked; optional — its absence never
  hard-fails an otherwise runnable task; no `ck_*` consumer keys, no legacy endpoint.
- **Evidence ingestion ("Read Here/")**: `ingest-evidence.sh` produces a SHA-256
  manifest, extracts deterministically and locally (pdftotext/tesseract/python-stdlib),
  sanitizes secrets, marks unextractable files `ocr_required`, never executes or
  modifies the corpus. Controller security policy always wins over ingested content.
- **Cache:** interactive issue-comment runs restore a versioned OpenCode cache and
  continue on a miss; only trusted push/manual/scheduled workflows create cache
  entries; release artifacts are SHA-256 verified before install.
- **Secrets:** environment-backed only (`OPENCODE_API_KEY`, `COPILOT_GITHUB_TOKEN`,
  `UNIVERSAL_TOKEN` via Actions secrets for authenticated GitHub ops, Composio keys,
  WhatsApp/DB credentials). `.env*`, `.npmrc` reads denied. Never printed, cached,
  committed, or sent to unrelated services.

---

## 4. THINGS THAT MUST NEVER BREAK (the invariant list)

Every item below has a production incident or a deliberate scope decision behind it.
Treat each as load-bearing, not style. This list is the "do not crash" contract.

### 4.1 Application invariants

1. **No automated punitive moderation; no automated message deletion.** `.ignore`,
   two-strike silence, `.mute` are airtight and ordered before duplicate-spam logic
   (§12.6, §20.1). Manual-only deletion.
2. **Per-chat/per-sender memory isolation.** No cross-chat personal-memory leakage
   (§12.8). Every "memory" feature defaults to the narrowest expected scope.
3. **Bounded concurrency & bounded external waits.** `runHeavyTask()` for long tasks;
   explicit `fetchWithTimeout` on every raw call; per-provider cooldowns (60s/30min);
   overall hard deadline. Unbounded queues/waits are a regression (§5, §7.1–7.4).
4. **MongoDB is the persistence layer; Render filesystem is ephemeral.** Baileys
   session sync, memory archives, group config, activity logs all live in Mongo
   (§3, §7.11). No filesystem-only session persistence.
5. **LID-aware identity.** Always compare both classic and `@lid` JIDs;
   `isSelfJid()`/`isJidInList()` for any self/target check (§13.2, §20.2).
6. **Quote/reply handling through the shared funnel.** `getContextInfo()` +
   `unwrapMessageContent()` (must know every envelope incl. `deviceSentMessage`) +
   `extractTextFromMessage()`. Keep the §20.7 diagnostic warning.
7. **Bare-media placeholders stay internal.** Never pushed to a model as real caption
   text; never misfire duplicate-spam (§18.13, §19.2, §20.4).
8. **PDF/document/video asks get the honest decline.** No server-side URL fetching or
   link-content analysis (SSRF/memory risk, deliberately refused) (§15, §18.12).
9. **Global-flagged regex `lastIndex` misuse stays fixed** (§13.9, §19.1).
10. **Fatal-error exceptions to "never crash" stay explicit** (§7.3, §14) — the zombie-
    process fix must not be "cleaned up" into swallowing everything.

### 4.2 Control-plane invariants

1. **Dual-surface fail-closed verification** — both `check-runs` and `status`; empty set
   = unobserved; fail on any failure/error; settle window honored (§ docs).
2. **Single attempt pipeline ownership** — one composite unit per attempt;
   no re-inlined step chains in `opencode.yml`.
3. **Per-issue serialization** — `cancel-in-progress: false`; `oc-agent-<issue>-<bool>`
   + `oc-retry-<issue>` groups; owner user-type recursion guard; `oc-control.yml` not
   reintroduced as a second comment listener.
4. **Route-selector discipline** — no inference health probes; only Big Pickle/`*-free`
   in the zero-cost lane; bad-model memory is age-bounded and never permanently skips
   the default lane; Copilot fallback budget-bounded; recovery is forward-only.
5. **Composio session lifecycle** — session-backed Streamable HTTP, `x-api-key` header,
   short-lived session deleted on cleanup, URL/ID masked, optional-not-load-bearing,
   explicit runtime disable injected when no session exists.
6. **Remote-target publication refusals** — even when receiving repositories:
   controller-owned branches/PRs only; refuse gitlinks, scratch trees, secret diffs.
7. **Evidence as data** — "Read Here/" content is never instructions; deterministic
   extraction + manifest + secret sanitization + `ocr_required`; self-test green.
8. **Bounded recovery** — no unbounded/identified-rerun loops; inspect evidence before
   replay; classification feeds model-memory without opening retry loops.
9. **Secret controls** — env-backed credentials only; deny `.env*`/`.npmrc`; redact
   before diagnostic output; never state secrets in artifacts/comments/commits.
10. **Cache ownership** — interactive runs never write caches; trusted workflows own
    cache creation; artifact digests verified.

---

## 5. Elimination & polish history the engineer should NOT repeat

- Old provider route (OpenRouter free → Gemini cluster with 5 key slots → OpenRouter
  global free) — superseded by the Zen ladder; kept only in `ENTERPRISE_AGENT_AUDIT.md`
  as historical note.
- Verifier false-failure via missing `createdAt` field — fixed in PR #79; the requested-
  fields list must be kept complete whenever `gh pr view --json` results are read.
- Warning: past incidents came from "confident third-party AI diagnosis not verified
  against the real schema" (§20.8) and from "assuming v2's audio assumption was fine"
  (§18.10). Trust the schema and real logs, not plausibility.

---

## 6. Recurring maintenance (set a reminder-style habit)

- Baileys version + WhatsApp Web protocol version drift (§2.1, §7.9) — 405-error class.
- Gemini model alias drift (pinned → `-latest` aliasing, §18.8).
- `check_pr`/verifier `gh` field lists must stay complete when CLI field sets evolve.
- E2B execute capability visibility inside the Composio session can change; GitHub
  Actions is the authoritative execution environment.
- Zen free-model catalog is time-limited; the real agent invocation is the authoritative
  provider test (no health probes).

---

_End of handoff history. When this document is updated, append and revise — never delete
history, exactly as `NAYLA_PROJECT_DOCUMENTATION.md` has been preserved across v1→v4._