# Sources and attribution

The setting descriptions in `Source/Catalog.swift` link to their evidence, including Apple support/developer documentation, macos-defaults, dotfiles examples, and project-specific references. A link identifies a source of information; it does not imply endorsement or a bundled dependency.

This source snapshot uses Apple system frameworks (SwiftUI, AppKit, Foundation, Security and related system APIs). It has no vendored dependency tree or package-manager lockfile. No upstream repository is bundled. The local source review cannot establish ownership of every line solely from file contents; new imported code or artwork must have its provenance and license reviewed.

`Source/GenerateIcon.swift` contains an AppKit drawing utility for the terminal-style icon. `scripts/generate-icon.sh` rebuilds `AppIcon.icns` directly from this drawing source, including 16/32/128/256/512-point representations at 1x and 2x. The repository icon was regenerated during public-source preparation; it is no longer the development baseline's low-resolution icon. No third-party icon package or embedded font is included in this snapshot.

This repository is licensed under the [MIT License](../LICENSE), copyright 2026 muyuzy123-pixel. The same license notice is bundled with the app. External linked materials retain their respective owners' terms.
