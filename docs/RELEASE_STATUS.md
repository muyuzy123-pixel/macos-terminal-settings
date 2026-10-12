# Repository and preview release status

## v1.10.0-preview.1 — 1.10.0 (Build 19)

The current preview removes in-app administrator authorization and power writes, provides Terminal commands and manual recovery for old power records, adds deferred Dock/Finder restarts with persistent reminders, and improves drafts, notices, shortcuts, and row layout. **Spanish translations have not yet been reviewed by a native speaker.** **西班牙语译文尚未经母语者审阅。** **Las traducciones al español aún no han sido revisadas por una persona hablante nativa.**

- [Preview release](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.10.0-preview.1) · [Release notes](publication/v1.10.0-preview.1-notes.md).
- Fixed source: [e8f62725eb61d4e1cd1c9779a3dfb7ec4cf2a414](https://github.com/muyuzy123-pixel/macos-terminal-settings/commit/e8f62725eb61d4e1cd1c9779a3dfb7ec4cf2a414); [source CI](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/38256266681).
- Published at **2026-10-12T13:39:28Z**. Frozen-source, contract, build, independent archive, isolated GUI, and anonymous-download results are recorded in the [Build 19 release verification](https://github.com/muyuzy123-pixel/macos-terminal-settings/blob/main/docs/publication/v1.10.0-preview.1-verification.json). Use that record for actual checks and asset hashes; earlier reports are historical evidence.
- Power commands run by the user in Terminal are outside in-app Undo. Old power Undo/WAL records are read and validated but never replayed; incomplete records retain the write lock until a consistent state is checked.
- Dock waits for a three-second quiet period and idle writes/refreshes; Finder waits for an explicit restart request. Pending reminders survive relaunch and resume with manual confirmation. Per-process completion preserves other in-flight and newly pending reminders.
- **Physical mouse-hover timing and VoiceOver have not been accepted in the running app.** Automated timing policies do not verify actual pointer events, spoken announcements, or VoiceOver activation/deactivation. Real managed-profile behavior and device effects remain separate acceptance.
- Distribution is Apple silicon **arm64**, **macOS 14.0 deployment target**, **ad-hoc signed with Hardened Runtime**, with no Developer ID or Apple notarization. Real macOS 14 runtime and Gatekeeper acceptance are not claimed.
- Current README screenshots describe Build 19 and unapplied 48/64-point drafts. They do not establish Apply, restart, hover, or VoiceOver acceptance.
- Earlier preview tags and Release attachments remain unchanged. The original archive remains private and is not marked read-only archived; historical publication and validation reports below are preserved.

## v1.9.0-preview.2 — 1.9.0 (Build 18) — historical record

The new preview includes English, Simplified Chinese, and Spanish, and corrects the Dock numeric validation hint to show the actual 1 pt step. **Spanish translations have not yet been reviewed by a native speaker.** **西班牙语译文尚未经母语者审阅。** Codex semantic review, automated checks, and directed GUI checks do not replace human native-speaker review.

- [Preview release](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.9.0-preview.2) · [Release notes](publication/v1.9.0-preview.2-notes.md).
- Fixed source: [`3356c839c24cd5cde29d7dfddf4811d3e94294c9`](https://github.com/muyuzy123-pixel/macos-terminal-settings/commit/3356c839c24cd5cde29d7dfddf4811d3e94294c9); [source CI](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/38095354478).
- Published at **2026-10-10T23:38:24Z**. Final Build 18 contracts, build, independent archive checks, isolated launch/language/search/draft/persistence smoke checks, and anonymous downloads passed. All three downloaded SHA-256 values match the frozen assets; the before/after audit of 46 preference addresses, power, production app state and recovery files remained unchanged after QA cleanup. See the [release verification record](publication/v1.9.0-preview.2-verification.json). Full integration and broader GUI acceptance were not repeated for Build 18.
- The [2026-10-09 Spanish acceptance report](validation/spanish-localization-2026-10-09.md) records the earlier unpublished Build 17 checks on macOS 26.6.2. It is historical evidence, not final-package acceptance of Build 18.
- Distribution remains Apple silicon arm64, macOS 14.0 deployment target, ad-hoc signed with Hardened Runtime, without Developer ID signing or Apple notarization. Real macOS 14 device acceptance, managed-profile behavior, and real privileged-write acceptance remain outstanding.
- Existing English and Simplified Chinese README screenshots are retained. The original `v1.9.0-preview.1` tag and three release attachments remain unchanged; the original archive repository remains private and is not marked read-only archived.

## First public release — historical record (September 2026)

Prepared from the 1.9.0 (Build 17) development baseline on 2026-09-19. On 2026-09-20, the maintainer selected MIT and authorized the private repository [muyuzy123-pixel/macos-terminal-settings](https://github.com/muyuzy123-pixel/macos-terminal-settings). The original repository was subsequently renamed to `macos-terminal-settings-private-archive` and retained as private. A new independent repository now uses the original name; the migration and checks are recorded in [PUBLIC_RELEASE_READINESS.md](PUBLIC_RELEASE_READINESS.md).

### Completed locally for the first public release

- Imported the necessary source, localization, test suite, bundle metadata, icon, and build inputs. `upstream-baseline.json` records their original hashes.
- Left the original development directory and historical archives unchanged. Excluded raw QA records, machine snapshots, previous binaries, and one-time localization migration scripts.
- Added English/Chinese README files, contributor/security guidance, reference attribution, and a release procedure.
- Kept all Swift/C app source, tests, localization resources, and Info.plist byte-identical to Build 17. Changes to imported inputs are limited to build/verify scripts and the regenerated icon.
- Shared toolchain resolution honors DEVELOPER_DIR/SDKROOT and validates SDK metadata. Clean bundle replacement avoids stale files from an older build. Temporary staging and the independently unpacked ZIP require strict signature validation; the Documents working copy uses normal signature validation because File Provider can reattach Finder metadata asynchronously.
- Regenerated the icon from the checked-in AppKit drawing source and verified all ten standard 1x/2x representations.
- Added read-only CI for contract tests, compilation, and independent packaging verification. CI does not publish a release or assume a virtual machine has real power settings.

### First-release verification

Environment: Apple silicon arm64, macOS 26.6.2 (25G83), Swift 6.3.3, macOS 26.5 SDK; app deployment target 14.0.

- Full-app type checking and contract checks passed, including 509 localization resource keys, bilingual catalog behavior, zero-effect language switching, locale formats, old Undo compatibility, and verbatim diagnostics.
- Isolated integration checks passed outside the execution sandbox. The first sandbox attempt could not write a random test preference domain and was not counted as a pass.
- Read-only snapshots before and after the successful integration run matched across all 46 catalog/context addresses, pmset, application preferences, application/Undo/WAL files, test residues, crash reports, and recorded environment.
- The MIT-licensed package was rebuilt and rechecked on 2026-09-20, including byte-for-byte license notice verification. The final ZIP passed independent file-allowlist/CRC checks, exact resource comparisons, arm64 and macOS 14.0/SDK 26 metadata checks, strict code signing, ad-hoc identity, and Hardened Runtime checks.
- Final ZIP SHA-256: `9c1e3f429ccc4012c1c52854edb5c5706c7c4f7f9819f65809c9d9b549986c52`.
- `dist/SHA256SUMS` was checked against the actual `dist/TerminalSettings.zip`; it passed. `dist/release-manifest.json` contains the detailed artifact evidence without local absolute paths.
- Public source inputs were scanned for private user paths and common credential/private-key patterns; none were found. This is a scoped source inspection, not a proof against all possible secrets.

### First-release repository distribution

- Anonymous source/download access and privacy isolation passed; see the [publication verification record](publication/verification.json).
- License: [MIT](../LICENSE), copyright 2026 muyuzy123-pixel. The license notice is included in the app bundle and verified against the repository copy.
- The active repository became **public** on 2026-09-20 02:03:59 UTC. The original archive remains **private**. See [PUBLIC_RELEASE_READINESS.md](PUBLIC_RELEASE_READINESS.md) for migration, privacy isolation, and publication details.
- [Public-preparation CI](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/35482821644) passed for screenshot/documentation commit `cdb2478e5caafbd795e48ea4f9a9a85d61947e38`. Final publication-status documentation does not change the tested application or build inputs.
- The [v1.9.0-preview.1 prerelease](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.9.0-preview.1) is publicly available with the same three verified assets. Source author-email metadata has been sanitized; application source files and release asset bytes remain unchanged.

The first-publication screenshot provides limited visual evidence for the English Dock size panel in an isolated copy: current values 35/37 points and unapplied drafts 48/64 points. Screenshot capture did not exercise Apply or device effects; the before/after audit of all 46 preference addresses, power settings, production app state, recovery files, and residue inventory passed unchanged. This is not broader GUI or device-effect acceptance. Historical Build 17 UI results remain historical. Real macOS 14, managed profiles, advanced power writes, Developer ID, notarization, and migration away from the legacy authorization API remain outside this local validation.


## Screenshot correction — historical record (2026-09-22)

The English README now uses an English capture and the Chinese README a Simplified Chinese capture. Both are native 2120×1520 RGBA PNGs with transparent corners, without the Computer Use pointer or an added white matte. No pixels were upscaled or passed through JPEG. The native window's own thin frame remains visible.

The captures show unchanged current values 35/37 and unapplied drafts 48/64. This run independently verified all 46 production preference addresses, power settings, production app state/recovery files, and residue inventory unchanged after QA cleanup. It is a limited visual check, not new device-effect acceptance. Application code, the preview tag, and all three release assets remain unchanged. See the [dated screenshot verification](publication/screenshots-2026-09-22.json); the first-publication record above remains historical.
