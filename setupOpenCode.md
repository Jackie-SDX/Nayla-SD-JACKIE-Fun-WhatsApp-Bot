# 🤖 Setup OpenCode on Your Account

> Type `/oc fix that bug` on a GitHub issue, grab a coffee ☕, and come back
> to a tested, verified Pull Request. No magic. No fees. **This is the exact
> setup this repo runs right now.**

Everything lives inside **GitHub Actions** and runs on OpenCode Zen's **free
models** — so your wallet stays calm. 💸🚫

---

## 📦 What You're Building

| Capability | What it does |
|---|---|
| 🧠 Reads your request | The full issue thread, not just one line |
| ✍️ Makes the change | On an isolated branch |
| 🧪 Tests it | Runs your suite before anything ships |
| 🔎 Verifies | Only claims success if CI actually passes |
| 🎉 Opens the PR | Ready to merge, branch and all |

---

## ✅ What You'll Need

| Item | Required? |
|---|---|
| GitHub account with **Admin** on the repo | ✅ |
| OpenCode Zen API key (**free**, ~2-min signup) | ✅ |
| GitHub Personal Access Token | ✅ |
| Copilot / Composio keys | ⬜ Optional, fun upgrades |

---

## 📋 Step 1 — Copy the Files

Copy these from this repo (download ZIP or `git clone`):

```
opencode.json                          ← the brain ⚙️
.opencode/instructions.md              ← the robot's rulebook
.opencode/agents/critic.md             ← hostile code reviewer
.github/workflows/*.yml                ← the /oc engine 🏗️
.github/scripts/*.sh                   ← routing, verifying, cleanup
.github/dependabot.yml                 ← auto-updates your Actions 🧑🍳
```

**Tweak two files:** `enterprise-agent-validation.yml` (the files/tests it
gates — make them match *your* project) and `.github/CODEOWNERS` (change
`@Jackie-SDX` to you).

---

## 🔑 Step 2 — Get Your Keys

**Key #1 — OpenCode Zen (free):** grab your key at
**[opencode.ai/auth](https://opencode.ai/auth)**. It unlocks the free lane:
`opencode/big-pickle` (+ `mimo-v2.5-free` as backup).

**Key #2 — GitHub token:** Settings → Developer settings → **Fine-grained
token** → repo access → **Contents, Pull requests, Issues, Actions: read/**
write (Metadata: read). Use it as `UNIVERSAL_TOKEN`. A classic PAT with the
`repo` scope works too. 😎

**Key #3 (optional) — Copilot:** a token farms work to the Copilot CLI lane,
capped at **60 credits** a run. Skip if you don't have it.

**Key #4 (optional) — Composio:** 500+ integrations (web search, browser,
research agents). Grab one at **[composio.dev](https://composio.dev)**.

---

## 🔐 Step 3 — Add Secrets

Repo → **Settings → Secrets and variables → Actions → Secrets**:

| Secret | Required? | What goes in it |
|---|---|---|
| `UNIVERSAL_TOKEN` | ✅ | Your GitHub PAT |
| `OPENCODE_API_KEY` | ✅ | Your Zen key |
| `COPILOT_GITHUB_TOKEN` | ⬜ | Copilot token (skip if none) |
| `COMPOSIO_API_KEY` | ⬜ | Composio key (skip if none) |

No `.env`, no keys in code. Everything sleeps encrypted in GitHub's vault. 🔒

---

## 🎛️ Step 4 — Variables (Optional)

Same menu, **Variables** tab — tuning knobs, defaults are fine:
`OPENCODE_ZEN_FREE_MODELS` (default `big-pickle,mimo-v2.5-free`),
`COMPOSIO_USER_ID`, `OPENCODE_VERSION`. Skip at will; the defaults work. 🎛️

---

## 🚀 Step 5 — Push & Celebrate

```bash
git add .
git commit -m "chore: summon the opencode agent 🧙"
git push origin main
```

Then run **Actions → opencode-cache** once so the binary is warm for future
runs. Done! ✅

Your first summoning — open an issue and type:

```
/oc Add a feature that sorts the leaderboard entries
```

…and watch the robot army deploy itself. 🫡

---

## 💬 How to Use It

The UI is **a comment** — and only *you* (the repo owner) can summon it.

| Command | Does |
|---|---|
| `/oc explain this` | Read the thread, explain it |
| `/oc fix this` | Branch → code → test → verify → PR 🎉 |
| `/oc retry failed jobs` | Rerun **only** the failed CI jobs |
| `/oc continue` | Resume after a timeout checkpoint |
| `/opencode ...` | The full-name alias |

Even **line-level comments** on a PR count — the agent gets file, line, and
diff context. Precision Swiss engineering. 🇨🇭

---

## ⚙️ How the Machine Works

```
/oc comment (owner only)
   └─▶ OpenCode runs (≤6h, Ubuntu)
         ├─▶ Verified release, SHA-256 checked (cache-first)
         └─▶ Free-model ladder: big-pickle → mimo-v2.5-free → Copilot (60-credit cap)
               └─▶ opencode github run · secrets redacted from logs
                     ├─▶ verify-agent-result.sh polls diff / tests / CI (≤20 min)
                     │     └─▶ reconcile duplicate PRs → 🎉
                     └─▶ failure? classify & exclude that provider → retry (max 3×)
```

**Three golden rules:** 1) **no fake victories** — success only after tests
and CI genuinely pass 📏. 2) **failures are teachers** — broken providers get
banned and the task moves down the ladder, never a blind rerun. 3) **timeouts
leave breadcrumbs** — a checkpoint comment so `/oc continue` resumes without
duplicating work. 🍞

---

## 🛡️ Security & Guardrails

- Owner-only trigger · `share: disabled` · `.env` files unreadable.
- Secrets **redacted** from every log; sensitive files never publish.
- Temp sessions and files cleaned up on every path, even failure.
- Agent works on an isolated `opencode/issue<N>` branch — `main` stays
  protected.

---

## 🚑 Troubleshooting (the usual suspects)

| Symptom | Fix |
|---|---|
| Nothing happened | Comment wasn't `/oc…` and/or not from *you* |
| "No configured agent route" | `OPENCODE_API_KEY` missing → Step 3 |
| PR checks failing | Update the validated files in `enterprise-agent-validation.yml` |
| Run timed out ~5h | By design → read checkpoint, reply `/oc continue` |

---

## 📜 The Fine Print

- **Dogfood alert:** this very document was produced by the system it
  describes. 🐕→🍽️
- Free Zen models are free *for a limited time* — `OPENCODE_ZEN_FREE_MODELS`
  is your switchboard when that changes.
- Big runs eat **Actions minutes** — plenty on the public free tier, keep an
  eye out on private repos. ⏳
- **Dependabot** ships weekly Action-update PRs — merge like a diligent
  landlord. 🏠
- Too heavy for you? `opencode github install` spins up the 2-minute minimal
  version. This repo is the *luxury edition*.

---

## 🎬 Fin

```
copy files → grab 2 keys → paste Secrets → push → /oc <task> → 🎉
```

You're now the proud owner of a **free-range, self-verifying, self-healing AI
software engineer** that answers to a single comment. Go forth, type `/oc`,
and may your Pull Requests be ever green. 💚

*— Written by the robot it describes.*