
# Packaging / Installation / Release Architecture Forensic Audit

**Audit date:** 2026-09-23  
**Audited project:** Jackie-SDX/cpp-project-template  
**Repository audited:** https://github.com/Jackie-SDX/cpp-project-template  
**Audit baseline:** current main at 11d1726324f02f53988e9047ed3018a9545ff631  
**Latest published release examined:** v0.0.9, release commit eec83c9794d88469b17f6c3924a08bfae2030ee1  
**Latest release workflow run examined:** 35877971162  
**Audit record location:** this file is intentionally stored in Jackie-SDX/Nayla-SD-JACKIE-Fun-WhatsApp-Bot, not in the audited CPP repository.

## 1. Scope and hard-stop conditions

This is a forensic architecture audit only.

No source code, CMake configuration, CPack configuration, CI workflow, release configuration, installer definition, package definition, branch, tag, release, or other project state in cpp-project-template was modified during this investigation.

Requested archive policy:

| Platform | Published standalone archive |
|---|---|
| Windows | .zip |
| Linux | .tar.gz |
| macOS | .zip |

Windows .7z is not a release artifact. Historical .7z generation remains commented out in relevant packaging workflows, but no .7z was published in v0.0.9.

The audit evaluates the complete chain:

source -> build -> install tree -> package/installer -> validation -> signing/trust -> publication -> consumer installation/update/uninstall.

It does not treat successful CPack generation as proof of release readiness.

## 2. Confidence

**Repository/CI topology: HIGH confidence.**  
**Complete tracked-snapshot byte verification: HIGH confidence.**  
**Package configuration conclusions: HIGH confidence.**  
**Selected artifact-structure/binary-header claims: HIGH confidence for the recovered v0.0.9 GitHub Actions artifacts inspected in Round 2.**  
**Cryptographic signature validity, notarization, installer execution, and clean-machine behavior: NOT YET PROVEN.**

The repository tree was recursively enumerated in full. Relevant packaging/release files were then inspected in bounded sections. Current authoritative documentation was researched for CMake/CPack, Windows distribution/signing, Apple signing/notarization, Debian packaging, GitHub attestations, GitLab behavior, and reproducible builds.

Round 3 performed a full tracked-snapshot retrieval at the exact audited commit: all 156 tree entries (121 files, 34 directories plus the root tree entry) were enumerated without truncation; all 121 tracked file blobs were fetched as raw bytes and each was verified against the Git blob SHA. The tree declares 1,588,283 file bytes. High-risk source files were then re-read directly and the complete snapshot was searched for release/version/signing/archive/cache/identity controls. The audit does not claim that every byte was mentally reasoned over by an independent reviewer; it claims byte-complete retrieval and hash verification of the entire tracked snapshot, plus targeted source-level forensic analysis.

OpenCode/Copilot were not exposed as callable independent reviewer integrations. That is recorded as a missing verification rather than represented as completed.

The following remain unproven:
- cryptographic validity and certificate-chain verification for the embedded Windows PE certificate tables;
- validity of the Windows MSI signature, if any;
- Apple app-bundle structure inside the nested release ZIP;
- Apple code-signing identity, Hardened Runtime, notarization, stapling, and Gatekeeper assessment;
- exact installer install/upgrade/uninstall behavior on clean machines;
- complete runtime DLL/shared-library/framework closure across the whole release matrix;
- bit-for-bit reproducibility;
- binary-level SBOM/provenance verification;
- actual GitLab release output for the same tag.

## 3. Executive finding

The CPP project has a substantial and broad cross-platform packaging system. The current GitHub release path is materially stronger than a simple CPack-and-upload pipeline.

Strengths include:
- explicit platform/toolchain matrix;
- package naming containing platform/toolchain/architecture;
- active removal of Windows .7z publication;
- exact GitHub release inventory validation;
- global SHA-256 manifest generation and verification;
- successful v0.0.9 production release;
- architecture checks on selected release legs;
- pinned external toolchain revisions;
- most release-workflow third-party actions pinned by commit SHA.

However, the evidence does not support an enterprise-grade release-trust claim yet.

Primary gaps:

1. No demonstrated end-user code-signing/notarization chain.
2. No cryptographically verifiable release provenance/SBOM chain.
3. GitHub and GitLab do not enforce the same release contract.
4. macOS application-bundle architecture is incomplete.
5. Linux dependency metadata is manually asserted rather than demonstrated against the actual runtime closure.
6. Reproducibility is not demonstrated.
7. Published product profiles are not completely uniform.
8. GitHub release publication is configured to overwrite same-named files.
9. Release governance is weaker than the packaging complexity suggests.

**Verdict: capable cross-platform distribution system, but NOT yet evidence-backed enterprise-grade release infrastructure.**

## 4. Repository inventory

The full repository tree was recursively enumerated before targeted retrieval.

Relevant surfaces include:

### Build system
- CMakeLists.txt
- CMakePresets.json
- cmake/cpack_module.cmake
- CMake support modules
- conanfile.txt
- vcpkg.json

### Packaging resources
- packaging/windows/icon.ico
- packaging/windows/icon.rc
- packaging/windows/version.rc.in
- packaging/windows/nsis/*
- packaging/windows/wix/*
- packaging/apple/icon.icns
- packaging/apple/icon.png
- packaging/linux/icon_256x256.png
- packaging/linux/template.desktop.in
- assets/images/*

### Automation
- .github/workflows/release.yml
- .github/workflows/ci.yml
- .github/workflows/windows-package-smoke.yml
- .github/workflows/windows-arm64-package-smoke.yml
- .github/workflows/experimental-platform-matrix.yml
- .github/workflows/vcpkg-cache-warmup.yml
- .github/workflows/opencode.yml
- .github/scripts/configure.cmake
- .github/scripts/build.cmake
- .github/scripts/test.cmake
- .gitlab/.gitlab-ci.yml
- .circleci/config.yml

### Installation/documentation
- docs/install.md
- README.md
- project documentation/release records

### Target/install definitions
- src/projectcli/CMakeLists.txt
- src/projectlib/src/CMakeLists.txt
- src/projectwx/src/CMakeLists.txt

## 5. Current distribution inventory — v0.0.9

The published GitHub release contains **57 assets**:

- 54 platform packages
- 2 source archives
- 1 SHA256SUMS file

### Windows: 27 artifacts

Nine combinations:
- MSVC x86_64
- MSVC i686
- MSVC ARM64
- MinGW x86_64
- MinGW i686
- LLVM x86_64
- LLVM i686
- LLVM ARM64
- CLANGARM64 MinGW ARM64

Each has:
- .zip
- NSIS .exe
- WiX .msi

### Linux: 15 artifacts

Five combinations:
- GCC x86_64
- GCC i686
- GCC ARM64
- Clang x86_64
- Clang ARM64

Each has:
- .tar.gz
- .deb
- .rpm

### macOS: 12 artifacts

Six combinations:
- Apple Clang x86_64
- Clang ARM64
- GCC x86_64
- GCC ARM64
- LLVM x86_64
- LLVM ARM64

Each has:
- .zip
- .dmg

### Source/integrity
- versioned source ZIP
- versioned source tar.gz
- SHA256SUMS

### Windows .7z
No .7z was published in v0.0.9. The active release path honors the requested policy.

## 6. Current vs target matrix

The recommended target deliberately keeps the current artifact count rather than adding formats.

| OS | Variant family | Current | Target |
|---|---|---:|---|
| Windows | MSVC x86_64 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | MSVC i686 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | MSVC ARM64 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | MinGW x86_64 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | MinGW i686 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | LLVM x86_64 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | LLVM i686 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | LLVM ARM64 | ZIP + NSIS + WiX | same + signing/validation |
| Windows | CLANGARM64 MinGW ARM64 | ZIP + NSIS + WiX | same + signing/validation |
| Linux | GCC x86_64 | tar.gz + DEB + RPM | same + dependency/runtime validation |
| Linux | GCC i686 | tar.gz + DEB + RPM | same + dependency/runtime validation |
| Linux | GCC ARM64 | tar.gz + DEB + RPM | same + dependency/runtime validation |
| Linux | Clang x86_64 | tar.gz + DEB + RPM | same + dependency/runtime validation |
| Linux | Clang ARM64 | tar.gz + DEB + RPM | same + dependency/runtime validation |
| macOS | Apple Clang x86_64 | ZIP + DMG | same + real .app + signing/notarization |
| macOS | Clang ARM64 | ZIP + DMG | same + real .app + signing/notarization |
| macOS | GCC x86_64 | ZIP + DMG | same, explicit product profile |
| macOS | GCC ARM64 | ZIP + DMG | same, explicit product profile |
| macOS | LLVM x86_64 | ZIP + DMG | same + signing/notarization |
| macOS | LLVM ARM64 | ZIP + DMG | same + signing/notarization |
| Source | versioned source ZIP | current | keep |
| Source | versioned source tar.gz | current | keep |
| Integrity | SHA256SUMS | current | keep + authenticated provenance |

**Target artifact policy: no additional published formats are required by this audit.**

## 7. Windows assessment

### Windows ZIP — KEEP / HARDEN

The standalone Windows .zip should remain.

Strengths:
- explicit archive policy;
- deterministic naming contract at the workflow level;
- release inventory validation;
- SHA-256 publication.

Round 2 representative artifact evidence:
- the archive contains both projectcli.exe and projectwx.exe;
- both are AMD64 PE32+ payloads;
- the expected MSVC runtime DLL set is present;
- no unexpected extra files were found.

Hardening:
- runtime dependency closure across the full matrix;
- verify embedded payload signatures and certificate chains;
- sign the installer itself;
- binary architecture verification for every variant;
- clean-machine launch;
- documentation/license inventory;
- reproducibility evidence;
- signed provenance.

### Windows NSIS — KEEP / HARDEN

NSIS is a justified consumer-facing installer and is already part of the proven release matrix.

Do not remove it solely because WiX is available.

Required hardening:
- Authenticode signing;
- RFC 3161 timestamping;
- pre-publication signature verification;
- silent install and exit-code checks;
- upgrade from previous release;
- downgrade policy test;
- uninstall cleanliness;
- elevation and install-scope verification;
- PATH behavior verification.

Microsoft current guidance:
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
- https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

### Windows WiX/MSI — KEEP / HARDEN

Maintaining both NSIS and WiX remains justified because they can serve different deployment channels.

Recommended product role:
- NSIS: primary interactive consumer installer.
- WiX MSI: enterprise/managed deployment channel.

Do not remove WiX without deployment evidence.

Hardening:
- deterministic upgrade identity;
- major-upgrade tests;
- explicit downgrade behavior;
- clean-install/uninstall tests;
- silent installation;
- Authenticode signing;
- timestamping;
- signature verification;
- ARM64 validation.

Current CPack/WiX documentation:
- https://cmake.org/cmake/help/latest/cpack_gen/wix.html
- https://wixtoolset.org/

### Windows .7z — REMOVE FROM PUBLISHING / KEEP DISABLED HISTORICAL BLOCK ONLY

Current state is correct. Do not restore it to the release artifact list.

## 8. macOS assessment

### macOS ZIP — KEEP / FIX

ZIP is a reasonable direct-distribution surface, but only if it contains a properly formed and signed application bundle for the GUI product.

Apple documentation:
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution

### macOS DMG — KEEP / FIX

DMG is a justified consumer distribution surface and should remain.

Current evidence proves DMG generation but not release trust.

Missing demonstrated controls:
- Developer ID signing;
- Hardened Runtime;
- notarization submission/result;
- stapling;
- Gatekeeper assessment.

Sources:
- https://developer.apple.com/documentation/Security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/Security/hardened-runtime

### macOS .app bundle — FIX

This is the most important macOS packaging architecture issue.

The project configures macOS CPack bundle-related variables, but the GUI executable target is not configured with the CMake MACOSX_BUNDLE target property.

CMake documents MACOSX_BUNDLE as the target property that creates an application bundle on macOS.

Therefore:

**DMG generation: proven.**  
**Correct .app bundle structure: not proven and likely incomplete.**

Required future validation:
- inspect Contents/MacOS;
- inspect Info.plist;
- inspect resources;
- inspect dylibs/frameworks;
- sign nested code from the inside out;
- enable and verify Hardened Runtime;
- submit to Apple notarization;
- staple ticket;
- validate stapling;
- run Gatekeeper assessment;
- launch on clean macOS.

Sources:
- https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE.html
- https://cmake.org/cmake/help/latest/cpack_gen/dmg.html
- https://cmake.org/cmake/help/latest/cpack_gen/bundle.html

## 9. Linux assessment

### DEB — KEEP / FIX

DEB remains justified.

Current dependency declarations include:
- libc6 >= 2.32
- libstdc++6 >= 12
- GUI alternative including libwxgtk3.2-1 or libwxgtk3.2-dev

The Round 2 artifact inspection found a concrete metadata defect in the representative published GCC x86_64 DEB: the filename is cpp-project-template_0.0.9_linux-gcc-x86_64.deb, but the package control metadata declares Version: 0.0.1. The same control record also identifies Maintainer: NaylaCruz and Homepage: https://github.com/NaylaCruz/cpp-project-template, which do not match the audited repository identity. This is a release metadata/source-of-truth failure, not merely a documentation concern.

The actual control metadata also confirms the runtime dependency declaration:
libc6 (>= 2.32), libstdc++6 (>= 12), libwxgtk3.2-1 | libwxgtk3.2-dev.

The package contains control and md5sums in control.tar.gz; no maintainer scripts or conffiles were detected in the inspected control archive.

This evidence upgrades DEB from a purely static concern to a concrete FIX finding.

Validation required:
- dpkg-deb metadata/content;
- dependency resolution;
- clean install;
- upgrade;
- remove;
- runtime launch;
- runtime library checks.

Sources:
- https://www.debian.org/doc/debian-policy/ch-relationships.html
- https://www.debian.org/doc/debian-policy/ap-pkg-binarypkg.html
- https://www.debian.org/doc/debian-policy/ch-controlfields.html

### RPM — KEEP / FIX

RPM is justified.

Current metadata includes:
- glibc >= 2.32
- libstdc++ >= 12
- GUI wxGTK3

Validation required:
- RPM metadata;
- Requires;
- scriptlets;
- file ownership;
- install/upgrade/remove;
- runtime launch;
- dependency resolution;
- signing verification.

Reference:
- https://rpm.org/docs/

### Linux tar.gz — KEEP / HARDEN

Keep the tar.gz policy.

Validate:
- file permissions;
- symlinks;
- runtime dependencies;
- architecture;
- documentation/licenses;
- deterministic metadata;
- clean execution.

## 10. Runtime dependency architecture

Install rules currently place:
- CLI executable in bin;
- GUI executable in bin when enabled;
- assets/images.

The repository search did not identify a general cross-platform runtime dependency closure stage using mechanisms such as CMake BundleUtilities/fixup_bundle or file(GET_RUNTIME_DEPENDENCIES).

Round 2 closes part of the runtime-payload evidence gap:

- Representative Windows x64 standalone ZIP: both executables are present and the expected MSVC runtime DLL set is bundled.
- Representative Linux x86_64 tar.gz: both executables are ELF64/x86-64 with PT_INTERP /lib64/ld-linux-x86-64.so.2, and no .so files are bundled.
- Therefore the Linux standalone archive is not self-contained in the broadest sense: it explicitly depends on a compatible host glibc dynamic loader/runtime, while other shared dependencies such as wxWidgets are not carried as local .so files.

This is not necessarily a defect; it is an explicit runtime compatibility requirement that must be documented and validated across supported Linux distributions.

The remaining evidence gap is full dependency closure across the entire release matrix and actual packaged launchability.

Risk is highest for:
- dynamic Windows configurations outside the inspected MSVC x64 representative;
- Linux distributions with incompatible glibc/wxGTK baselines;
- macOS dylibs/frameworks;
- multi-toolchain variants.

Required future control:
1. derive the runtime closure;
2. verify the installed tree;
3. validate package contents;
4. execute from the packaged tree rather than the CI build tree;
5. ensure host-installed libraries are not silently satisfying dependencies.

## 11. Cross-platform matrix findings

### Strength

The package naming system has been significantly hardened around project/version/system/toolchain/architecture and v0.0.9 proves the 54 package filenames are unique.

### Product-profile divergence

The v0.0.9 macOS GCC variants use BUILD_PROJECTWX=OFF and BUILD_TESTING=OFF, and their test step was skipped.

Therefore these artifacts are not necessarily functionally equivalent to the other macOS artifacts.

The product profile must be explicit in the release contract and documentation.

### Architecture verification is not uniform

Some expanded jobs verify binary architecture explicitly. Other published variants mainly verify install-tree presence or toolchain identity.

Future release policy should verify actual architecture for every published artifact:
- PE machine type on Windows;
- ELF class/machine on Linux;
- Mach-O architecture slices on macOS;
- package architecture metadata;
- filename-to-binary consistency.

## 12. GitHub release pipeline

The GitHub path is the strongest part of the current design.

Observed pipeline:

source checkout -> dependency/toolchain setup -> configure -> build -> test -> install -> validation -> package -> upload -> exact inventory validation -> checksum verification -> publish

v0.0.9 run:
https://github.com/Jackie-SDX/cpp-project-template/actions/runs/35877971162

Observed:
- 32 jobs;
- package jobs succeeded;
- exact release inventory validation succeeded;
- checksum validation succeeded;
- final publish succeeded.

Positive controls:
- explicit matrix;
- exact package filename gate;
- empty-artifact rejection;
- SHA256SUMS;
- sha256sum verification;
- pinned release actions by commit SHA;
- pinned external toolchain revisions;
- narrow write permission at publication.

### Finding: manifest duplication

The release contract is partly duplicated between the CMake naming logic, the workflow matrix, and the exact inventory list.

Future architecture should use one machine-readable release manifest consumed by both GitHub and GitLab.

### Finding: release asset overwrite

The GitHub publishing action is configured with overwrite_files=true.

That means the release process should not be treated as immutable without an additional control proving that same-name asset replacement is prohibited or impossible.

Target:
- validate once;
- publish exactly once;
- reject replacement of same-named assets;
- retain exact digests from the validated candidate set.

## 13. GitLab release pipeline

GitLab is the largest current release-integrity inconsistency.

The audited .gitlab-ci.yml deliberately has:
- allow_failure on package jobs;
- best-effort WiX;
- best-effort DEB/RPM;
- best-effort macOS DMG/ZIP;
- artifact upload even when package jobs are imperfect;
- a collector that publishes whatever artifacts exist.

GitLab documentation confirms that allow_failure permits a job to fail without failing the overall pipeline:
https://docs.gitlab.com/ci/yaml/

### Resulting risk

GitLab can publish a successful release containing only a partial subset of the intended matrix.

That is materially different from the GitHub release contract.

### Target architecture

Separate:
- optional experimental packaging jobs, which may remain allow_failure;
- release-eligible packaging jobs, which must pass a strict manifest gate.

GitLab and GitHub should publish the same validated release candidate, not separate ad-hoc matrices.

## 14. Supply-chain and security assessment

### Positive controls

- GitHub release actions mostly pinned by SHA.
- vcpkg revisions pinned.
- custom vcpkg triplet commit pinned.
- GitLab has commit/pipeline/job build attestations as plain JSON.
- SHA-256 hashes published.

### Authenticity gap

SHA-256 is integrity evidence, not publisher authenticity or build provenance.

### Windows

Repository configuration does not show an explicit installer-signing stage, and Round 2 artifact inspection now provides direct binary evidence:

- The representative v0.0.9 NSIS installer cpp-project-template_0.0.9_windows-msvc-x86_64_nsis.exe has a valid MZ/PE structure but PE Security Directory (DataDirectory[4]) VA=0, Size=0. No embedded Authenticode certificate table was detected in the installer itself.
- The representative payload executables inside the standalone ZIP, bin/projectcli.exe and bin/projectwx.exe, are both PE32+ AMD64 (Machine=0x8664) and both contain non-zero PE Security Directory entries, proving that certificate-table data is embedded in those payload binaries. The actual signer identity, trust chain, timestamp, and cryptographic validity were not verified.
- The WiX MSI is a valid OLE Compound File. The available binary inspection did not establish its signature state.

Therefore the Windows finding is now more precise: the representative NSIS installer is concretely unsigned at the PE certificate-table level, while the bundled payload executables contain embedded certificate tables whose validity is still unverified.

Sources:
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
- https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures

### macOS

No visible:
- Developer ID signing;
- Hardened Runtime enforcement;
- notarization;
- stapling;
- Gatekeeper verification.

Sources:
- https://developer.apple.com/documentation/Security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/Security/hardened-runtime

### Linux

No visible:
- RPM signing;
- Debian package signing;
- signed release metadata;
- artifact-level cryptographic provenance.

### SBOM/provenance

GitHub currently supports signed artifact attestations, including provenance and SBOM:
- https://docs.github.com/en/actions/concepts/security/artifact-attestations
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations

The audited release path does not use these mechanisms.

### Recommended trust chain

build provenance
-> SBOM
-> code/package signing
-> verification
-> checksum
-> signed artifact attestation
-> publication

## 15. Reproducibility

Bit-for-bit reproducibility is not demonstrated.

The release workflow manually constructs several binary archives. No repository-level release policy was found that normalizes timestamps and archive metadata across these paths.

SOURCE_DATE_EPOCH is the established ecosystem mechanism for deterministic build timestamps:
https://reproducible-builds.org/docs/source-date-epoch/

Recommended future validation:
- deterministic timestamp inputs;
- deterministic archive metadata;
- deterministic ordering;
- independent rebuild;
- diffoscope comparison;
- recorded reproduction result.

A checksum of a release file is not reproducible-build evidence.

## 16. Documentation findings

docs/install.md correctly documents:
- Windows .zip;
- Linux .tar.gz;
- macOS .zip;
- no published .7z.

It also documents a macOS productbuild packaging path, even though that is not part of the current published artifact matrix.

This should eventually be made explicit as:
- published release artifact;
- advanced/local packaging option;
- historical option.

The installation guide also contains older repository/upstream references that do not match the current canonical ownership.

These are documentation-quality findings, not evidence of current artifact breakage.

## 17. Format decisions

| Format | Decision | Rationale |
|---|---|---|
| Windows ZIP | KEEP / HARDEN | correct generic archive channel |
| Windows NSIS | KEEP / HARDEN | consumer installer role |
| Windows MSI/WiX | KEEP / HARDEN | enterprise/managed deployment role |
| Windows 7z | REMOVE FROM PUBLISHING | explicit product policy |
| macOS ZIP | KEEP / FIX | useful direct-distribution channel |
| macOS DMG | KEEP / FIX | useful consumer distribution channel |
| Linux DEB | KEEP / FIX | native Debian-family packaging |
| Linux RPM | KEEP / FIX | native RPM-family packaging |
| Linux tar.gz | KEEP / HARDEN | generic Linux distribution |
| MSIX | CONSIDER | evaluate only for a specific Store/managed/update requirement |
| AppImage | CONSIDER | no current evidence requiring it |
| Flatpak | CONSIDER | no current evidence requiring it |
| Snap | CONSIDER | no current evidence requiring it |
| Arch package | CONSIDER | no current evidence requiring it |
| macOS productbuild | CONSIDER / documentation-only until explicitly supported | not in current release matrix |

## 18. Exact future changes proposed

No changes below were applied during this audit.

### .github/workflows/release.yml
Purpose:
- signing/notarization/provenance stages;
- immutable publication;
- shared manifest;
- uniform architecture checks;
- package metadata checks;
- SBOM/provenance generation and verification.

### .gitlab/.gitlab-ci.yml
Purpose:
- distinguish experimental optional jobs from release-eligible jobs;
- strict release manifest;
- prevent successful partial production releases;
- match GitHub release behavior.

### cmake/cpack_module.cmake
Purpose:
- centralize package metadata;
- correct runtime dependency declarations;
- support explicit validation contracts;
- reduce duplicated naming/format logic.

### src/projectwx/src/CMakeLists.txt
Purpose:
- create a real macOS application bundle for the GUI product;
- make app-bundle/signing behavior explicit.

### CMakeLists.txt
Purpose:
- explicit install components/product profiles;
- clearer release package composition.

### .github/workflows/windows-package-smoke.yml
Purpose:
- install/upgrade/uninstall/launch/signature validation;
- standardized action pinning.

### .github/workflows/windows-arm64-package-smoke.yml
Purpose:
- retain ARM64 architecture validation;
- standardize action pinning;
- make regression coverage less branch-specific.

### docs/install.md
Purpose:
- distinguish published artifacts from local packaging options;
- document installer roles and signing expectations;
- clean stale references.

### New release manifest/evidence contract
Purpose:
- one source of truth for supported release combinations, filenames, package formats, product profiles, required tests, required signatures and required attestations.

## 19. Changes deliberately NOT advised

- Do not remove WiX without enterprise deployment evidence.
- Do not remove NSIS without consumer-distribution evidence.
- Do not add MSIX yet.
- Do not add AppImage/Flatpak/Snap/Arch packages merely for symmetry.
- Do not restore Windows .7z.
- Do not maintain independent GitHub and GitLab production matrices.

## 20. Open risks

| Risk | Severity | Status |
|---|---|---|
| Published GCC x86_64 DEB declares Version 0.0.1 under a v0.0.9 filename | Critical | proven from artifact bytes |
| Published DEB metadata still identifies NaylaCruz repo/maintainer | High | proven from artifact bytes |
| Representative NSIS installer has no PE certificate table | High | proven from artifact bytes |
| macOS app-bundle structure not fully established | Critical | unresolved |
| macOS signing/Hardened Runtime/notarization not demonstrated | Critical | unresolved |
| GitLab can publish partial releases | High | proven by configuration |
| Artifact provenance/SBOM not cryptographically published | High | unresolved |
| GitHub release overwrite configuration | High | configuration finding |
| GitHub release resolves VERSION after configure/build, leaving internal package metadata at the local placeholder | Critical | proven from full source + Round 2 artifact |
| GitHub Windows cache gate is conditioned on old NaylaCruz repository identity | High | proven from source |
| CMake package metadata still points at NaylaCruz repository/author identity | High | proven from source |
| Release workflow contains stale 85-package inventory comment | Medium | proven from source |
| Linux runtime compatibility depends on host loader/glibc and undeclared host shared libraries | High | proven for representative tarball; matrix-wide validation pending |
| Complete runtime DLL/shared-library/framework closure not proven | High | matrix-wide validation pending |
| Reproducibility not demonstrated | High | unresolved |
| Architecture verification not uniform | Medium/High | configuration finding |
| macOS GCC product profile differs and skips tests | Medium | proven in v0.0.9 run |
| Documentation drift | Medium | proven |
| CPP main branch currently unprotected | Medium | GitHub branch metadata |
| auxiliary CI paths are not equivalent to production release validation | Medium | topology finding |

## 21. Validation evidence

### Repository/static validation
Performed:
- full recursive repository-tree inventory;
- complete raw retrieval of all 121 tracked blobs at the audited commit;
- Git blob SHA verification for all 121 files with zero mismatches;
- targeted retrieval of all packaging, CPack, installer, workflow, GitLab, dependency, install and documentation surfaces;
- bounded analysis of long workflow files;
- cross-reference of install targets and release packaging;
- search for signing, notarization, SBOM, provenance, runtime dependency, RPATH/install-name and archive controls;
- inspection of vcpkg/toolchain pins.

### v0.0.9 GitHub validation
Run:
https://github.com/Jackie-SDX/cpp-project-template/actions/runs/35877971162

Observed:
- 32 jobs;
- package jobs successful;
- exact release inventory validation successful;
- checksum validation successful;
- publish successful.

Release:
https://github.com/Jackie-SDX/cpp-project-template/releases/tag/v0.0.9

Observed:
- 57 total assets;
- 54 platform package artifacts;
- 2 source archives;
- SHA256SUMS;
- no .7z.

### Round 2 artifact-level validation

Round 2 used the connected GitHub Actions artifact download path plus a cloud-browser byte-inspection bridge to recover and inspect actual v0.0.9 build artifacts. This materially closes the artifact-byte limitation from Round 1.

#### Linux representative artifact

GitHub Actions artifact:
- workflow run: 35877971162
- artifact: release-Linux
- artifact ID: 10759980392
- GitHub artifact SHA-256: 1f9ea4c776cc02e496b9d872b3455510caa9d80e265e6b9031863f52cc42fd9b
- recovered raw ZIP size: 344,631 bytes
- recovered raw ZIP SHA-256: 1f9ea4c776cc02e496b9d872b3455510caa9d80e265e6b9031863f52cc42fd9b

The raw artifact passed an independent byte-level digest equality check against GitHub artifact metadata.

Outer members:
- cpp-project-template_0.0.9_linux-gcc-x86_64.deb
- cpp-project-template_0.0.9_linux-gcc-x86_64.rpm
- cpp-project-template_0.0.9_linux-gcc-x86_64.tar.gz

The tarball was decompressed and parsed:
- bin/projectcli: ELF64/x86-64, little-endian, PT_INTERP /lib64/ld-linux-x86-64.so.2, mode 0755
- bin/projectwx: ELF64/x86-64, little-endian, PT_INTERP /lib64/ld-linux-x86-64.so.2, mode 0755
- no .so files were present in the tarball
- documentation/license/icon/desktop files were present.

The DEB was parsed as an ar archive:
- debian-binary
- control.tar.gz
- data.tar.gz

Its control archive contains:
- control
- md5sums
- no maintainer scripts or conffiles detected.

Actual control metadata:
- Package: cpp-project-template
- Version: 0.0.1
- Architecture: amd64
- Maintainer: NaylaCruz
- Homepage: https://github.com/NaylaCruz/cpp-project-template
- Depends: libc6 (>= 2.32), libstdc++6 (>= 12), libwxgtk3.2-1 | libwxgtk3.2-dev

This is inconsistent with the published v0.0.9 filename and audited repository identity.

The RPM contains a structurally valid RPM lead and a non-empty signature-header region. Specific signer identity and cryptographic verification were not established.

#### Windows representative artifact

GitHub Actions artifact:
- artifact: release-Windows
- artifact ID: 10758957748
- size: 8,331,117 bytes

Outer members:
- cpp-project-template_0.0.9_windows-msvc-x86_64.zip
- cpp-project-template_0.0.9_windows-msvc-x86_64_nsis.exe
- cpp-project-template_0.0.9_windows-msvc-x86_64_wix.msi

The nested standalone ZIP contains:
- bin/projectcli.exe
- bin/projectwx.exe
- MSVC runtime DLLs including concrt140.dll, msvcp140*.dll, vcruntime140*.dll
- documentation/license
- image resource
- no unexpected extra files
- no .7z.

Payload PE measurements:
- projectcli.exe: MZ+PE, Machine 0x8664 AMD64, PE32+ 0x20b, Security Directory VA=286720, Size=115384
- projectwx.exe: MZ+PE, Machine 0x8664 AMD64, PE32+ 0x20b, Security Directory VA=5074944, Size=115720

The non-zero security directories prove embedded certificate-table data exists in those two payload executables. The actual certificate chain, signer, timestamp and cryptographic validity were not verified.

NSIS installer:
- MZ+PE
- installer PE Machine 0x14c (Intel 386) — this describes the installer stub, not the bundled application payload
- Security Directory VA=0, Size=0
- no embedded Authenticode certificate table detected.

WiX MSI:
- valid OLE Compound File structure
- signature state not established from the available byte inspection.

#### macOS representative artifact

GitHub Actions artifact:
- artifact: release-macOS
- artifact ID: 10759307322
- artifact size: 204,206 bytes

Outer members were recovered:
- cpp-project-template_0.0.9_macos-apple-clang-x86_64.dmg — 155,229 bytes uncompressed / 143,034 bytes compressed
- cpp-project-template_0.0.9_macos-apple-clang-x86_64.zip — 61,917 bytes uncompressed / 60,746 bytes compressed

Browser-side decompression limitations prevented reliable extraction of the nested macOS ZIP directory and a conclusive UDIF koly footer test on the inner DMG bytes. Therefore:
- real .app bundle structure remains unproven;
- the attempted compressed-member footer scan is not treated as proof of an invalid DMG;
- signing/notarization remains unverified.

#### What Round 2 still does not prove

Round 2 did not establish:
- clean install/upgrade/uninstall behavior;
- actual runtime launch on target OS images;
- SmartScreen behavior;
- Apple Gatekeeper/notarization result;
- certificate-chain validity for the embedded Windows payload signatures;
- MSI signing validity;
- Linux package installation/resolution across target distro versions;
- full release-matrix runtime closure;
- deterministic/reproducible rebuilds;
- GitLab production-release artifact parity.




## 21A. Round 3 — complete tracked-snapshot verification

Round 3 closed the repository-content coverage gap from the earlier targeted/static passes.

### Exact repository snapshot

Audited ref:

`11d1726324f02f53988e9047ed3018a9545ff631`

Git tree result:

- 156 total tree entries returned;
- 121 file blobs;
- 34 directory trees;
- recursive tree response was **not truncated**;
- declared tracked-file bytes: **1,588,283**.

Every one of the 121 file blobs was fetched through the connected GitHub raw-content path and persisted as raw bytes. For every fetched file, the Git blob object hash was independently recomputed as:

`sha1("blob " + byte_length + NUL + raw_bytes)`

and matched the SHA published by GitHub's recursive tree.

Result:

**121/121 files byte-verified against the audited Git snapshot; 0 mismatches.**

This is stronger evidence than rendered GitHub-page inspection because line endings, binary data, and non-text bytes were all included in the verification.

### Round 3 source-level findings

#### Critical: GitHub release version resolution occurs too late

The repository's CMake project defaults to:

`CPP_PROJECT_TEMPLATE_VERSION = 0.0.1.0`

when the CI does not pass an explicit version before `project(... VERSION ...)`.

The GitHub release workflow performs the real tag-version resolution in a later step named **Resolve release version and naming**. That step runs only after:

- CMake configure;
- build;
- tests;
- install;
- canonical CPack package-name determination.

It exports `VERSION` and `RELEASE_PREFIX` for subsequent filenames, but it does **not** pass `-D CPP_PROJECT_TEMPLATE_VERSION=...` back into the already-completed CMake configuration.

The result is exactly consistent with the Round 2 artifact finding:

- published filename: `cpp-project-template_0.0.9_linux-gcc-x86_64.deb`
- internal DEB metadata: `Version: 0.0.1`

The fourth CMake version component in `0.0.1.0` is not represented in the Debian package version, yielding `0.0.1`.

This is not merely a packaging-renaming problem. It is a **source-of-truth ordering defect in the GitHub release workflow**.

The GitLab pipeline provides useful contrast: its shared version-resolution anchors compute `RESOLVED_VERSION` and pass `-D CPP_PROJECT_TEMPLATE_VERSION=$RESOLVED_VERSION` during configure. Therefore GitHub and GitLab do not currently share the same release-version contract.

#### High: Windows release cache gate is keyed to the wrong repository identity

The GitHub release workflow contains:

`if: github.repository == 'NaylaCruz/cpp-project-template' && (...cache misses...)`

inside the Windows release cache gate.

The audited repository is:

`Jackie-SDX/cpp-project-template`

Therefore the final cache-enforcement step is skipped on the current canonical repository even when the required package/tool caches miss.

The job still runs, but the stated release-cache contract is not actually enforced for the repository being released.

This is a configuration/control-plane defect rather than a runtime artifact defect.

#### Medium: stale release-workflow inventory comment

The current release workflow still contains a comment describing an **85-package** expected inventory while the active release contract is 54 platform packages.

This does not by itself alter execution, but it is stale control-plane documentation inside a safety-critical release workflow and increases maintenance/error risk.

#### Medium: package metadata identity is duplicated in source configuration

The full-source pass confirms `CMakeLists.txt` still declares:

- homepage: `https://github.com/NaylaCruz/cpp-project-template`
- author/vendor identity: `NaylaCruz`

This directly explains why the published DEB carried the old identity. The Round 2 artifact finding therefore has a source-level root cause as well as an artifact-level manifestation.

#### Confirmed macOS architecture gap

The GUI target in `src/projectwx/src/CMakeLists.txt` is created with `add_executable(... WIN32 ...)` and does not set the CMake `MACOSX_BUNDLE` target property.

The project does set bundle-related variables in `cmake/cpack_module.cmake`, but those variables alone are not proof that the target is a real macOS application bundle.

The Round 1 conclusion is therefore confirmed by the full-source pass: the missing target-level bundle declaration remains an actual source-configuration issue.

### Round 3 unchanged conclusions

Round 3 does not overturn the existing evidence that:

- Windows ZIP + NSIS + WiX should remain;
- Linux tar.gz + DEB + RPM should remain;
- macOS ZIP + DMG should remain;
- Windows .7z should remain unpublished;
- code signing, notarization, SBOM/provenance and reproducibility remain incomplete;
- artifact install/upgrade/erase/launch behavior remains unproven matrix-wide.

## 22. Required future artifact validation

### Windows
For every published installer/archive:
- PE architecture;
- Authenticode signature and chain;
- RFC 3161 timestamp;
- silent install;
- exit code;
- install scope/prefix;
- file inventory;
- upgrade N-1;
- downgrade policy;
- uninstall;
- clean launch.

### macOS
For every variant:
- .app structure;
- Mach-O architecture;
- dylib/framework closure;
- code-sign verification;
- Developer ID identity;
- Hardened Runtime;
- entitlements;
- notarization;
- stapled ticket;
- stapler validation;
- Gatekeeper assessment;
- clean launch;
- DMG UX;
- ZIP extraction/launch.

### Linux DEB
- control metadata;
- architecture;
- Depends;
- package contents;
- maintainer scripts;
- install/upgrade/remove;
- runtime launch.

### Linux RPM
- package metadata;
- architecture;
- Requires;
- scriptlets;
- file ownership;
- install/upgrade/erase;
- runtime launch;
- signature verification.

### Standalone archives
- contents;
- modes/symlinks;
- architecture;
- runtime dependencies;
- documentation/licenses;
- deterministic metadata;
- clean execution.

## 23. Recommended release trust model

Target:

**Source commit**
-> **reproducible build**
-> **installed-tree verification**
-> **package build**
-> **binary/package architecture validation**
-> **runtime dependency validation**
-> **code signing**
-> **SBOM generation**
-> **provenance attestation**
-> **signature/attestation verification**
-> **checksum manifest**
-> **immutable publication**
-> **post-publication digest verification**

Package commands should never be the sole release gate.

## 24. Enterprise-readiness decision

### Current classification

**NOT YET ENTERPRISE-GRADE by evidence.**

This does not mean the project lacks a serious packaging system.

It means the repository currently demonstrates:
- broad packaging coverage;
- a sophisticated matrix;
- strong GitHub inventory control;
- checksum generation;
- significant CI hardening;

but does not yet demonstrate the complete trust chain expected for serious production distribution.

### Target classification

The project can reach an evidence-backed enterprise-grade posture without adding many more artifact formats.

Priority:
1. real macOS app bundle;
2. Windows signing/timestamping;
3. macOS signing/Hardened Runtime/notarization;
4. Linux package signing;
5. SBOM + signed provenance;
6. immutable release publication;
7. GitHub/GitLab release-contract convergence;
8. runtime dependency validation;
9. reproducibility evidence;
10. install/upgrade/uninstall regression coverage.

## 25. Evidence URLs

### Project
- https://github.com/Jackie-SDX/cpp-project-template
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/CMakeLists.txt
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/cmake/cpack_module.cmake
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/.github/workflows/release.yml
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/.github/workflows/windows-package-smoke.yml
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/.github/workflows/windows-arm64-package-smoke.yml
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/.gitlab/.gitlab-ci.yml
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/docs/install.md
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/src/projectwx/src/CMakeLists.txt
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/src/projectcli/CMakeLists.txt
- https://github.com/Jackie-SDX/cpp-project-template/blob/main/vcpkg.json

### Release evidence
- https://github.com/Jackie-SDX/cpp-project-template/releases/tag/v0.0.9
- https://github.com/Jackie-SDX/cpp-project-template/actions/runs/35877971162
- GitHub Actions artifacts for Round 2 were recovered through the connected artifact-download path and inspected byte-level in a cloud-browser sandbox; artifact IDs and measured sizes are recorded in the Round 2 validation section.

### CMake / CPack
- https://cmake.org/cmake/help/latest/manual/cpack-generators.7.html
- https://cmake.org/cmake/help/latest/cpack_gen/wix.html
- https://cmake.org/cmake/help/latest/cpack_gen/dmg.html
- https://cmake.org/cmake/help/latest/cpack_gen/bundle.html
- https://cmake.org/cmake/help/latest/prop_tgt/MACOSX_BUNDLE.html

### Windows
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/choose-distribution-path
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
- https://learn.microsoft.com/en-us/windows/win32/seccrypto/time-stamping-authenticode-signatures
- https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
- https://wixtoolset.org/

### Apple
- https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution
- https://developer.apple.com/documentation/Security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/Security/hardened-runtime
- https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle

### Linux
- https://www.debian.org/doc/debian-policy/ch-relationships.html
- https://www.debian.org/doc/debian-policy/ap-pkg-binarypkg.html
- https://www.debian.org/doc/debian-policy/ch-controlfields.html
- https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html
- https://rpm.org/docs/

### Provenance / reproducibility
- https://docs.github.com/en/actions/concepts/security/artifact-attestations
- https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations
- https://docs.gitlab.com/ci/yaml/
- https://docs.gitlab.com/ci/jobs/job_artifacts/
- https://reproducible-builds.org/docs/source-date-epoch/
- https://spdx.dev/

## 26. Final audit statement

This document records the repository and release architecture as evidenced on 2026-09-23.

No CPP repository code or packaging configuration was changed as part of this audit.

The current system is capable of producing a large cross-platform artifact matrix, and v0.0.9 demonstrates that its strongest GitHub path can validate and publish the intended package inventory.

Round 2 materially strengthened the evidence base by recovering and parsing real GitHub Actions build artifacts.

Round 3 then closed the repository-content coverage gap: the entire tracked snapshot was retrieved as raw bytes and every Git blob hash matched the audited commit. Round 3 also established the source-level cause of the DEB version drift and identified the stale GitHub cache-gate repository condition. It also exposed concrete release defects that static configuration review alone did not prove:

- the published GCC x86_64 DEB carries Version: 0.0.1 under a v0.0.9 filename;
- the same DEB still identifies NaylaCruz as maintainer/homepage;
- the representative NSIS installer has no embedded Authenticode certificate table;
- the representative Windows application payloads do contain embedded certificate tables;
- the representative Linux binaries are ELF64/x86-64 and depend on the host /lib64/ld-linux-x86-64.so.2;
- the Linux tarball carries no shared .so files;
- macOS outer release structure is proven, but the .app and notarization chain remain unresolved.

The remaining work is therefore primarily about release trust, metadata correctness, platform validation, and reproducibility rather than adding more packaging formats.

Until those controls are corrected and demonstrated across the release matrix, the project should be described as a well-developed cross-platform packaging pipeline under hardening, not as an evidence-backed enterprise-grade software distribution system.
