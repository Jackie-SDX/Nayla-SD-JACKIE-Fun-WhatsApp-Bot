# 🤖 Setup OpenCode on Your Account

## Your Very Own Code-Fixing Wizard, Summoned by a Single Comment

> Picture this: you type `/oc fix that bug on line 200` into a GitHub issue,
> walk away, grab a coffee ☕, and come back to a freshly opened Pull Request
> with the fix already written — tested, verified, and ready to merge.
>
> No magic. No fees. **This is the exact same setup this repository uses.**

This guide walks you through cloning the entire **enterprise-grade `/oc`
agent system** onto one of **your** GitHub repositories, step by step.
By the end, GitHub Actions will be your tireless, free-range AI software
engineer. 🚀

---

## 🎭 Table of Contents

1. [What You're Building](#1-what-youre-building)
2. [What You'll Need](#2-what-youll-need)
3. [Step 1 — Copy the Files](#step-1--copy-the-files)
4. [Step 2 — Get Your Keys](#step-2--get-your-keys)
5. [Step 3 — Configure GitHub Secrets](#step-3--configure-github-secrets)
6. [Step 4 — Configure GitHub Variables (Optional)](#step-4--configure-github-variables-optional)
7. [Step 5 — Push & Celebrate](#step-5--push--celebrate)
8. [How to Use It](#8-how-to-use-it)
9. [How the Machine Works](#9-how-the-machine-works)
10. [Optional Upgrades](#10-optional-upgrades)
11. [Security & Guardrails](#11-security--guardrails)
12. [Troubleshooting](#12-troubleshooting)
13. [The Fine Print](#13-the-fine-print)

---

## 1. What You're Building

A **hybrid, self-healing AI agent pipeline** that lives entirely inside
GitHub Actions. When **you** (the repository owner) drop a comment starting
with `/oc` on any issue or PR, the machine springs into action:

| Capability | What it does |
|---|---|
| 🧠 **Reads your request** | The full issue thread, not just one line |
| 🔍 **Explores the codebase** | Searches, reads, and reasons about your code |
| ✍️ **Makes the change** | Edits files on an isolated branch |
| 🧪 **Tests it** | Runs your test suite before anything ships |
| 🔎 **Independently verifies** | Only declares success if CI checks actually pass |
| 🎉 **Opens a Pull Request** | Complete with title, branch, and description |

All of this runs on **OpenCode Zen's free models** (more on that below), so
your wallet stays as calm as your morning breathing. 💸🚫

---

## 2. What You'll Need

| Item | Required? | Notes |
|---|---|---|
| A GitHub account | ✅ | You need **Admin/Owner** on the target repo |
| A repository (can be new) | ✅ | Public or private both work |
| OpenCode Zen API key | ✅ | **Free** — 2-minute signup, see [Step 2](#step-2--get-your-keys) |
| A GitHub Personal Access Token | ✅ | For `UNIVERSAL_TOKEN` (automated push/PR powers) |
| GitHub Copilot CLI token | ⬜ Optional | Adds a paid-ish fallback lane, 60-credit cap |
| Composio API key | ⬜ Optional | Unlocks 500+ external tool integrations |
| A sense of adventure | 🎉 | 100% recommended, zero cost |

> **Pro secret for public repos:** everything here is *already in this
> repository*. Instead of retyping files, you can literally fork this repo or
> copy-paste the `.github/` directory, `opencode.json`, and `.opencode/`
> folder into yours. ~90% of the work is already done for you.

---

## Step 1 — Copy the Files

Copy these files & folders from this repository into your own repo. You can
grab them right from the GitHub web UI (**Download ZIP**, or clone and
copy):

```
opencode.json                          ← the agent brain configuration
.opencode/
  instructions.md                      ← the agent's operating manual (read me!)
  agents/
    critic.md                          ← a read-only "hostile reviewer" subagent
.github/
  workflows/
    opencode.yml                       ← the main /oc engine 🏗️
    opencode-cache.yml                 ← nightly cache warmer (make it fast ⚡)
    oc-control.yml                     ← /oc retry failed jobs handler
    enterprise-agent-validation.yml    ← guards every PR the agent opens
    oc-enterprise-e2e-self-test.yml    ← self-test on PRs to main
  scripts/
    select-opencode-route.sh           ← picks the best free model
    run-opencode-attempt.sh            ← the (up to 3×) attempt runner
    run-copilot-attempt.sh             ← optional Copilot fallback worker
    publish-copilot-change.sh          ← publishes fallback changes
    verify-agent-result.sh             ← honest truth-detector (no fake wins)
    classify-provider-failure.sh       ← learns from failures, routes around them
    prepare-composio-mcp.sh            ← boots the optional Composio session
    cleanup-composio-mcp.sh            ← always cleans up its toys
    retry-oc-failed-jobs.sh            ← the selective rerun specialist
    post-oc-continuation.sh            ← leaves durable checkpoints on timeout
    reconcile-opencode-result.sh       ← closes duplicate PRs (neat freak)
    validate-application.sh            ← deterministic pre-flight checks
  dependabot.yml                       ← auto-updates your Actions 🧑🍳
  CODEOWNERS                           ← you own everything (rightfully so)
  copilot-instructions.md              ← the fallback worker's rulebook
```

**Two files you'll want to tweak for your repo:**

- `enterprise-agent-validation.yml` — validate (and/or rename) the
  repository-specific files it checks: `NAYLA_PROJECT_DOCUMENTATION.md`,
  `docs/*.md`, `scripts/test-simple-web-crawler.js`, and `npm test`. These are
  the *actual tests* that gate every agent PR, so make them match **your**
  project.
- `.github/CODEOWNERS` — change `@Jackie-SDX` to your own username.

> 💡 **Heads-up about `opencode-cache.yml`:** it writes to GitHub's Actions
> cache. Cache sharing is only for the *same repository,* so it works on your
> repo after a push to `main`. If you ever run from a **fork**, the cache just
> misses and installs fresh — gracefully.

---

## Step 2 — Get Your Keys

### 🔑 Key #1: OpenCode Zen API key (required, and it's FREE)

1. Head to **[opencode.ai/auth](https://opencode.ai/auth)** and sign in.
2. Create your account & copy your **API key** from the dashboard.
3. That's it. That single key unlocks the free model lane:
   - **`opencode/big-pickle`** — the stealth star driver. *Free for a limited
     time while the OpenCode team sleuths out its superpowers.*
   - **`opencode/mimo-v2.5-free`** — backup free model for when Big Pickle is
     busy or sleepy.

> The workflow reads these from the **`OPENCODE_ZEN_FREE_MODELS`** variable
> (default: `big-pickle,mimo-v2.5-free`). Only model IDs that end in `-free`
> or are exactly `big-pickle` are ever accepted for the free lane. Your
> pennies are safe. 🪙

### 🔐 Key #2: A GitHub token (`UNIVERSAL_TOKEN`)

This is the token that powers automated pushes, PR creation, and CI
inspection — the robot's **pushing license**. Go to:

1. **GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**
2. Repository access: **only the target repo**
3. Permissions:
   - **Contents:** Read and write
   - **Pull requests:** Read and write
   - **Issues:** Read and write
   - **Actions:** Read and write
   - **Metadata:** Read (auto-granted)
   - **Checks / Statuses:** Read
4. Generate and **copy the token** (it starts with `github_pat_...`).

> ℹ️ The lazier-but-simpler option: a **classic PAT** with the `repo` scope.
> Fine-grained is the modern, least-privilege choice, and honestly more
> "peak professional" anyway. 😎
>
> ⚠️ If you *don't* set `UNIVERSAL_TOKEN`, the workflow gracefully falls back
> to the default `GITHUB_TOKEN` from the runner — but a dedicated token is
> smoother and more predictable. Your call.

### 🪙 Key #3 (optional): GitHub Copilot fallback token

If your friend happens to have **GitHub Copilot** access, adding a token here
gives you a **third lane**: when both free models are down, the pipeline
farms the task to the GitHub Copilot CLI, capped at **60 AI credits** a run.
To create one:

> GitHub → Settings → Developer settings → **Personal access tokens** (or your
> Copilot CLI's existing token). GitHub Copilot CLI also supports `gh auth
> login` for a smooth token-less experience.

Skip it if you don't have it — the fallback is optional and **never** a hard
requirement.

### 🧰 Key #4 (optional): Composio API key

Composio is your robot's *Swiss Army knife* 🔧 — 500+ external app
integrations (web search, browser automation, research agents, and more)
exposed to the agent via a short-lived MCP session. Grab a key at
**[composio.dev](https://composio.dev)** and connect whatever apps you want
to use. If you skip it, the pipeline simply runs without those tools — no
panic, no warnings that matter.

---

## Step 3 — Configure GitHub Secrets

Now we upload the key ingredients into your repo's vault:

1. Open your repo → **Settings → Secrets and variables → Actions → Secrets**
2. Click **New repository secret** and add each one:

| Secret | Required? | What goes in it |
|---|---|---|
| `UNIVERSAL_TOKEN` | ✅ | Your fine-grained (or classic) GitHub PAT |
| `OPENCODE_API_KEY` | ✅ | Your OpenCode Zen API key |
| `COPILOT_GITHUB_TOKEN` | ⬜ | Copilot fallback token (skip if none) |
| `COMPOSIO_API_KEY` | ⬜ | Composio key (skip if none) |

No JSON files, no `.env`, no keys-in-code. **Everything is encrypted at rest
in GitHub's secret vault** — living its best life, unseen by anyone including
the workflow you're about to run. 🔒

---

## Step 4 — Configure GitHub Variables (Optional)

Same menu, but pick the **Variables** tab. These aren't secrets — they're
tuning knobs the pipeline reads:

| Variable | Default | What it does |
|---|---|---|
| `OPENCODE_ZEN_FREE_MODELS` | `big-pickle,mimo-v2.5-free` | Comma-separated free-model ladder |
| `COMPOSIO_USER_ID` | your username | Which Composio user's tools to use |
| `OPENCODE_VERSION` | *(latest)* | Pin a specific OpenCode release version |

You can literally skip this step entirely and let the defaults do their job.
But it's nice to *know* the knobs exist. 🎛️

> **Also, one tiny install step:** the OpenCode **GitHub App** is what lets
> the agent read the issue/know which repo to work on when using the basic
> setup. This repo's workflow instead passes tokens directly and runs
> `opencode github run` — if you ever switch to the dead-simple path, just run:
>
> ```bash
> opencode github install
> ```
>
> from inside your repo on your machine. (More in [The Fine Print](#13-the-fine-print).)

---

## Step 5 — Push & Celebrate

```bash
git add .
git commit -m "chore: summon the opencode agent 🧙"
git push origin main
```

Then head to **Actions → opencode-cache** and click **Run workflow** once, so
the OpenCode binary gets cached nice and warm for future runs. Done! ✅

**Your first summoning:** open an issue, type:

```
/oc Add a new feature that sorts the leaderboard entries
```

…and watch the tiny robot army deploy itself. 🫡

---

## 8. How to Use It

The entire user interface is **a comment**. Nobody can summon the agent but
**you** (the repo owner) — other accounts' commands are politely ignored, so
random GitHub passers-by can't make your bot do their chores. 😌

| Command | What happens |
|---|---|
| `/oc explain this issue` | Agent reads the thread and replies with a clear explanation |
| `/oc fix this` | Agent creates a branch, implements, tests, verifies, opens a PR 🎉 |
| `/oc delete the cache when A is removed` | Works on existing **PRs too** — comments trigger it right there |
| `/opencode ...` | Same as `/oc` (full-name alias) |
| `/oc continue` | Resume work after a timeout checkpoint |
| `/oc retry failed jobs` | **Selectively** rerun only the failed CI jobs from the last run |
| `/oc fix it https://github.com/OTHER-OWNER/OTHER-REPO` | Run the task against an **external target repository** (remote-target mode) |
| `/oc repo=OTHER-OWNER/OTHER-REPO fix it` | Same remote-target mode via `repo=`/`repository=`/`target=` selectors |
| `/oc --repo OTHER-OWNER/OTHER-REPO --base main fix it` | Remote-target mode with an explicit base branch |

> 💬 You can even comment on a **specific line of code** in a PR's "Files"
> tab — the agent receives the file path, line numbers, and diff context, and
> fixes exactly that spot. Precision Swiss engineering. 🇨🇭

---

## 9. How the Machine Works

Here's the skeleton, in glorious ASCII. This is the secret sauce — copy this
architecture and you get a *self-healing* agent, not just a script.

```
+------------------+     +------------------+     +------------------+
|   /oc <task>     | --> |  /oc <task>     | --> |  OpenCode runs   |
| (comment on      |     |  (you, the      |     |  on Ubuntu-Latest|
|  issue or PR)    |     |  owner, only)   |     |  (up to 6h)      |
+------------------+     +------------------+     +------------------+
                                                       |
                                                       v
                 +---------------------------------.-----------------+
                 |  Resolve verified OpenCode release (SHA-256 checked)|
                 |  Restore from cache or install fresh               |
                 +---------------------------------.-----------------+
                                                       |
                 +-------------------------------------v------------------+
                 |  Route selector: free-model ladder                    |
                 |  1. opencode/big-pickle                               |
                 |  2. opencode/mimo-v2.5-free                           |
                 |  3. github-copilot/auto  (optional, 60-credit cap)    |
                 |  4. none — honest "no route left" warning             |
                 +-------------------------------------+------------------+
                                                       |
                       +-------------------------------+---------------+
                       v                                               v
                 +--------------------------------+      +-------------------------+
                 |  opencode github run           |      |  (fallback) Copilot CLI |
                 |  timeout-controlled, secrets   |      |  sandboxed, no git      |
                 |  redacted from logs            |      |  commit/push/gh/curl    |
                 +--------------------------------+      +-------------------------+
                       |                                                   |
                       v                                                   v
                 +---------------------+          Did CI "validate" pass?  |
                 |  Verified by facts, |<---------+  verify-agent-result.sh |
                 |  not by vibes:      |             polls up to 20 min     |
                 |  - diff check       |                                   |
                 |  - npm test         |                                   |
                 |  - CI check-runs    |                                   |
                 +----------+----------+                                   |
                            |                                              |
              +-------------+---------------+                              |
              v                             v                              |
   +------------------+            +----------------+     failure?  -------+
   | Reconcile        |            | Failure        |     classify & learn:
   | duplicate PRs    |            | classifier     |     exclude the broken
   | (close extras)   |            | (route jumps)  |     provider, try again
   +------------------+            +----------------+     (x3 attempts max)

   Timeout?  -> post checkpoint comment ->  you reply "/oc continue" -> resume
   All fail? -> human handoff comment with sanitized evidence -> you take over
```

### The three golden rules baked into the machine

1. **No fake victories.** The workflow only reports success after it
   *independently* verifies — `git diff --check`, your test suite, and the
   `validate` CI check on the actual PR head commit. "It looked fine" is not
   a conclusion. 📏
2. **Failures are teachers.** If a model is rate-limited or unavailable, the
   failure classifier shrugs, permanently excludes that provider for the
   task, and advances to the next lane. Up to **three attempts**. No blind
   reruns of identical failures.
3. **Timeouts leave breadcrumbs.** If the 5h50m agent budget runs out, the
   pipeline plants a durable checkpoint comment so `/oc continue` can resume
   exactly where it stopped — never duplicating already-made progress. 🍞

### 🌐 Remote-target mode (work on *another* repository)

Add an explicit target to a `/oc` command and the same controller-owned
pipeline operates on an **external** repository:

- The target is cloned into `$RUNNER_TEMP` — never your worktree — so its
  `.git` and policy can never be staged or published by accident.
- The target's own `.opencode/`, `opencode.json`, `AGENTS.md`, and `plugins`
  are quarantined for the run; **your** `opencode.json` and enterprise
  instructions stay authoritative. Target files are restored on publication.
- Work never restarts from scratch: one stable branch
  `oc/remote-OWNER-REPO-base-slug` per (repo, base, task), reused on resume.
- Publication refuses nested Git repositories (mode 160000 gitlinks),
  `.octmp/`/`.oc-tmp/` trees, and secret-bearing diffs, and pushes with an
  explicit single-invocation Authorization header — never a stored credential.
- Success is verified against the **target repository's own PR and CI
  checks**; the `validate` check of *this* repo is never assumed to exist there.
- A timed-out remote run drops a durable
  `<!-- oc-target-repo:... base:... branch:... -->` marker, so a bare
  `/oc continue` resumes that exact target/base/branch.

The GitHub Actions workflow needs write permission on the target repository
for this mode; a short-lived `UNIVERSAL_TOKEN` covering both repositories (or
the target's own token released as `secrets.UNIVERSAL_TOKEN`) makes remote
publication work end-to-end.

---

## 10. Optional Upgrades

### 🧰 Composio — give the agent hands and eyes

Out of the box the agent is a great *reader*. Add `COMPOSIO_API_KEY`
(+ variables) and it becomes an **operator**: web research, browser
automation, document crawling, Slack/Sheets/GitHub actions across accounts —
all through a short-lived, auto-deleted MCP session. Security-wise the
session is scoped to your `COMPOSIO_USER_ID`, the headers file is created at
`0600` perms, and everything is torn down in the `always()` cleanup step.

### 🤫 GitHub Copilot fallback — the third string

Add `COPILOT_GITHUB_TOKEN` and the pipeline gains a fully sandboxed Copilot
CLI lane with a hard 60-credit cap. The fallback worker is *extra* chained —
denied `git commit`, `git push`, `git reset`, `git clean`, `gh`, `curl`, and
`wget` — and any changes it produces go through the same deterministic
validation before they're allowed near a PR.

### ⚡ Cache warming — why wait for downloads?

`opencode-cache.yml` prebuilds the verified OpenCode binary cache on every
push to `main`, on demand, and nightly (00:17 UTC). Your `/oc` runs start in
seconds instead of download-dragging. Speed. Pure speed. 🚄

---

## 11. Security & Guardrails

Because with great agency comes great responsibility:

- 🔒 **Owner-only trigger** — only `github.repository_owner` can `/oc`.
- 🧪 **Every change is tested** before any PR sees the light of day.
- 🏷️ **`share: disabled`** — no OpenCode sessions are shared anywhere.
- 🚫 **`.env` files are unreadable** — the `read` permission denies `*.env`,
  `.env.*`, `.npmrc`. The `bash` permission denies `git reset`, `git clean`,
  branch deletion, and catastrophic `rm -rf`.
- 🛡️ **Secrets are redacted** from every log — API keys, GitHub tokens, and
  Copilot credentials are scrubbed with exact-match *and* pattern-based
  redaction before anything is printed or posted to the issue.
- 🚷 **Sensitive files never publish** — `.env`, keys, and WhatsApp
  `session_auth/` folders are hard-refused by the publication guard.
- ♻️ **Everything cleans up** — temporary MCP sessions, header files with
  `0600` perms, and raw logs are deleted even on failure.
- 🧘 **Branch hygiene** — the agent works on an isolated
  `opencode/issue<N>-...` branch; `main` is treated as a protected
  production line.

---

## 12. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Workflow didn't run | Comment wasn't from *you*, or didn't start with `/oc` | Double-check your account & the leading `/oc` or `/opencode` |
| "OpenCode Zen credential unavailable" | `OPENCODE_API_KEY` missing | Add it in repo Secrets (Step 3) |
| "No configured agent route" | All lanes lacked credentials | Ensure `OPENCODE_API_KEY` (and optionally Copilot token) exist |
| Agent PR has failing checks | Your `enterprise-agent-validation.yml` expectations mismatch your repo | Update the validated file list / test script; then `/oc retry failed jobs` |
| Run timed out at ~5h | Long task, budget reached — *this is by design* | Read the checkpoint comment, reply `/oc continue` |
| "already received a selective failed-job rerun" | You asked to retry twice ⏱️ | Inspect the failing job logs *first*, then decide |
| I ran it on a fork | Cache writes are repo-scoped | Cache misses → fresh install; totally fine, just slower |

---

## 13. The Fine Print

- **This is the same configuration running right now in this repository.**
  This very document was produced by it. It's literally peak dogfooding. 🐕→🍽️
- **Zero-cost lane:** OpenCode Zen models **Big Pickle** and **MiMo-V2.5
  Free** are free — *for a limited time*. The free catalog can change; the
  variable `OPENCODE_ZEN_FREE_MODELS` is your switchboard when it does.
- **Simple alternative:** if you'd rather not carry the full enterprise
  architecture, `opencode github install` spins up a minimal `/oc` workflow
  in ~2 minutes. This repository proves what the *luxury edition* looks like.
- **Actions minutes:** the 6-hour ceiling and 20-minute verify windows
  consume GitHub Actions minutes per run. For public repos on the free tier,
  these are plentiful; for private repos, keep an eye on your allowance. ⏳
- **Dependabot** keeps your pinned Action SHAs current with weekly PRs —
  merge them like a diligent landlord. 🏠

---

## 🎬 Fin

You now have everything needed to clone this system onto your own account:

```
copy the files  →  grab 2 keys  →  paste into Secrets  →  push  →  /oc <task>  →  🎉
```

Your friend is now the proud owner of a **free-range, self-verifying,
self-healing AI software engineer** that responds to a single comment.

Go forth, type `/oc`, and may your Pull Requests be ever green. 💚

*— The OpenCode /oc enthusiast who wrote this with the robot it describes.*