# Contributing

Start with a small, reviewable change and describe the user-visible behavior. For a new preference, provide evidence for its domain, key, scalar type, scope, supported versions, effect, and recovery strategy. A community example alone is not proof of current behavior.

## Invariants

- Draft edits, presets, expansion, language changes, and loading current values must not write system preferences, restart processes, or request authorization.
- Preserve absent values and scalar types. Do not turn a missing value into a guessed default.
- Managed or unreadable state must fail closed. Recheck state and conflicts immediately before writing.
- Record recovery data before the first write. Never discard an unreadable journal or overwrite an external third value during undo.
- Keep executable paths, arguments, preference addresses, and privileged keys constrained by the catalog. Commands run as argument arrays; displayed shell snippets are not an execution interface.
- Preserve Undo/WAL compatibility, stable feature IDs, and untranslated raw diagnostics. Add matching English and Chinese resources for UI changes.
- Changing permissions, privileged execution, data schemas, deployment targets, or recovery semantics requires an explicit design review.

## Build and checks

Run `zsh verify.sh --contract-only`, `zsh build.sh`, then `zsh scripts/check-release.sh`. Use `zsh verify.sh` for isolated integration checks described in [TESTING.md](docs/TESTING.md). Run only the checks relevant to a change; document untested behavior.

Do not test real Dock, Finder, screen saver, or privileged changes on a contributor's machine without an intentional test plan. UI acceptance should use an isolated bundle identifier and application-state directory. Do not post raw recovery records or complete preference exports.

Keep generated bundles, archives, logs, machine snapshots, credentials, and signing keys out of Git. Do not reintroduce the one-time localization migration scripts. `Source/GenerateIcon.swift` is a development utility and is excluded from the app compiler input. Run `zsh scripts/generate-icon.sh` to rebuild the checked-in icon from that source; a successful script run verifies all ten image sizes before replacing it.
