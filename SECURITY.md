# Security and privacy boundaries

This application changes macOS preferences and can request administrator authorization for three power settings. Review the displayed effect and recovery behavior before applying a change.

## Current design

Ordinary commands use fixed executables and argument arrays. Advanced writes permit only Boolean values for `ttyskeepawake`, `proximitywake`, and `acwake`, across power sources present at the start of an operation. The catalog constrains recovery records as well as new writes. Managed or unreadable preferences remain read-only; conflicting external changes prevent destructive recovery.

A write-ahead journal records the intended transaction before writes begin. An unreadable or incomplete journal locks further writes until reviewed or recovered. This reduces recovery risk; it does not make undocumented settings stable or replace a system backup.

## Known limitations

- The inherited C bridge calls deprecated `AuthorizationExecuteWithPrivileges`. Apple directs developers toward a launchd helper / Service Management approach. Migration to a signed modern helper has not been implemented or validated. The legacy API does not expose a child PID; a communication timeout cannot prove that the privileged process has exited. The app retains its recovery journal and locks writes when the outcome is unknown. [Apple API documentation](https://developer.apple.com/documentation/security/authorizationexecutewithprivileges)
- Builds are ad-hoc signed, without Developer ID or notarization. A strict code signature check is not a Gatekeeper or notarization result.
- The app is not App Sandbox-contained. Ordinary writes run as the current user; advanced writes use the macOS authorization dialog.
- Hidden keys and legacy gestures may be ignored on newer systems. Write/read-back checks do not validate physical effects.
- Real managed profiles and privileged power writes require separate acceptance; simulated tests do not prove those device behaviors.

## Data and reports

No telemetry, analytics, automatic update service, or network client is present in the reviewed source. External documentation links open in the system browser. Drafts, language choice, undo data, and recovery journals remain local. Logs and screenshots may expose preference values or file paths: redact them before sharing.

Report suspected vulnerabilities through [Security → Report a vulnerability](https://github.com/muyuzy123-pixel/macos-terminal-settings/security/advisories/new), which sends a private report to the repository maintainer. Do not disclose exploit details, credentials, private preference exports, or undo/recovery records in public issues. For ordinary non-sensitive bugs, use the [bug report template](https://github.com/muyuzy123-pixel/macos-terminal-settings/issues/new?template=bug_report.md) and include the app/macOS versions plus a minimal, redacted reproduction. If the private-report entry is unavailable, request a private reporting channel without posting vulnerability details.
