# Security and privacy boundaries

This policy describes [v1.10.0-preview.1](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.10.0-preview.1), App **1.10.0 (Build 19)**. See the [frozen source e8f62725eb61d4e1cd1c9779a3dfb7ec4cf2a414](https://github.com/muyuzy123-pixel/macos-terminal-settings/commit/e8f62725eb61d4e1cd1c9779a3dfb7ec4cf2a414), [source CI](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/38256266681), and [release verification](https://github.com/muyuzy123-pixel/macos-terminal-settings/blob/main/docs/publication/v1.10.0-preview.1-verification.json) for the checked artifact and its validation scope.

This application changes macOS preferences for the current user. It never requests administrator authorization: for three power settings it only reads their state and shows fixed `sudo pmset` commands for you to run in Terminal. Review the displayed effect and recovery behavior before applying a change.

## Current design

Ordinary commands use fixed executables and argument arrays. Power settings are read with an unprivileged `pmset -g custom`; the app offers commands only for the Boolean keys `ttyskeepawake`, `proximitywake`, and `acwake`. The catalog constrains recovery records as well as new writes. Managed or unreadable preferences remain read-only; conflicting external changes prevent destructive recovery.

A write-ahead journal records the intended transaction before writes begin. An unreadable or incomplete journal locks further writes until reviewed or recovered. This reduces recovery risk; it does not make undocumented settings stable or replace a system backup.

## Known limitations

- The older 1.9.0 (Build 18) preview writes power settings through the deprecated `AuthorizationExecuteWithPrivileges` API. Version 1.10.0 (Build 19) removes that bridge and links no authorization API. Bringing in-app power changes back needs a signed launchd helper (Service Management), which in turn needs Developer ID signing. Legacy power records are never replayed.
- A completed power Undo record does not itself lock ordinary preference writes. The app shows manual restore commands; **Keep Current State and Remove Record** can also discard that completed record directly, without requiring current values to match its recorded after-state.
- An unfinished power WAL keeps ordinary writes locked. Removal requires a read matching the recorded before-state, or an explicit **Keep Current State and Remove Record** request followed by a fresh read matching the recorded after-state. Partial or conflicting states, read failures, and failed WAL removal retain the journal and its write lock. The app does not write power settings through either path.
- Builds are ad-hoc signed, without Developer ID or notarization. A strict code signature check is not a Gatekeeper or notarization result.
- The app is not App Sandbox-contained. Writes run as the current user; power settings change only when you run the shown commands yourself.
- Hidden keys and legacy gestures may be ignored on newer systems. Write/read-back checks do not validate physical effects.
- Real managed profiles require separate acceptance; simulated tests do not prove that device behavior.
- Real mouse-hover timing, VoiceOver behavior, and macOS 14 runtime acceptance remain unverified. Spanish translations have not yet been reviewed by a native speaker.

## Earlier preview: v1.9.0-preview.2 (Build 18) — historical

The older [download](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.9.0-preview.2) still uses `AuthorizationExecuteWithPrivileges` for its three allowlisted power settings and can show the macOS administrator-authorization dialog. Its legacy helper does not expose a child PID; a timeout cannot prove that the helper exited, so an unknown outcome retains the recovery journal and locks writes. These release assets are unchanged. See the [published security policy](https://github.com/muyuzy123-pixel/macos-terminal-settings/blob/v1.9.0-preview.2/SECURITY.md) for that version's complete boundaries.

## Data and reports

No telemetry, analytics, automatic update service, or network client is present in the reviewed source. External documentation links open in the system browser. Drafts, language choice, undo data, recovery journals, and pending restart metadata remain local. Logs and screenshots may expose preference values or file paths: redact them before sharing.

Report suspected vulnerabilities through [Security → Report a vulnerability](https://github.com/muyuzy123-pixel/macos-terminal-settings/security/advisories/new), which sends a private report to the repository maintainer. Do not disclose exploit details, credentials, private preference exports, or undo/recovery records in public issues. For ordinary non-sensitive bugs, use the [bug report template](https://github.com/muyuzy123-pixel/macos-terminal-settings/issues/new?template=bug_report.md) and include the app/macOS versions plus a minimal, redacted reproduction. If the private-report entry is unavailable, request a private reporting channel without posting vulnerability details.
