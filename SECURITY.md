# Security and privacy boundaries

This application changes macOS preferences for the current user. It never requests administrator authorization: for three power settings it only reads their state and shows fixed `sudo pmset` commands for you to run in Terminal. Review the displayed effect and recovery behavior before applying a change.

## Current design

Ordinary commands use fixed executables and argument arrays. Power settings are read with an unprivileged `pmset -g custom`; the app offers commands only for the Boolean keys `ttyskeepawake`, `proximitywake`, and `acwake`. The catalog constrains recovery records as well as new writes. Managed or unreadable preferences remain read-only; conflicting external changes prevent destructive recovery.

A write-ahead journal records the intended transaction before writes begin. An unreadable or incomplete journal locks further writes until reviewed or recovered. This reduces recovery risk; it does not make undocumented settings stable or replace a system backup.

## Known limitations

- Earlier builds wrote power settings through the deprecated `AuthorizationExecuteWithPrivileges` API. This build removes that bridge and links no authorization API. Bringing in-app power changes back needs a signed launchd helper (Service Management), which in turn needs Developer ID signing. A power undo record or unfinished power journal left by an earlier build is not replayed: the app shows the restore commands and removes the record only after a check finds the earlier state, or, on request, a fully applied change.
- Builds are ad-hoc signed, without Developer ID or notarization. A strict code signature check is not a Gatekeeper or notarization result.
- The app is not App Sandbox-contained. Writes run as the current user; power settings change only when you run the shown commands yourself.
- Hidden keys and legacy gestures may be ignored on newer systems. Write/read-back checks do not validate physical effects.
- Real managed profiles require separate acceptance; simulated tests do not prove that device behavior.

## Data and reports

No telemetry, analytics, automatic update service, or network client is present in the reviewed source. External documentation links open in the system browser. Drafts, language choice, undo data, and recovery journals remain local. Logs and screenshots may expose preference values or file paths: redact them before sharing.

Report suspected vulnerabilities through [Security → Report a vulnerability](https://github.com/muyuzy123-pixel/macos-terminal-settings/security/advisories/new), which sends a private report to the repository maintainer. Do not disclose exploit details, credentials, private preference exports, or undo/recovery records in public issues. For ordinary non-sensitive bugs, use the [bug report template](https://github.com/muyuzy123-pixel/macos-terminal-settings/issues/new?template=bug_report.md) and include the app/macOS versions plus a minimal, redacted reproduction. If the private-report entry is unavailable, request a private reporting channel without posting vulnerability details.
