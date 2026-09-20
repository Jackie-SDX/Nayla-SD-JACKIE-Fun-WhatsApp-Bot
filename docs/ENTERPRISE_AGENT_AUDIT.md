# Enterprise OpenCode Agent Audit

Repository: `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot`

Main baseline at audit start:
`93780b5201d613da04072524d8aa84710dbafdf5`

The reactive-provider-routing fix is staged on `fix/reactive-provider-routing` for review before integration into `main`.

## 1. Confirmed cache finding

The original interactive OpenCode path used GitHub Actions cache behavior that could restore but could not reliably write on the low-trust `issue_comment` path.

Observed evidence from a real OpenCode run included:

- cache mode: read;
- cache miss for the versioned OpenCode key;
- cache reservation failure because the token had no writable cache scope.

Conclusion: the interactive issue-comment path must not own cache population.

The hardened architecture therefore separates cache restore from cache population.

Interactive workflow:

- restores a versioned OpenCode cache;
- continues on a cache miss;
- verifies and installs the official release artifact when necessary;
- never performs `actions/cache/save`.

Trusted cache workflow:

- runs on pushes to `main`, manual dispatch, and a daily schedule;
- obtains official OpenCode release metadata;
- verifies the published SHA-256 digest for the Linux x64 archive;
- verifies the installed executable version;
- saves the versioned cache;
- treats cache-save failure as non-fatal.

## 2. Model and quota architecture

The zero-cost route circuit starts with an OpenRouter free Qwen model, then uses the Gemini credential cluster, and ends with the OpenRouter global free router. Route selection is side-effect-free and performs no inference health probes, because probes consume the same scarce free-tier request budget used by real agent calls.

The operational primary free model is qwen/qwen3.8-27b:free.

The requested qwen/qwen3.6-plus-preview:free identifier was live-tested through the connected OpenRouter account during this change and returned HTTP 404 with No endpoints found. It is therefore not hard-coded into the production route.

The operational Qwen replacement was live-tested successfully at zero cost. Its current OpenRouter endpoint exposed tool calling and a 262K context window.

The primary free model is configurable through the repository variable OPENROUTER_PRIMARY_MODEL. The route selector rejects values that are not explicitly suffixed :free, preventing accidental paid-model activation in the zero-cost lane.

The Gemini fallback cluster supports five credential slots: GEMINI_API_KEY, GEMINI_API_KEY_2, GEMINI_API_KEY_3, GEMINI_API_KEY_4, and GEMINI_API_KEY_5.

The Gemini model ladder is Gemini 3.8 Flash, 3.7 Flash, 3.6 Flash, 3.5 Flash, and 3.5 Flash-Lite, each across the five available credential slots.

The final fallback is openrouter/free.

With five Gemini slots, the circuit contains 27 theoretical route positions: one OpenRouter primary, 25 Gemini model/key combinations, and one OpenRouter global free-router fallback.

Separate Gmail accounts can improve quota resilience only when the associated Google credentials/projects have genuinely independent quota accounting and the human is authorized to use them. The Gmail address itself is not the quota boundary, and key rotation does not create unlimited quota or justify bypassing provider restrictions.

## 3. OpenRouter behavior

The configuration uses the OpenRouter model ID `openrouter/free`.

That identifier is a free routing macro, not a deterministic promise that one named model will receive every request. The workflow therefore reports the route as `openrouter/free` unless runtime telemetry provides the underlying model.

The repository deliberately does not hard-code Qwen3.8 Max into the zero-cost lane. The currently documented OpenRouter Qwen3.8 Max route is paid, so silently selecting it would violate the project's zero-cost requirement.

A future paid-model lane can be added as an explicitly authorized, opt-in path, separate from the free route circuit.

## 4. Recovery and forensic debugging

There are two independent recovery budgets.

### Provider/agent attempt budget

One GitHub trigger allows up to three full OpenCode agent invocations.

Each retry begins from the next untried route. Before retrying, the workflow inspects:

- repository status;
- diff check;
- diff summary;
- the preceding attempt's sanitized log.

This is replay-aware: a provider failure is never treated as evidence that no repository or GitHub-side mutation occurred.

After three failed full-agent attempts, the workflow posts sanitized findings to the triggering Issue or Pull Request and terminates.

### Forensic debugging budget

The agent instructions allow up to five total evidence-based forensic recovery cycles inside a coding task.

Every cycle must:

1. read the actual failure evidence;
2. form a concrete fault hypothesis;
3. make the smallest relevant correction;
4. rerun the most informative validation.

Three consecutive failures of the same unresolved fault trigger the three-strike circuit breaker. The agent stops rather than burning resources on repeated identical hypotheses.

## 5. Evidence gate

The agent uses a practical 90%-evidence gate before a substantive mutation is treated as ready for commit/PR handoff.

This is a qualitative engineering threshold, not a measured probability.

Required convergence includes:

- the relevant static/runtime/test evidence that is actually available;
- changed-file scope matches the intended fix;
- the diff has been reviewed;
- no known correctness or security blocker remains.

The agent must report evidence gaps instead of converting incomplete verification into a success claim.

## 6. Public-repository secret controls

The repository is public.

The OpenCode configuration and workflow use environment-backed credentials only.

The agent is explicitly prohibited from:

- hard-coding API keys;
- hard-coding GitHub tokens;
- hard-coding WhatsApp session or API credentials;
- hard-coding database credentials;
- echoing the environment wholesale;
- putting secrets into caches, artifacts, issue comments, commits, test fixtures, or diagnostics.

The OpenCode permission model denies reads of:

- `.env`;
- `.env.*`;
- `*.env`;
- credential-bearing `.npmrc`.

The attempt wrapper redacts configured credentials and common credential formats before diagnostic output is emitted.

## 7. Git mutation boundaries

The agent is not allowed to use shell commands for:

- `git commit`;
- `git push`;
- `git reset`;
- `git clean`;
- local branch deletion.

The OpenCode GitHub integration is responsible for the GitHub-side branch/PR workflow.

`main` is treated as protected by policy even though the current repository settings do not enforce branch protection.

## 8. OpenCode security controls

The staged configuration includes:

- sharing disabled;
- external-directory access denied;
- doom-loop protection denied;
- destructive Git operations denied;
- immutable GitHub Action references;
- release-artifact SHA-256 verification;
- `persist-credentials: false` on checkout;
- no OIDC `id-token: write` permission;
- no interactive cache save.

OpenCode is invoked as the pinned/current CLI path rather than using a floating `@latest` GitHub Action reference.

The current source release reference audited during this work is OpenCode v1.18.31.

## 9. Composio integration audit

The verified Composio MCP endpoint for this repository is https://connect.composio.dev/mcp with the credential supplied through x-consumer-api-key: {env:COMPOSIO_API_KEY}.

Live connected-tool checks performed during this work:

- Tavily: a real current web search succeeded;
- E2B: sandbox creation and connection succeeded;
- E2B shell/code execution: the E2B integration advertises execution capabilities, but the repository-management connector did not expose a standalone E2B execute action in its own management tool surface.

The management connector and the OpenCode MCP tool surface are not identical. OpenCode should dynamically discover the E2B execution capability through the Composio MCP when it is exposed.

This audit does not falsely claim that the repository-management connector executed a command inside the E2B sandbox. GitHub Actions remains the authoritative repository execution environment whenever the E2B execution action is not actually visible to the running agent.

## 10. Reactive routing hardening

The provider selector never calls OpenRouter `chat/completions` or Gemini `generateContent` as a health probe. It only chooses the next configured route.

After a real OpenCode failure, the workflow classifies the sanitized failure evidence. 401/403/429/5xx, quota exhaustion, rate limiting, and provider saturation exclude the affected provider from later attempts in the same task. Model-specific or request-shape failures remain eligible for a different model route instead of incorrectly excluding the whole provider.

This prevents the recovery mechanism from creating additional inference traffic merely to discover that a provider is unavailable.

## 11. Validation evidence

The final enterprise validation workflow on the isolated audit branch passed all implemented checks.

Latest validation run:

- run ID: `35477793625`
- head SHA: `b3c5b1acfcb1b2b5f5562c8b2da58aaca5e3cffe`
- workflow: `enterprise-agent-validation`
- result: success

Validated categories included:

- required-file presence;
- JSON/YAML syntax;
- shell/application syntax;
- model/key routing invariants;
- bounded recovery invariants;
- security invariants;
- secret-disclosure guard;
- cache architecture references;
- application packaging/reproducibility audit;
- main governance visibility audit.

## 12. Existing application findings

These are pre-existing project findings surfaced by validation and deliberately not hidden by the agent-infrastructure work:

### Start entrypoint

`package.json` references `server.js` from the start command, while `server.js` is absent from the repository tree examined by the validator.

### Reproducibility

No `package-lock.json` or `npm-shrinkwrap.json` is present.

### Automated tests

`package.json` does not currently define an npm `test` script.

These remain warnings until the application itself is intentionally repaired.

## 13. Manual enterprise governance gate

Repository governance is separate from OpenCode configuration.

Current live GitHub inspection reports:

- `main` is not protected;
- required status checks are not configured at the repository branch-protection level.

The staged branch does include:

- `.github/CODEOWNERS` with `* @Jackie-SDX`;
- Dependabot configuration for GitHub Actions and npm updates.

Before integrating this branch, repository settings should deliberately enforce:

- pull-request review before `main`;
- required validation status checks;
- no force-push;
- no direct branch deletion;
- restricted merge authority;
- appropriate secret/environment protection for privileged deployment jobs;
- organization/repository Actions allowlists where appropriate.

Those settings were intentionally not changed by this audit.

## 14. Current acceptance gate

The isolated implementation is ready for human review when all of the following are satisfied:

1. enterprise validation remains green;
2. the human supplies whichever of `GEMINI_API_KEY_4` and `GEMINI_API_KEY_5` they actually want to use;
3. additional Gemini credentials are independently quota-isolated and authorized;
4. `OPENROUTER_API_KEY` is present when OpenRouter fallback is desired;
5. a real `/oc` run is executed after the workflow reaches the default branch or an otherwise supported test entrypoint;
6. when Composio is requested during the run, the logs show an actual tool invocation and result;
7. the final diff and branch state are reviewed;
8. the human decides whether the branch should be merged into `main`.

No claim of full end-to-end `/oc` execution is made for the current audit branch because GitHub's `issue_comment` workflow resolves from the default branch, and this audit deliberately did not modify `main`.

## Final staged state

Audit branch:
`audit/enterprise-opencode`

Current audit head: see the tip of audit/enterprise-opencode.
`b3c5b1acfcb1b2b5f5562c8b2da58aaca5e3cffe`

Main baseline:
`93780b5201d613da04072524d8aa84710dbafdf5`

Main was not modified by this audit.
