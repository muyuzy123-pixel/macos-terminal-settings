First MIT-licensed preview of Terminal Settings, based on version 1.9.0 (Build 17).

- Native macOS interface, English and Simplified Chinese, 40 curated settings, and 7 numeric control groups.
- Source, build scripts, tests, and MIT license are included in the repository. The app bundle includes the same license notice.
- The attached ZIP is an Apple silicon (arm64) build with a macOS 14.0 deployment target, locally validated on macOS 26.6.2. Real macOS 14 runtime acceptance is not claimed.
- The build uses Hardened Runtime and ad-hoc signing. It has no Developer ID signature or Apple notarization, and no Gatekeeper acceptance is claimed.
- Advanced power settings retain the legacy authorization API; a modern signed helper and real privileged-write acceptance remain future work.

Local contract and isolated integration checks passed. The attached archive was independently checked for exact files and resources, version, architecture, deployment target, signature, and license. See `SHA256SUMS` and `release-manifest.json`; do not substitute these checks for device-effect or GUI acceptance.

This is a prerelease for evaluation. The source is available under the MIT License.

Source commit: `e1456633dbffc392b3ebb2608f7dea3ee8e41039`. Current repository checks are available in [GitHub Actions](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions).
