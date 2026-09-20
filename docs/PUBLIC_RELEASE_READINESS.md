# Public release readiness

Prepared on 2026-09-20. The repository is still **private**. README revisions and source/asset checks are complete; the original repository should not be made public yet because GitHub still returns the former author email when queried by an old commit ID.

## README and behavior review

The English and Chinese README files now distinguish draft editing from every submission path, limit immediate-action menus to controls that choose system values, explain default-branch versus preview-tag builds, and state the actual validation scope. They also clarify override deletion, failed checksum/build handling, and uninstall behavior. These descriptions were checked against the current source. Runtime code, preferences, permissions, and release assets were not changed.

A new product screenshot is optional. None has been fabricated or copied from machine-state QA records.

## Content prepared for publication

- MIT-licensed source, bilingual resources, tests, reproducible-from-source icon generation, build/release scripts, and project documentation.
- The existing `v1.9.0-preview.1` prerelease and exactly three verified assets: `TerminalSettings.zip`, `SHA256SUMS`, and `release-manifest.json`.
- ZIP SHA-256: `9c1e3f429ccc4012c1c52854edb5c5706c7c4f7f9819f65809c9d9b549986c52`.
- Preview source commit after email sanitization: `e1456633dbffc392b3ebb2608f7dea3ee8e41039`. Its file tree is identical to the original release source tree. The downloaded assets remain byte-identical to the locally verified files.
- Prepared [public release notes](publication/release-notes.md) and [private vulnerability-reporting text](publication/security-reporting.md).

The audit covered every object in the original local Git history (48 blobs, 16 trees, 2 commits), all original refs, and all 37 originally tracked files. It also covered release metadata/assets, both original Actions runs and their logs/artifacts, and repository issue/PR/wiki/Pages exposure. No personal filesystem paths, preference exports, recovery records, common token/private-key patterns, or unintended build artifacts were found in the content being prepared. GitHub runner paths are present in CI logs. This is a scoped inspection, not a proof against every possible secret.

Issues and pull requests were empty. Wiki, Discussions, and Pages were not enabled. Raw local QA data, original-history backups, and audit evidence remain in ignored local directories and are not publication assets.

## Author-email privacy

The maintainer chose GitHub noreply email sanitization. Both existing commits were rewritten for author and committer email, with every file tree preserved. Main and the preview tag were updated using exact force-with-lease conditions. This repository's local Git email is now the GitHub noreply address; global Git configuration was not changed.

The two original Actions runs separately stored the former email in their metadata. Their metadata/logs were backed up locally, then the runs and their associated artifacts were removed. Release provenance was updated to the sanitized source commit. New CI runs use the sanitized history.

**Residual found:** authenticated GitHub Git-data API requests using the two old commit IDs still return those old commit objects and their former email. Rewriting visible refs does not prove that server-side historical objects have been removed. A direct public-visibility switch on this original repository therefore does not meet the chosen privacy objective.

## Prepared migration and public-access steps

The proposed next operation, subject to maintainer confirmation, is:

1. Rename the current repository to `macos-terminal-settings-private-archive` and keep it private. Preserve its release, original-object remnants, and audit context there.
2. Create a new **private**, independent repository at `muyuzy123-pixel/macos-terminal-settings`. Push only a clean Git object set containing the sanitized reachable history, and recreate the same prerelease from the verified assets. Do not fork the archive or transfer its object database.
3. Confirm that the new repository cannot resolve the old commit IDs, that all reachable author/committer emails use noreply, that release asset hashes match, and that fresh CI passes. Verify default branch, MIT recognition, and release/tag provenance.
4. After the maintainer explicitly confirms public access, switch only the new clean repository to public. The archive remains private. A public repository makes its reachable history, release assets, and Actions history/logs available; see [GitHub's visibility documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).
5. Enable and verify [private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository), apply the prepared security text, and update the live release notes/status. Check anonymous access to the README, license, tag, and assets.

The migration has not yet been executed. Public access has not been enabled. Ad-hoc signing, lack of notarization, legacy privileged execution, and device-validation limits remain accurately disclosed; public visibility does not change those limits.
