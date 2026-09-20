# Testing and evidence

## Automated checks

`zsh verify.sh --contract-only` type-checks the complete app and runs contract checks with recording and fail-closed substitutes. It covers the catalog, numeric constraints, localization, region formatting, old recovery schemas, transaction ordering, conflict handling, journal failure, and non-Apply behavior. It does not call live `defaults` or `pmset`; temporary recovery files are still used by filesystem tests.

`zsh verify.sh` additionally uses randomly named test preference domains, including current-host domains, and reads `pmset -g custom`. It does not apply catalog keys or request privileged writes. It is an integration test on the local machine, not a pure in-memory test. Run it intentionally and inspect failures before rerunning.

`zsh scripts/check-release.sh` independently extracts the ZIP, checks its exact file inventory, verifies strict signing, compares resources, and records version, architecture, deployment target, and hashes. It does not launch the app or change preferences.

## UI and device acceptance

For changes to views, verify both languages, minimum window size, search, focus, drafts, expanded controls, invalid input, and Accessibility identifier uniqueness. Use a QA copy with a distinct bundle identifier so existing drafts and Undo/WAL are not shared. Main feature toggles, Apply, Restore, Undo, and advanced switches are real mutation paths.

Treat visual effects, managed-profile behavior, physical gestures, actual privileged writes, and old-system compatibility as separate device checks. Do not substitute compilation, a successful database read-back, or automated click timing for those checks.

## Evidence carried forward

The original development task reported Build 17 contract/integration, isolated GUI, and independent archive checks on macOS 26.6.2. Those are historical reports, not new acceptance of this repository's rebuilt artifact. Raw historical QA snapshots were excluded because they contain machine-specific data. The import manifest preserves the source hashes used as this repository's baseline.

Current repository check results are recorded in [release status](RELEASE_STATUS.md). GitHub Actions results are only claimed after an actual remote run succeeds. CI runs contract checks and build/archive verification; it does not run the hardware-dependent live power-settings integration check on a virtual machine. The workflow uses the [GitHub-hosted macos-26 arm64 runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), pins its actions to commit hashes, and has read-only repository permissions. It does not upload secrets or publish a GitHub Release.
