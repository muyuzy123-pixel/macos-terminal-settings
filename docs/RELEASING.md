# Release procedure

1. The license is MIT (copyright 2026 muyuzy123-pixel). Public-release preparation for `muyuzy123-pixel/macos-terminal-settings` is recorded in [PUBLIC_RELEASE_READINESS.md](PUBLIC_RELEASE_READINESS.md). Keep the repository private until the maintainer confirms the visibility change after reviewing the exposed content.
2. Review the exact Git file list. Exclude QA snapshots, previous artifacts, migration scripts, machine paths, secrets, and signing keys. Resolve third-party code or artwork license questions before publication.
3. Keep source and `Info.plist` aligned. The first public source snapshot inherits 1.9.0 / Build 17; packaging changes alone do not imply new app behavior. Application changes require an intentional version decision.
4. Run `zsh verify.sh --contract-only`, the appropriate integration/UI checks, `zsh build.sh`, and `zsh scripts/check-release.sh` on the final tree. Do not publish older ZIPs alongside newer source hashes.
5. Review `dist/` evidence and the exact release asset names. Describe the build as arm64, macOS 14 minimum deployment, ad-hoc signed, and unnotarized. State actual tested macOS versions and any untested behavior.
6. Push the reviewed source to the chosen repository and inspect the real CI result. Create an explicit tag and preview release only after its source commit and checks are final. Upload the checked ZIP and its SHA-256 evidence; do not attach raw local logs.
7. Download or inspect the published assets and confirm their hashes and release wording. Record the final repository, tag, release URL, commit, and checks.

The CI workflow validates source and packaging and does not publish releases. Developer ID signing, notarization, and a modern signed privileged helper are separate future work. Never commit certificates or change the user's local signing or Xcode license settings automatically.

Before the visibility change, review the complete reachable history and GitHub Actions records, not only the working tree. After switching to public, enable and verify [private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository), apply the prepared reporting text in [publication/security-reporting.md](publication/security-reporting.md), and publish the prepared [release notes](publication/release-notes.md). Verify anonymous access to the README, MIT license, release page, and assets. Keep the existing preview label and signing limitations.
