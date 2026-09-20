# Enterprise OpenCode Agent Audit

Repository: `Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot`

Main baseline at audit start:
`93780b5201d613da04072524d8aa84710dbafdf5`

This work is staged on the isolated branch `audit/enterprise-opencode`. No implementation commit from this audit has been written to `main`.

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

The previous Gemini model identifiers were retired. The hardened configuration uses the currently configured Gemini generation ladder and does not depend on the retired 2.5 identifiers.

The interactive route selector supports five Gemini credential slots:

1. `GEMINI_API_KEY`
2. `GEMINI_API_KEY_2`
3. `GEMINI_API_KEY_3`
4. `GEMINI_API_KEY_4`
5. `GEMINI_API_KEY_5`

The current route order is model-major, then credential-major:

- Gemini 3.8 Flash + key slots 1→5
- Gemini 3.7 Flash + key slots 1→5
- Gemini 3.6 Flash + key slots 1→5
- Gemini 3.5 Flash + key slots 1→5
- Gemini 3.5 Flash-Lite + key slots 1→5
- OpenRouter `openrouter/free`

With all five Gemini slots configured, this produces 26 theoretical route candidates: 25 Gemini model/key combinations plus the OpenRouter free router.

With three Gemini keys configured today, it produces 16 theoretical candidates: 15 Gemini combinations plus OpenRouter.

The selector performs a small live provider probe before a full OpenCode invocation. HTTP 401/403, 429, and common 5xx provider failures cause the selector to advance without retrying the failed route repeatedly.

Important quota constraint: multiple keys are not unlimited quota. They are useful only when they represent credentials/projects/accounts that the human is authorized to use and whose provider quota accounting is actually isolated. A provider-level restriction, suspension, or organization-wide limit must not be bypassed with key rotation.

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

The verified Composio MCP endpoint for this repository is:

`https://connect.composio.dev/mcp`

with the credential supplied through:

`x-consumer-api-key: {env:COMPOSIO_API_KEY}`

Live connected-tool checks performed during this audit:

- Tavily: a real current web search succeeded;
- E2B: API health check succeeded.

The available E2B Composio surface in this environment did not expose a direct arbitrary command/code-execution operation. Therefore this audit does not claim an E2B runtime build/test. GitHub Actions remains the verifiable project execution environment for repository changes.

A configured connector or successful health check is not treated as proof that every higher-level tool operation works.

## 10. Validation evidence

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

## 11. Existing application findings

These are pre-existing project findings surfaced by validation and deliberately not hidden by the agent-infrastructure work:

### Start entrypoint

`package.json` references `server.js` from the start command, while `server.js` is absent from the repository tree examined by the validator.

### Reproducibility

No `package-lock.json` or `npm-shrinkwrap.json` is present.

### Automated tests

`package.json` does not currently define an npm `test` script.

These remain warnings until the application itself is intentionally repaired.

## 12. Manual enterprise governance gate

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

## 13. Current acceptance gate

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

Current audit head:
`b3c5b1acfcb1b2b5f5562c8b2da58aaca5e3cffe`

Main baseline:
`93780b5201d613da04072524d8aa84710dbafdf5`

Main was not modified by this audit.
