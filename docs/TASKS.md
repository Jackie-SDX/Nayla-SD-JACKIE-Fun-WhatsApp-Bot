# CPP Project Template — Distribution Hardening Task Plan

> **Scope:** implementation backlog for `Jackie-SDX/cpp-project-template` release engineering and software distribution. The task document itself is maintained in the audit/project documentation repository; the CPP repository remains the system under remediation and is not modified by this document.
>
> **Baseline audited:** `main` at `11d1726324f02f53988e9047ed3018a9545ff631`; latest release inspected: `v0.0.9` / workflow run `35877971162`.
>
> **Status rule:** every checkbox is a real implementation/verification task. A task is not complete because a build succeeds; it requires recorded evidence and the acceptance condition stated below.

## Definition of done

A release is releasable only when the complete release manifest, source commit, version, package metadata, artifact filenames, signatures, attestations, checksums, runtime dependencies, and tested installation state agree. Required platform artifacts must be buildable, inspectable, verifiably trusted, installable on clean machines, upgradeable/removable without unacceptable side effects, and accompanied by reproducibility/provenance evidence.

The supported release formats remain:

- **Windows:** ZIP + NSIS EXE + WiX MSI
- **Linux:** tar.gz + DEB + RPM
- **macOS:** ZIP + DMG

Do **not** add `.7z`, MSIX, AppImage, Flatpak, Snap, Arch packages, or other formats merely to increase artifact count. Add a new format only when a documented distribution requirement justifies its engineering and support cost.

---

# P0 — Release blockers

## 1. Single release identity and version contract

- [ ] Establish one canonical release version source of truth.
- [ ] Resolve the release/tag version **before** CMake configure and build.
- [ ] Pass the resolved version into CMake (`CPP_PROJECT_TEMPLATE_VERSION`) before package generation.
- [ ] Ensure `project(... VERSION ...)`, CPack metadata, DEB metadata, RPM metadata, Windows installer metadata, macOS bundle metadata, package filenames, and release notes all derive from that single version.
- [ ] Normalize the version model so semantic versioning and platform-specific version rules are explicit.
- [ ] Handle Windows MSI's three-field version comparison rules deliberately; document how fourth-field/internal build numbers are represented.
- [ ] Add a CI assertion that tag version == CMake version == CPack version == every package version == installer version == bundle version == release manifest version.
- [ ] Fail the release before artifact upload if any version mismatch exists.
- [ ] Prohibit a post-build filename-only version rewrite as a substitute for actually building with the release version.

## 2. Correct product/repository identity

- [ ] Replace every stale `NaylaCruz`/old-repository identity in product metadata with the canonical current project identity.
- [ ] Correct `HOMEPAGE_URL`, author, organization/vendor, package maintainer, bundle identifiers, installer publisher metadata, and documentation links.
- [ ] Scan source, packaging templates, CI, generated metadata, and release assets for stale identity strings.
- [ ] Add an automated identity scan that fails release packaging on forbidden/stale repository/product identities.
- [ ] Ensure DEB/RPM/installer metadata and application About/version surfaces agree on product name, vendor, homepage, and license.

## 3. One release manifest for GitHub and GitLab

- [ ] Create a machine-readable release manifest describing every supported OS, architecture, compiler/toolchain, product profile, artifact generator, file format, canonical filename, signing requirement, attestation requirement, test requirement, and support baseline.
- [ ] Generate the GitHub matrix from the manifest rather than duplicating a handwritten matrix.
- [ ] Generate the GitLab matrix/contract from the same manifest.
- [ ] Generate expected artifact inventory/counts from the manifest; eliminate stale hardcoded inventory comments and counts.
- [ ] Make GitHub and GitLab resolve the same version and identity inputs before configure/build.
- [ ] Make both CI systems enforce the same required release gates.
- [ ] Record deliberate CI-platform differences explicitly instead of silently allowing drift.

## 4. Release cache correctness

- [ ] Remove the stale GitHub repository-name condition that currently bypasses cache-miss enforcement for the canonical repository.
- [ ] Define cache keys over OS, architecture, compiler, compiler version, vcpkg triplet, dependency manifest, toolchain revision, build profile, CMake/tool version, and relevant build scripts.
- [ ] Ensure a cache hit cannot satisfy a different ABI/toolchain/profile.
- [ ] Add cache-miss diagnostics explaining why a cache was invalidated.
- [ ] Require the release path to seed or restore every required cache deterministically.
- [ ] Exercise cold-cache and warm-cache releases as separate acceptance tests.

## 5. Immutable release publication

- [ ] Remove publication behavior that overwrites same-named release assets.
- [ ] Freeze the final artifact candidate set before publication.
- [ ] Verify all artifacts locally in CI before making them public.
- [ ] Publish each canonical asset exactly once.
- [ ] Reject duplicate filenames, duplicate semantic identities, and stale artifacts.
- [ ] Verify downloaded release assets after publication against pre-publication SHA-256 and size.
- [ ] Record the exact release tag, source commit, workflow run/attempt, manifest digest, artifact digests, and publication timestamp.
- [ ] Treat a failed publication as a failed release unless the entire publication transaction is proven complete and consistent.

## 6. Release inventory gate

- [ ] Require every manifest-declared artifact to exist.
- [ ] Require every artifact to have exactly the expected filename, format, architecture, product profile, and version.
- [ ] Reject unexpected release assets unless explicitly marked as release metadata/source archives.
- [ ] Validate source archives separately from binary artifacts.
- [ ] Require canonical `SHA256SUMS` coverage for all distributable binaries/installers/archives.
- [ ] Verify the published `SHA256SUMS` file against the final downloaded assets.
- [ ] Sign the checksum manifest or otherwise bind it to the release provenance.

## 7. Release-critical CI failure semantics

- [ ] Remove `allow_failure` from production release-critical package/test/signing jobs.
- [ ] Separate experimental/nightly jobs from production release jobs.
- [ ] Prevent a release from succeeding when any required package, signature, attestation, validation, or lifecycle test fails.
- [ ] Prevent stale artifacts from a prior matrix entry from being accidentally reused as successful output.
- [ ] Make retries preserve the original release candidate identity and never mix outputs from different commits.

---

# P0 — Windows distribution

## 8. Authenticode and trust chain

- [ ] Sign all distributed Windows PE executables and DLLs that require publisher trust.
- [ ] Sign the NSIS installer itself.
- [ ] Sign the WiX MSI itself.
- [ ] Sign any externally generated cabinet/package components when required by the packaging design.
- [ ] Sign generated uninstall/launcher executables where they are distributed separately or exposed independently.
- [ ] Use SHA-256 or stronger digest/signature algorithms.
- [ ] Use RFC 3161 timestamping with a SHA-256 timestamp digest.
- [ ] Prefer HSM/cloud-backed signing rather than long-lived raw PFX material on runners.
- [ ] Keep signing credentials unavailable to untrusted pull-request workflows.
- [ ] Use least-privilege release permissions and isolated signing jobs.
- [ ] Verify signer identity, certificate chain, EKU, timestamp, signature validity, and artifact digest in CI after signing.
- [ ] Fail release publication if any required Windows artifact is unsigned or cryptographically unverifiable.
- [ ] Document certificate renewal, revocation, rotation, emergency replacement, and SmartScreen reputation handling.

## 9. Windows runtime and binary policy

- [ ] Define the supported Windows versions for every architecture/toolchain variant.
- [ ] Define the MSVC/UCRT runtime baseline for each variant.
- [ ] Verify the final installed tree rather than the build tree for runtime dependencies.
- [ ] Detect missing runtime DLLs and accidental dependence on runner-installed software.
- [ ] Verify PE machine type, PE32/PE32+, subsystem, and architecture against the release manifest.
- [ ] Inspect security-relevant PE characteristics (ASLR/DEP and other applicable mitigations) and document any intentional exceptions.
- [ ] Verify no debug/developer artifacts, symbols, test binaries, temporary files, credentials, or build paths leak into release packages.

## 10. NSIS lifecycle

- [ ] Validate fresh install on a clean supported Windows machine.
- [ ] Validate silent/unattended installation.
- [ ] Validate install with and without administrator rights according to the chosen install model.
- [ ] Validate PATH modification behavior and complete removal on uninstall.
- [ ] Validate Start Menu/Desktop shortcuts and their removal.
- [ ] Validate repair/reinstall behavior.
- [ ] Validate upgrade from the immediately previous release.
- [ ] Validate upgrade from a representative older supported release.
- [ ] Validate downgrade protection or explicitly documented downgrade behavior.
- [ ] Validate uninstall leaves only documented user data/configuration.
- [ ] Validate installer exit codes and logs for success, cancellation, privilege failure, and failure rollback.

## 11. WiX MSI lifecycle

- [ ] Establish a stable `UpgradeCode` strategy.
- [ ] Generate a new `ProductCode` for MSI major releases according to Windows Installer rules.
- [ ] Implement explicit `MajorUpgrade` behavior.
- [ ] Block unsafe downgrades.
- [ ] Test upgrade from N-1 to N.
- [ ] Test upgrade from an older supported N-x version to N.
- [ ] Test rollback after a deliberately induced mid-upgrade failure.
- [ ] Test repair/maintenance mode.
- [ ] Test uninstall and ARP/Add-or-Remove-Programs state.
- [ ] Validate MSI internal consistency/ICE rules where available.
- [ ] Validate silent enterprise installation and standard `msiexec` exit-code semantics.
- [ ] Verify signed MSI/cabinet state after every finalization step.

---

# P0 — macOS distribution

## 12. Real application bundle

- [ ] Make the GUI target an actual `MACOSX_BUNDLE` target rather than relying only on CPack bundle variables.
- [ ] Validate the final `.app` structure (`Contents`, `MacOS`, `Resources`, `Info.plist`, etc.).
- [ ] Set a stable bundle identifier owned by the product.
- [ ] Set bundle short version, bundle version/build number, display name, executable name, and minimum OS explicitly.
- [ ] Ship application icons and other required resources in the correct bundle locations.
- [ ] Validate that command-line and GUI product profiles are intentional and not accidentally mixed.

## 13. macOS architecture and runtime closure

- [ ] Define supported macOS versions per architecture in the release manifest.
- [ ] Build and validate every declared architecture independently.
- [ ] Validate Mach-O architecture slices and headers.
- [ ] Audit every dylib/framework dependency from the final installed app.
- [ ] Validate `@rpath`, `@loader_path`, `@executable_path`, and install-name behavior.
- [ ] Prevent accidental dependency on developer machine paths or CI-only locations.
- [ ] Verify the app launches on a clean supported macOS host without development toolchains installed.
- [ ] Decide explicitly whether architecture-specific packages or a universal binary are the supported distribution model.

## 14. Developer ID, Hardened Runtime, notarization

- [ ] Sign all distributed executables and nested code with Developer ID certificates.
- [ ] Enable Hardened Runtime for GUI and command-line targets that are distributed as signed code.
- [ ] Use only the minimum required entitlements.
- [ ] Securely timestamp macOS signatures.
- [ ] Verify nested-code signatures recursively after final packaging.
- [ ] Notarize the exact deliverables intended for users.
- [ ] Use `notarytool` rather than obsolete notarization mechanisms.
- [ ] Staple notarization tickets to the deliverables where applicable.
- [ ] Verify notarization status and stapled tickets in CI.
- [ ] Run `spctl`/Gatekeeper verification against the final app/DMG/package as applicable.
- [ ] Perform first-launch tests with quarantine/Gatekeeper conditions representative of an actual downloaded release.
- [ ] Verify signing/notarization after DMG creation, not only on the inner `.app`.

## 15. macOS distribution lifecycle

- [ ] Validate ZIP extraction on a clean host.
- [ ] Validate DMG mounting and application installation.
- [ ] Validate that the DMG contains exactly the intended product and presentation metadata.
- [ ] Validate upgrade/replacement from the previous release.
- [ ] Validate removal/cleanup behavior and document what user data intentionally remains.
- [ ] Validate offline installation/launch where the product is intended to work offline.

---

# P0 — Linux DEB/RPM/tar.gz distribution

## 16. Debian package correctness

- [ ] Fix the concrete v0.0.9 filename vs DEB internal Version 0.0.1 mismatch at the source of packaging, not by renaming the file afterward.
- [ ] Correct maintainer, homepage, vendor, and package identity metadata.
- [ ] Define a supported Debian/Ubuntu baseline and CPU architecture policy.
- [ ] Use runtime dependencies only; never use a development package fallback merely to make the package install.
- [ ] Define minimum glibc/wxWidgets/runtime versions deliberately.
- [ ] Inspect `control`, file lists, architecture, installed size, dependencies, conffiles, triggers, and maintainer scripts.
- [ ] Validate packages with `lintian` or an equivalent package-quality gate.
- [ ] Test fresh install on a clean host/container representing each supported baseline.
- [ ] Test N-1 to N package upgrade.
- [ ] Test downgrade behavior or explicitly reject unsafe downgrades.
- [ ] Test removal/erase and file ownership cleanup.
- [ ] Test application launch from installed paths.
- [ ] Validate desktop entry, icons, MIME/file associations, and desktop database behavior where applicable.
- [ ] Sign repository metadata if/when the project provides an APT repository; do not confuse standalone `.deb` integrity with repository trust.

## 17. RPM package correctness

- [ ] Define supported RPM-based distributions and architectures.
- [ ] Validate name, epoch/version/release, architecture, summary, description, license, URL, packager, dependencies, and file list.
- [ ] Validate scriptlets/triggers and their failure behavior.
- [ ] Run `rpmlint` or an equivalent package-quality gate.
- [ ] Test fresh install on clean supported hosts.
- [ ] Test N-1 to N upgrade.
- [ ] Test downgrade behavior or explicit rejection.
- [ ] Test erase/uninstall and file ownership cleanup.
- [ ] Test installed application launch and desktop integration where applicable.
- [ ] Sign the final RPM with the project release key.
- [ ] Verify RPM signature cryptographically in CI and in consumer documentation.
- [ ] Define key rotation/revocation and consumer key-distribution procedures.

## 18. Linux tarball correctness

- [ ] Ensure archives unpack into a single predictable top-level directory.
- [ ] Validate file permissions, executable bits, symlinks, ownership semantics, and archive ordering.
- [ ] Validate that no development files, CI secrets, test fixtures, caches, or absolute build paths are included.
- [ ] Validate runtime dependencies from the extracted installation tree.
- [ ] Validate CLI and GUI startup from a clean supported environment.
- [ ] Document manual installation, launch, uninstall/removal, and runtime requirements.

---

# P0 — Runtime compatibility and platform baselines

## 19. Runtime dependency closure

- [ ] Generate a machine-readable runtime dependency inventory for Windows PE, Linux ELF, and macOS Mach-O artifacts.
- [ ] Run dependency inspection against the **final packaged/installed tree**, not the CI build tree.
- [ ] Detect host-satisfied dependencies that are absent from the package.
- [ ] Define which system libraries are intentionally external and which are bundled.
- [ ] Define minimum glibc and libstdc++ symbol/version baselines.
- [ ] Define wxWidgets runtime baselines separately from build-time development dependencies.
- [ ] Define Windows runtime baseline and redistribution policy.
- [ ] Define macOS deployment target and system framework baseline.
- [ ] Define supported CPU instruction sets and prohibit accidental AVX/CPU-feature requirements outside the manifest.
- [ ] Execute the release matrix on clean machines/containers representing each declared baseline.

## 20. Binary-hardening checks

- [ ] Inspect Linux ELF hardening properties such as PIE, RELRO, NX, stack protection, and applicable symbol/loader properties.
- [ ] Inspect Windows mitigation-relevant properties and document intentional exceptions.
- [ ] Inspect macOS hardened runtime and signing properties.
- [ ] Make security-property regressions release blockers where the chosen baseline requires them.

---

# P1 — Artifact validation and QA

## 21. Artifact structural validation

- [ ] Validate PE/ELF/Mach-O machine architecture for every artifact.
- [ ] Validate package metadata against the release manifest.
- [ ] Validate archive membership and reject unexpected files.
- [ ] Validate executable permissions and symlink correctness.
- [ ] Reject secrets, private keys, CI credentials, tokens, debug files, and unintended source/build trees in artifacts.
- [ ] Validate installer package contents, not just installer headers.
- [ ] Validate all release artifacts with format-native inspection tools.
- [ ] Keep machine-readable validation reports as release evidence.

## 22. Product-profile parity

- [ ] Document every intentional difference between GUI/CLI profiles.
- [ ] Document build-test differences such as disabled GUI/tests for special toolchain variants.
- [ ] Ensure profile differences are reflected in the manifest and not inferred from filenames.
- [ ] Add tests for files/resources expected only in each profile.
- [ ] Prevent accidental release of an incomplete profile as if it were a full product.

## 23. Full release-matrix QA

- [ ] Maintain a matrix covering every declared OS × architecture × compiler/toolchain × profile × artifact format.
- [ ] Require at least one clean-machine runtime smoke test per matrix row.
- [ ] Require package metadata/signature verification per matrix row.
- [ ] Require install/upgrade/remove tests per installer/package family.
- [ ] Maintain an exception mechanism only for documented, intentional platform limitations.
- [ ] Prohibit silent matrix exclusions.

---

# P1 — Reproducible builds

## 24. Deterministic build inputs

- [ ] Define `SOURCE_DATE_EPOCH` policy for release builds.
- [ ] Normalize timezone, locale, hostname-dependent inputs, user-dependent paths, and build directory paths.
- [ ] Normalize archive file ordering, timestamps, ownership, permissions, and compression metadata.
- [ ] Remove current-time metadata from ZIP/tar/DEB/RPM/DMG generation wherever the format permits.
- [ ] Pin build tool versions and package-generator versions.
- [ ] Pin external binaries downloaded during the build and verify their checksums/signatures.

## 25. Rebuild verification

- [ ] Perform independent rebuilds of representative artifacts on a separate runner/environment.
- [ ] Compare artifacts byte-for-byte where the format/build permits.
- [ ] Use `diffoscope` or an equivalent deterministic comparison tool for divergent outputs.
- [ ] Record and classify every expected non-deterministic field.
- [ ] Drive remaining reproducibility failures to zero or explicitly document an unavoidable, bounded exception.
- [ ] Publish build/rebuild evidence for audited releases.

---

# P1 — SBOM, provenance, attestations, and supply-chain controls

## 26. Dependency and toolchain integrity

- [ ] Pin the vcpkg baseline/registry state and make dependency resolution reproducible.
- [ ] Pin CMake, Ninja, compiler/toolchain versions, NSIS, WiX, RPM/DEB tooling, and macOS packaging/signing tooling.
- [ ] Verify checksums/signatures for third-party tools downloaded by CI.
- [ ] Add dependency-diff review between releases.
- [ ] Add automated vulnerability scanning for direct and transitive dependencies.
- [ ] Define a process for triaging, patching, accepting, or documenting dependency vulnerabilities.
- [ ] Add license-policy scanning for source and binary dependencies.

## 27. SBOM

- [ ] Generate an SPDX and/or CycloneDX SBOM for each releasable product profile.
- [ ] Include transitive dependencies.
- [ ] Distinguish build-time dependencies from runtime/distributed dependencies.
- [ ] Include exact versions/identifiers and package-manager provenance where available.
- [ ] Bind each SBOM to the exact release artifact digest.
- [ ] Publish SBOMs with the release and/or as verified attestations.
- [ ] Verify that the SBOM describes the shipped product rather than only the source manifest.

## 28. Provenance and attestations

- [ ] Generate cryptographically verifiable build provenance for every releasable artifact.
- [ ] Prefer GitHub Artifact Attestations / Sigstore-compatible attestations for GitHub release artifacts.
- [ ] Target a documented SLSA Build Level 3-equivalent build/provenance model for the production release pipeline.
- [ ] Include source repository, exact commit, workflow, run/attempt, build inputs, toolchain identity, and artifact digest in provenance.
- [ ] Generate attestations only after final artifact bytes exist.
- [ ] Verify provenance before publication, not only after publication.
- [ ] Publish verification instructions for consumers.
- [ ] Maintain an offline verification path for organizations that need air-gapped validation.
- [ ] Define attestation retention and cleanup rules so attestations remain aligned with retained artifacts.

## 29. Signing-key management

- [ ] Separate signing credentials from ordinary build secrets.
- [ ] Prefer hardware-backed/HSM/cloud signing for long-lived release identities.
- [ ] Prevent developer/PR jobs from accessing production signing identities.
- [ ] Define key/certificate rotation schedules.
- [ ] Define revocation and emergency-response procedures.
- [ ] Record signer identity and certificate/key version in release evidence.
- [ ] Test recovery after signing-credential rotation.

---

# P1 — CI/CD security and governance

## 30. GitHub Actions hardening

- [ ] Pin third-party GitHub Actions to immutable commit SHAs.
- [ ] Maintain an automated process for updating those pinned SHAs and reviewing changes.
- [ ] Apply least-privilege workflow/job permissions.
- [ ] Use OIDC instead of long-lived cloud credentials where supported.
- [ ] Restrict release/signing workflows to trusted events, branches, tags, and environments.
- [ ] Prevent untrusted pull-request code from reaching signing credentials.
- [ ] Harden artifact download/upload boundaries against path traversal and artifact confusion.
- [ ] Enable secret scanning and push protection.
- [ ] Add dependency review/security scanning on changes to build/release definitions.
- [ ] Review release workflows for command injection and untrusted input interpolation.

## 31. GitLab parity and security

- [ ] Apply equivalent pinning/version controls to GitLab images, includes, and reusable components.
- [ ] Remove release-critical `allow_failure` paths.
- [ ] Ensure GitLab and GitHub produce equivalent release evidence.
- [ ] Prevent a weaker CI platform from publishing artifacts that would fail the stronger platform's gates.
- [ ] Define a single authority for final publication or a formally synchronized dual-publish process.

## 32. Repository governance

- [ ] Protect `main` with required CI checks.
- [ ] Protect release tags and prevent silent tag movement.
- [ ] Require verified/signed commits where compatible with the project's contribution model.
- [ ] Protect release environments and signing identities without introducing unnecessary manual approval gates for ordinary development work.
- [ ] Define CODEOWNERS/review ownership for release-critical workflow, packaging, signing, and dependency files.
- [ ] Retain release evidence long enough to support incident investigation and audits.

---

# P1 — Installer/package lifecycle and user experience

## 33. Cross-platform lifecycle matrix

- [ ] Test fresh install.
- [ ] Test upgrade from N-1.
- [ ] Test upgrade from an older supported version.
- [ ] Test downgrade behavior.
- [ ] Test repair/reinstall where applicable.
- [ ] Test uninstall/removal.
- [ ] Test rollback after induced failure.
- [ ] Test silent/unattended installation for enterprise deployment targets.
- [ ] Test idempotent repeated installation where applicable.
- [ ] Test interrupted/cancelled installation and recovery.
- [ ] Verify exit codes are documented and machine-consumable.
- [ ] Verify installer/package logs are available and useful for support.

## 34. Offline and restricted-network behavior

- [ ] Define whether each artifact is expected to install completely offline.
- [ ] Ensure installers do not download undeclared payloads during installation.
- [ ] Document any unavoidable network requirements.
- [ ] Test behind a proxy/restricted network where enterprise users commonly operate.
- [ ] Ensure update/check-for-update features, if present, are separable from base installation.

## 35. Installation hygiene

- [ ] Validate install paths and permissions on each platform.
- [ ] Validate PATH/environment changes and reversibility.
- [ ] Validate file ownership and permissions on Linux/macOS.
- [ ] Validate registry/ARP state for Windows installers.
- [ ] Validate desktop/menu integration and icon caches where applicable.
- [ ] Validate user configuration and data are not accidentally deleted by uninstall.
- [ ] Validate temporary files and installer caches do not accumulate unnecessarily.

---

# P1 — Documentation, legal, and support readiness

## 36. Distribution documentation

- [ ] Publish a supported-platform/architecture/toolchain matrix.
- [ ] Document minimum runtime requirements.
- [ ] Document each artifact's purpose and expected installation method.
- [ ] Document checksum verification.
- [ ] Document Windows signature verification.
- [ ] Document macOS signature/notarization/Gatekeeper verification.
- [ ] Document DEB/RPM package signature verification where applicable.
- [ ] Document SBOM/provenance verification and exact consumer commands.
- [ ] Document offline/air-gapped verification for supported enterprise scenarios.
- [ ] Document upgrade, downgrade, uninstall, repair, and rollback semantics.

## 37. License and third-party compliance

- [ ] Verify the product's declared license is accurate.
- [ ] Audit all bundled third-party licenses and required notices.
- [ ] Ensure release artifacts contain required license/NOTICE information.
- [ ] Add machine-readable SPDX identifiers and/or REUSE compliance where practical.
- [ ] Run automated license-policy checks in CI.
- [ ] Verify third-party notices against the actual shipped dependency set.

## 38. Security/support policy

- [ ] Publish a security contact and vulnerability-reporting process.
- [ ] Define supported release/EOL windows.
- [ ] Define security update severity/response expectations.
- [ ] Document how users report installer/package failures.
- [ ] Define a release incident and rollback procedure.
- [ ] Define certificate/key compromise response procedures.

## 39. Release notes and migration

- [ ] Generate release notes from the exact release manifest and commit.
- [ ] Record breaking changes and migration requirements.
- [ ] Record minimum OS/runtime changes.
- [ ] Record installer/upgrade behavior changes.
- [ ] Record security/signing/provenance changes.
- [ ] Record dependency/runtime changes that can affect deployment.

---

# P2 — Operational maturity and long-term maintenance

## 40. Release evidence and audit trail

- [ ] Store machine-readable release manifests.
- [ ] Store validation reports.
- [ ] Store checksums and signature-verification results.
- [ ] Store SBOM and provenance evidence.
- [ ] Store reproducibility/rebuild evidence.
- [ ] Store install/upgrade lifecycle test evidence.
- [ ] Record exact CI runner/toolchain versions.
- [ ] Record release workflow run and attempt identifiers.
- [ ] Keep evidence linked to the immutable source commit and release tag.

## 41. Regression and release drills

- [ ] Perform periodic clean-machine release drills rather than relying only on ordinary CI.
- [ ] Perform signing-certificate renewal/rotation drills.
- [ ] Perform notarization credential/key rotation drills.
- [ ] Perform dependency compromise/failure tabletop exercises.
- [ ] Perform failed-publication recovery drills.
- [ ] Perform release rollback drills.
- [ ] Verify old release assets can still be validated after toolchain/key rotations.

## 42. Update and distribution strategy

- [ ] Decide whether an update mechanism is in scope; do not silently imply one exists merely because installers exist.
- [ ] If auto-update is added, define signed update metadata, rollback, anti-downgrade policy, and recovery behavior before implementation.
- [ ] Define how enterprise fleet-management tools can deploy and pin versions.
- [ ] Document stable artifact URLs/versioned URLs and retention policy.
- [ ] Define how yanked/compromised releases are marked and communicated.

## 43. Continuous verification

- [ ] Run periodic verification of released artifacts after publication.
- [ ] Detect and report release assets whose content no longer matches recorded digests.
- [ ] Monitor signing certificate expiry.
- [ ] Monitor notarization credential expiry.
- [ ] Monitor Linux signing-key expiry/rotation.
- [ ] Monitor dependency and toolchain end-of-life dates.
- [ ] Monitor action pins and release workflow drift.
- [ ] Re-run critical install smoke tests against representative current OS images on a scheduled basis.

# P1 — Additional cross-cutting controls from the final omission pass

## 44. Build isolation and trust boundaries

- [ ] Run production release builds on ephemeral, isolated runners with no persistent developer state.
- [ ] Minimize network access during the build; separate dependency acquisition from the reproducible build stage where practical.
- [ ] Verify every downloaded build dependency/tool by trusted checksum/signature before execution.
- [ ] Prevent build scripts from silently executing arbitrary unpinned remote content.
- [ ] Ensure release jobs cannot consume artifacts produced by unrelated workflows or untrusted branches.
- [ ] Record the build environment identity sufficiently to reconstruct the trust boundary used for the release.

## 45. Git/tag/reference integrity

- [ ] Verify that the release tag is immutable and points to the exact source commit used for every artifact.
- [ ] Prefer signed/verified release tags for production releases and document the trust policy.
- [ ] Reject release builds when the requested tag/ref resolves differently between jobs.
- [ ] Add a single-flight/concurrency lock so two publication jobs cannot race on the same release version.
- [ ] Prevent reruns from mixing artifacts produced by different workflow attempts or commits.

## 46. Consumer verification toolkit

- [ ] Provide a documented, scriptable release-verification procedure covering filenames, SHA-256, signatures, SBOM, and provenance.
- [ ] Provide one supported verification command/path per platform where practical.
- [ ] Verify that verification tooling works from a clean environment without repository checkout access.
- [ ] Document expected signer identities/fingerprints and provenance identity constraints.
- [ ] Document how consumers identify a revoked, yanked, or compromised release.
- [ ] Keep verification instructions versioned and tested against the current release assets.

## 47. Security testing of the release path

- [ ] Enable SAST/code scanning for security-sensitive build and packaging code.
- [ ] Scan release workflows for dangerous interpolation, command injection, unsafe artifact handling, and untrusted input use.
- [ ] Run dependency vulnerability scanning for direct and transitive dependencies.
- [ ] Run representative sanitizer builds (ASan/UBSan and other applicable sanitizers) before final production release where supported by the platform.
- [ ] Add malformed-package/archive tests for extraction safety, path traversal, symlink traversal, and unexpected executable content.
- [ ] Verify installers/packages do not execute undeclared network or privileged operations.

## 48. Conditional localization/accessibility readiness

- [ ] If localized installer/application UI is supported, test each shipped locale for truncated strings, encoding, resource completeness, and upgrade/uninstall consistency.
- [ ] If GUI distribution is supported for accessibility-sensitive environments, test keyboard navigation, high-contrast/display scaling, screen-reader-relevant metadata, and installer dialogs.
- [ ] Do not advertise locale/accessibility support that has not been tested in the shipped artifact.

## 49. Security advisory and VEX handling

- [ ] Define how a shipped dependency vulnerability is evaluated against the actual product.
- [ ] Where appropriate, produce VEX/security advisory data explaining whether a disclosed vulnerability is affected, not affected, or already remediated.
- [ ] Link security advisories to affected artifact versions and exact dependency/SBOM evidence.
- [ ] Test the process for yanking/revoking a compromised release and communicating the replacement release.


---

# Release gate — final acceptance checklist

A production release must not be declared complete until all applicable boxes below are true:

- [ ] Version is resolved before configure/build and is identical everywhere.
- [ ] Product/repository identity is correct and stale identities are absent.
- [ ] Release manifest is the source of truth and the final artifact inventory exactly matches it.
- [ ] Every required matrix row produced the correct artifact.
- [ ] Every Windows artifact is signed and timestamped; signatures are cryptographically verified.
- [ ] NSIS and WiX installers themselves are signed.
- [ ] Every macOS distributed executable is Developer ID signed with Hardened Runtime and minimal entitlements.
- [ ] macOS deliverables are notarized, stapled where applicable, and Gatekeeper-validated.
- [ ] DEB metadata is correct, dependencies are runtime-correct, and package lifecycle tests pass.
- [ ] RPM metadata/signature/lifecycle tests pass.
- [ ] Linux tarball runtime closure is proven on clean supported systems.
- [ ] Runtime dependency inventories are produced from final installed artifacts.
- [ ] No runner/dev-machine dependency is required accidentally.
- [ ] Reproducibility evidence exists for representative artifacts.
- [ ] SBOM is generated and bound to exact artifact digests.
- [ ] Provenance/attestation is generated and verified.
- [ ] Release artifacts have canonical SHA-256 digests and publication-time re-verification.
- [ ] Required CI security controls are active and release-critical jobs cannot silently fail.
- [ ] Installation/upgrade/rollback/uninstall tests pass across supported platform families.
- [ ] Documentation, licenses, notices, security contact, support matrix, and release notes match the actual release.
- [ ] Release evidence is retained and traceable to the immutable source commit and tag.

---

# Explicitly out of scope unless separately justified

- [ ] Do not add packaging formats only for artifact-count growth.
- [ ] Do not replace working NSIS/WiX/DEB/RPM/DMG/ZIP distribution formats merely because another format exists.
- [ ] Do not introduce a mandatory human approval council for normal engineering work just to claim stronger governance; protect only genuinely sensitive release/signing boundaries.
- [ ] Do not mark a release compliant because a single CI workflow is green while package contents, signatures, metadata, provenance, or clean-machine installation remain unverified.

---

# Research basis

The task plan was reconciled against the existing forensic audit, direct source inspection, recovered release artifacts, connected YouTube transcripts, connected Reddit searches, and current public guidance.

Authoritative/current references used for acceptance criteria:

- Microsoft Authenticode timestamping and SHA-256 guidance: https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures
- Apple notarization requirements: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Apple Hardened Runtime: https://developer.apple.com/documentation/security/hardened-runtime
- GitHub artifact attestations: https://docs.github.com/en/actions/concepts/security/artifact-attestations
- GitHub artifact-attestation verification: https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
- GitHub offline attestation verification: https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/verify-attestations-offline
- GitHub Actions security hardening/OIDC: https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments
- Sigstore Cosign signing/verification: https://docs.sigstore.dev/quickstart/quickstart-cosign/
- Sigstore in-toto attestations: https://docs.sigstore.dev/cosign/verifying/attestation/
- CMake/CPack: https://cmake.org/cmake/help/latest/manual/cpack.1.html
- CPack NSIS: https://cmake.org/cmake/help/latest/cpack_gen/nsis.html
- CPack macOS DMG: https://cmake.org/cmake/help/latest/cpack_gen/dmg.html
- WiX major upgrades: https://docs.firegiant.com/wix3/howtos/updates/major_upgrade/
- WiX signing: https://docs.firegiant.com/wix/tools/signing/
- Debian reproducible builds: https://wiki.debian.org/ReproducibleBuilds/Howto
- Debian package signing/apt trust model: https://www.debian.org/doc/manuals/securing-debian-manual/deb-pack-sign.en.html
- NIST SSDF SP 800-218: https://csrc.nist.gov/pubs/sp/800/218/final
- REUSE licensing compliance: https://reuse.software/spec-3.2/

Supplementary practitioner-source checks included YouTube material covering CMake/CPack/CTest/CDash deployment practices, software-packaging usability, Windows executable signing, and macOS client security. These sources are treated as supplementary engineering signals rather than authoritative compliance standards.

## Research limitations

- The Notion MCP toolkit reported **no active connection** during this research run, so no Notion-derived claims were used.
- The social-account sweep found active YouTube and Reddit connections; the other social-management toolkits queried did not report active accounts, so no unsupported social findings were invented.
- DeepWiki did not have an indexed page for this private repository, so repository conclusions continued to rely on the direct GitHub snapshot and artifact evidence already established by the forensic audit.
