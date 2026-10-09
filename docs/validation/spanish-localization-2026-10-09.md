# Spanish localization acceptance — 2026-10-09

PR #1 was revised and checked locally on Apple silicon, macOS 26.6.2 (25G83), Swift 6.3.3, macOS 26.5 SDK, with the deployment target kept at 14.0. This is acceptance of the directed language-change scenarios below, not a claim that every device effect or every translated sentence has been accepted.

## Corrections

- Both READMEs now distinguish Spanish development-source support from the released `v1.9.0-preview.1` download, which still has English and Simplified Chinese. Instructions identify the PR branch while it is unmerged.
- UI test guidance covers every supported interface language.
- Regional tests now include `es_ES` and `es_MX`; test inputs use `Locale.decimalSeparator`. Parsed values still generate fixed-format command arguments.
- Language-resolution tests additionally cover underscore/case forms and an unsupported first language followed by Spanish, preserving the original first-preference fallback policy.
- The Spanish restore explanation now explicitly says restoration is blocked when external changes are detected.
- Actual GUI checking found a pre-existing numeric-message bug: rejecting Dock size `48.5` displayed a multiple of **16 pt**, although the step is **1 pt**. The step had been formatted through range normalization. Only measurement formatting was corrected; validation, ranges, stepping, stored values and writes are unchanged. A three-language regression checks the correct step and that `49` remains valid.

## Automated results

| Check | Result |
| --- | --- |
| Complete app type-check and localization contracts | Passed; 509 matching resource keys, placeholder/empty/duplicate checks |
| `verify.sh --contract-only` | Passed before the GUI-discovered prompt correction; the final full run repeats these contracts |
| Final full `verify.sh` | Passed; random test domains and read-only live power parsing, no real catalog settings applied |
| Final app build and independent archive check | Passed; en/es/zh-Hans resources and inventory present, arm64, minimum macOS 14.0, strict signature and MIT notice checked |
| Numeric regions | en_US, zh_CN, de_DE, es_ES, es_MX passed; display/input follows region, actual commands retain a dot separator |
| Language resolution and step-message regressions | Passed |

Build inputs and outputs were isolated in temporary directories so the published local baseline and Release assets were not replaced. The acceptance candidate remains version 1.9.0/Build 17 as an unpublished PR build; a future Spanish release requires its own version and validation record.

## Directed GUI results

A separate QA build uses the production views, models and resources unchanged, with a unique Bundle ID. Its temporary App entrypoint adds a test-only menu to change language without navigating away from the focused editor and to request default/minimum window sizes. This menu is not in the repository's application source or production build. Capture/automation permissions belong to the test tools; the app's permission design is unchanged.

| Scenario | Observed result |
| --- | --- |
| Default 1060×760 and minimum 820×672 outer windows | Overview and critical text readable; 300-point picker and the complete three-language Follow System label fit |
| Spanish minimum overview | Hero text wraps; warnings and language controls readable. Native toolbar abbreviates the long app name while full name remains in the body and AX title |
| Spanish Dock two-parameter editor | Current 35/37 values remain separate from drafts; long load-current and Apply labels readable; vertical scrolling exposes the full editor in the minimum window |
| Invalid `48.5` | Correct 1-point error shown, last valid 48/64 drafts preserved, Apply disabled; valid `49` clears error and reenables Apply |
| Focused es → en → zh-Hans → es cycle | Raw invalid text, keyboard focus, draft values, expanded editor and disabled Apply remain; cached error text changes language. Exact/panel/Apply AX identifiers are unique |
| Spanish search `ocultación automática` | Two expected matches |
| Technical search `autohide-time-modifier` | One match, no duplicated result |
| Expand/collapse of long-title animation item | Correct expanded/collapsed states |
| Quit/relaunch | Spanish selection, valid numeric drafts and editing mode retained |

No main feature toggle, Apply, Restore, Undo or administrator operation was executed. This directed check does not cover real privileged writes, managed profiles, physical gestures, Dock animation effects, or macOS 14 device behavior. Detailed AX traces and tool-produced screenshots are local ignored QA evidence, not product screenshots.

## Translation and production-state review

Critical decision-making wording was compared against the source English/Chinese and execution semantics: draft/apply, explicit deletion, pre-app restoration, undo, discarding records, managed restrictions, timeout/journal retention, advanced 0 writes and experimental effect limits. These distinctions were retained. This was a Codex semantic review; **no human native-speaker review has been performed**. Native-speaker polish remains recommended before a new Spanish preview release.

The before/after audit matched all 46 catalog/context addresses, power profiles, production app state, production Undo/WAL files, environment and residue inventory. QA state was cleaned. Raw production snapshots remain local and ignored by Git.

The [structured acceptance record](spanish-localization-2026-10-09.json) includes the candidate hash, cases and local capture hashes. The existing preview tag and three public assets remain the original bilingual release; this report does not authorize or announce replacement of those assets.
