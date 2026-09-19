# Enterprise OpenCode Agent Audit

Repository: Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot

Main baseline at audit start:
93780b5201d613da04072524d8aa84710dbafdf5

This work is staged on an isolated audit branch. Main is not part of the implementation.

## Confirmed findings

1. Interactive cache writes were denied.

The completed OpenCode run reported "Cache mode: read".

The OpenCode cache key was opencode-Linux-X64-v1.18.31.

The primary and fallback restore operations both reported a cache miss.

Post-job saves were rejected with "cache write denied: token has no writable scopes".

Conclusion: the interactive path cannot be the cache writer. The enterprise design therefore separates cache restore from cache population.

2. Gemini 3.8 retry behavior consumed excessive time.

The observed run returned repeated HTTP 503 responses and repeated HTTP 429 quota failures.

The final quota response identified the free-tier generate-content request limit for gemini-3.8-flash.

The primary OpenCode invocation ran for approximately 194 seconds before failure, after which the Gemini 3.6 fallback ran for approximately 134 seconds and succeeded.

Conclusion: provider selection must happen before a full agent run whenever possible, and a failed route must rotate rather than repeatedly hammer the same provider.

3. The previous workflow wired only one Gemini key.

The hardened workflow supports:

GEMINI_API_KEY
GEMINI_API_KEY_2
GEMINI_API_KEY_3

Secondary and tertiary aliases are also exposed for compatibility with the supplied blueprint.

Multiple keys are not treated as unlimited capacity; quota isolation depends on provider project/account arrangements.

4. The previous OpenRouter fallback hard-coded a transient model.

The hardened path uses openrouter/free instead.

OpenRouter documents openrouter/free as a free router that filters for request capabilities such as tool calling and structured output.

5. Composio credential propagation was proven, but actual tool execution was not.

The previous GitHub run showed COMPOSIO_API_KEY reaching OpenCode and fetched Composio documentation.

It did not demonstrate a successful Tavily or E2B tool invocation.

Therefore the previous run proves credential delivery, not end-to-end Composio tool integration.

6. The supplied MCP URL was wrong.

The supplied blueprint used https://composio.dev.

The verified Connect MCP endpoint is https://connect.composio.dev/mcp.

7. Main has no visible branch protection/rules.

The audit connection reports main as unprotected and no rules are visible.

This is repository governance, not an OpenCode config problem. Governance settings are intentionally not modified by this audit.

8. package.json has an application packaging inconsistency.

The current package start script contains node server.js, but server.js is absent from the repository tree.

This is recorded and surfaced by validation; it is not silently changed by the agent-infrastructure work.

9. The project has no npm lockfile and no automated test script.

The repository tree contains no package-lock.json or npm-shrinkwrap.json, and package.json has no test script.

The validation workflow therefore performs deterministic syntax/configuration checks and reports the reproducibility/test-suite gap instead of pretending a test suite exists.

10. Third-party Action version drift was present.

The previous workflow used anomalyco/opencode/github@latest.

The enterprise branch removes the floating Action and runs the pinned OpenCode v1.18.31 CLI directly.

Checkout/cache Actions are pinned to immutable commit SHAs.

## Enterprise architecture

Interactive agent:

owner-only /oc or /opencode comment
→ per-issue/PR concurrency
→ checkout
→ versioned verified OpenCode cache restore
→ verified release install on cache miss
→ credential/config preflight
→ lightweight model/key probe
→ OpenCode CLI execution
→ bounded route re-selection on failure
→ routing summary
→ explicit final status

Trusted cache:

push to main or manual/scheduled cache workflow
→ official OpenCode release metadata
→ official Linux x64 artifact
→ published SHA-256 verification
→ executable verification
→ versioned cache save

This deliberately avoids making the low-trust interactive workflow a cache writer.

## Current connected integrations audited

GitHub: active through the Jackie-SDX connection.

Tavily MCP: active; live search succeeded during this audit.

E2B: active; health check, sandbox creation, connection, and state inspection succeeded.

OpenRouter connector: active; model catalog endpoint and credit endpoint responded. The user-facing GitHub workflow still requires OPENROUTER_API_KEY if that route is to be used.

The currently discovered E2B connector surface did not expose a direct sandbox command-execution action in this environment. Therefore no E2B runtime test is claimed.

## Manual governance required

To actually enforce enterprise branch governance, repository and organization settings still need deliberate configuration:

- require pull requests before main;
- require relevant status checks;
- prohibit force-push/delete;
- require appropriate CODEOWNERS review;
- restrict who can approve/merge;
- least-privilege Actions policy;
- protected environments for privileged deployment secrets;
- secret scanning/push protection;
- organization Actions allowlists;
- signed-commit policy when required.

Those settings are intentionally outside this branch implementation because changing them is repository governance, not a safe side effect of an agent config patch.

## Acceptance gate

Before merging this branch:

1. enterprise-agent-validation workflow must pass;
2. owner supplies the additional Gemini/OpenRouter secrets they choose to use;
3. a real /oc run demonstrates route selection;
4. when Composio use is requested, the run must show an actual tool invocation and successful result;
5. diff and branch state are reviewed;
6. only then should a human choose whether to merge into main.
