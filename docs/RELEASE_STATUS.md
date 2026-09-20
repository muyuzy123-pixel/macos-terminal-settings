# Repository and preview release status

Prepared from the 1.9.0 (Build 17) development baseline on 2026-09-19. On 2026-09-20, the maintainer selected MIT and authorized the private repository [muyuzy123-pixel/macos-terminal-settings](https://github.com/muyuzy123-pixel/macos-terminal-settings). The original repository was subsequently renamed to `macos-terminal-settings-private-archive` and retained as private. A new independent private repository now uses the original name; the migration and checks are recorded in [PUBLIC_RELEASE_READINESS.md](PUBLIC_RELEASE_READINESS.md).

## Completed locally

- Imported the necessary source, localization, test suite, bundle metadata, icon, and build inputs. `upstream-baseline.json` records their original hashes.
- Left the original development directory and historical archives unchanged. Excluded raw QA records, machine snapshots, previous binaries, and one-time localization migration scripts.
- Added English/Chinese README files, contributor/security guidance, reference attribution, and a release procedure.
- Kept all Swift/C app source, tests, localization resources, and Info.plist byte-identical to Build 17. Changes to imported inputs are limited to build/verify scripts and the regenerated icon.
- Shared toolchain resolution honors DEVELOPER_DIR/SDKROOT and validates SDK metadata. Clean bundle replacement avoids stale files from an older build. Temporary staging and the independently unpacked ZIP require strict signature validation; the Documents working copy uses normal signature validation because File Provider can reattach Finder metadata asynchronously.
- Regenerated the icon from the checked-in AppKit drawing source and verified all ten standard 1x/2x representations.
- Added read-only CI for contract tests, compilation, and independent packaging verification. CI does not publish a release or assume a virtual machine has real power settings.

## Verification performed here

Environment: Apple silicon arm64, macOS 26.6.2 (25G83), Swift 6.3.3, macOS 26.5 SDK; app deployment target 14.0.

- Full-app type checking and contract checks passed, including 509 localization resource keys, bilingual catalog behavior, zero-effect language switching, locale formats, old Undo compatibility, and verbatim diagnostics.
- Isolated integration checks passed outside the execution sandbox. The first sandbox attempt could not write a random test preference domain and was not counted as a pass.
- Read-only snapshots before and after the successful integration run matched across all 46 catalog/context addresses, pmset, application preferences, application/Undo/WAL files, test residues, crash reports, and recorded environment.
- The MIT-licensed package was rebuilt and rechecked on 2026-09-20, including byte-for-byte license notice verification. The final ZIP passed independent file-allowlist/CRC checks, exact resource comparisons, arm64 and macOS 14.0/SDK 26 metadata checks, strict code signing, ad-hoc identity, and Hardened Runtime checks.
- Final ZIP SHA-256: `9c1e3f429ccc4012c1c52854edb5c5706c7c4f7f9819f65809c9d9b549986c52`.
- `dist/SHA256SUMS` was checked against the actual `dist/TerminalSettings.zip`; it passed. `dist/release-manifest.json` contains the detailed artifact evidence without local absolute paths.
- Public source inputs were scanned for private user paths and common credential/private-key patterns; none were found. This is a scoped source inspection, not a proof against all possible secrets.

## Repository distribution

- License: [MIT](../LICENSE), copyright 2026 muyuzy123-pixel. The license notice is included in the app bundle and verified against the repository copy.
- Visibility remains **private** while public-release preparation is completed. See [PUBLIC_RELEASE_READINESS.md](PUBLIC_RELEASE_READINESS.md) for the completed migration that isolates the historical-email remnants in the private archive. Public access still requires a separate instruction.
- Fresh [GitHub Actions verification](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/35481438157) passed in the new repository for migrated commit `c95b4971d60c663b3c253ee0b24d6a1ec3fd4147`. Later migration-status documentation does not change the tested application or build inputs.
- The [v1.9.0-preview.1 prerelease](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.9.0-preview.1) is available to repository collaborators with three verified assets. Source author-email metadata has been sanitized; application source files and release asset bytes remain unchanged.

The first-publication screenshot provides limited visual evidence for the English Dock size panel in an isolated copy: current values 35/37 points and unapplied drafts 48/64 points. Screenshot capture did not exercise Apply or device effects; the before/after audit of all 46 preference addresses, power settings, production app state, recovery files, and residue inventory passed unchanged. This is not broader GUI or device-effect acceptance. Historical Build 17 UI results remain historical. Real macOS 14, managed profiles, advanced power writes, Developer ID, notarization, and migration away from the legacy authorization API remain outside this local validation.
