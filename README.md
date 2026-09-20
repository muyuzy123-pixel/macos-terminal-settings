# Terminal Settings

[简体中文](README.zh-CN.md)

A native macOS SwiftUI app for inspecting and changing a curated set of persistent preferences that normally require Terminal commands. Each setting explains its effect, risk, source, equivalent command, and recovery behavior.

**Development baseline: 1.9.0 (Build 17).** Licensed under the [MIT License](LICENSE). The source is maintained in the private repository [muyuzy123-pixel/macos-terminal-settings](https://github.com/muyuzy123-pixel/macos-terminal-settings). Repository access remains private; no public release is announced.

## Features

- 40 settings across Dock, Finder, screenshots, trackpad, keyboard, windows, system/development, and advanced power settings.
- 7 numeric control groups with 10 parameters, including Dock sizes and screen saver idle time.
- English and Simplified Chinese, immediate in-app language switching, and bilingual search.
- Separate current values and editable drafts. Numeric edits, presets, and loading current values stay in the draft until Apply. Main setting toggles are actions and can write immediately.
- Managed-preference checks, typed snapshots, conflict-aware undo, and recovery journals written before changes begin.
- Explicit distinctions between deleting an override, restoring a value from before the app took control, and undoing the last change.

The catalog currently classifies 34 settings as Terminal-only, 4 as System Settings enhancements, and 2 as mirrors. These are versioned catalog judgments, not a promise about all macOS versions. Many keys are undocumented and may stop working after a system update. A successful read-back verifies the stored value, not the visible behavior.

## Requirements and build

- Apple silicon Mac (arm64). Intel binaries are not supplied.
- Deployment target: macOS 14 or later. The inherited local acceptance environment was macOS 26.6.2; runtime behavior on macOS 14 has not been accepted on a real device.
- Xcode or Apple Command Line Tools providing a **macOS 26.x SDK**. Swift is compiled in Swift 5 language mode.
- No package manager or third-party runtime dependencies.

```sh
zsh verify.sh --contract-only
zsh build.sh
zsh scripts/check-release.sh
```

Build outputs are `TerminalSettings.app` and `TerminalSettings.zip`. The release check independently extracts the ZIP and verifies its contents; `dist/` holds the resulting release evidence. Paths containing spaces are supported. Set `DEVELOPER_DIR` and/or `SDKROOT` to select a toolchain explicitly; otherwise the scripts prefer installed Command Line Tools.

The build uses **ad-hoc signing with Hardened Runtime**. It does not use a Developer ID certificate or Apple notarization. macOS may block a downloaded build. No claim of Gatekeeper approval is made; do not disable system security settings to run it.

## Permissions and data

Ordinary settings use the current user's preference domains, including current-host domains where specified. Advanced actions request macOS administrator authorization and allow only three `pmset` Boolean keys: `ttyskeepawake`, `proximitywake`, and `acwake`.

The app does not request Accessibility, Screen Recording, Automation, Full Disk Access, or Input Monitoring. Its source contains no telemetry, update service, or network client. Opening a reference link uses the system browser. Drafts, language choice, and per-setting recovery baselines are stored in the app's preferences; the last-undo file and pending transaction journal are stored locally under its Application Support directory. The bundle identifier remains `com.codex.TerminalSettings` to preserve existing local records.

The advanced authorization bridge still calls Apple's deprecated `AuthorizationExecuteWithPrivileges`. It is retained from the development baseline; a modern signed helper is future work. See [security boundaries](SECURITY.md) before using or changing it.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md), [testing](docs/TESTING.md), and [release procedure](docs/RELEASING.md). Historical raw QA data, machine-state snapshots, old application bundles, and one-time localization migration scripts are deliberately excluded from this repository.

[Baseline hashes](docs/upstream-baseline.json) identify the imported development files before repository packaging changes. [Reference attribution](docs/ATTRIBUTION.md) documents the catalog's external sources.
