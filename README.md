# OpenCode Enterprise Agent — Control Plane Bundle

> This branch/snapshot contains **only** the OpenCode autonomous-agent control plane.
> The application/product it used to automate (the WhatsApp bot) is deliberately
> **not** included. Everything here is the `/oc` machine: workflows, scripts,
> agent policy, verification, and this hand-off kit.

Sourced from `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot` at snapshot HEAD
`4e354440b0cd195861dde6cec1beb4ea4b35dcc2` (branch
`opencode/issue89-20260922100523`).

## What this is

A GitHub-Actions-hosted "autonomous software engineer" platform. A repo owner types
`/oc <task>` in an issue comment and this control plane:

1. serializes the request per issue (never concurrent, never interrupted);
2. picks a zero-cost model route (`opencode/big-pickle` → `opencode/mimo-v2.5-free` →
   optional Copilot fallback);
3. runs the agent on an isolated branch via verified, SHA-256-checked OpenCode;
4. verifies the result **fail-closed across every observable CI surface**;
5. publishes a PR and reconciles duplicates;
6. records per-run observability and cleans up (Composio session, remote target).

## What's inside

| Area | Path | Purpose |
| --- | --- | --- |
| Trigger & serialization | `.github/workflows/opencode.yml` | Single `/oc` listener + merged retry lane |
| Validation gate | `.github/workflows/enterprise-agent-validation.yml` | 531-line `validate` job gating control-plane branches |
| Cache | `.github/workflows/opencode-cache.yml` | Trusted cache creation (restore-only on interactive runs) |
| Attempt pipeline | `.github/actions/oc-attempt/action.yml` | One-attempt composite unit |
| Runtime scripts | `.github/scripts/*.sh` (27) + 1 `.awk` | Routing, verification, publication, recovery, evidence, observability |
| Agent policy | `.opencode/instructions.md`, `.opencode/agents/critic.md` | The agent rulebook + adversarial reviewer |
| Agent runtime config | `opencode.json` | Model, permissions, Composio MCP, sharing |
| Audit / history docs | `docs/*.md` | The written reasoning behind every invariant |
| Copilot fallback policy | `.github/copilot-instructions.md` | Bounded optional Copilot lane |
| Setup guide | `setupOpenCode.md` | How to install this on a GitHub account |
| **Hand-off kit** | `senior-engineer-handoff/` | PAYLOAD, prompt, history & invariants (start here) |

Deliberately **removed** from this bundle: the WhatsApp bot product files
(`index.js`, `pair.js`, `scripts/`, `NAYLA_PROJECT_DOCUMENTATION.md`, bot
`README.md`, `package*.json`, `eslint.config.js`, `Contact-Author`). See
[`senior-engineer-handoff/PAYLOAD.md`](senior-engineer-handoff/PAYLOAD.md) for the
exact inventory and how to re-integrate.

## Reading order for an incoming engineer

1. `senior-engineer-handoff/HISTORY_UPGRADES_AND_INVARIANTS.md` — what was built, what
   failed, what must never break.
2. `senior-engineer-handoff/PROMPT_FOR_SENIOR_ENGINEER.md` — the audit/improvement
   brief.
3. `docs/` — the audit documents (deep reasoning).
4. The code.

## Verifying this bundle locally

```bash
bash -n .github/scripts/*.sh                          # shell syntax
jq empty opencode.json                                # config parse
ruby -e 'require "yaml"; Dir[".github/workflows/*.yml"].each { |f| YAML.load_file(f) }'
bash .github/scripts/test-oc-target.sh                # control-plane regression suite
bash .github/scripts/test-ingest-evidence.sh          # evidence-ingestion self-test
bash .github/scripts/test-opencode-live-output.sh     # live-output contract test
```

The two workflow-based checkpoints (`enterprise-agent-validation.yml`'s `validate`
job) also gate `npm test`/lint of the *application*, which is absent here — that is
expected and documented in the PAYLOAD.

## Download

Download the branch as a ZIP:

- **GitHub UI:** branch dropdown → this branch → "Download ZIP",
- or Ctrl/Cmd+click the Code → "Download ZIP".

The ZIP is a self-contained control plane; only the hand-off kit added by this
snapshot (the `senior-engineer-handoff/` directory and this README) is not part of
the original repo's `main` tree.