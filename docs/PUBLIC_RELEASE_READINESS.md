# Public release readiness

The clean repository migration completed on 2026-09-20. **Both repositories remain private.** The new repository is ready for a separate decision about public access; the original repository is retained as a private archive.

## Repository migration

| Role | Repository | GitHub repository ID | Visibility |
| --- | --- | ---: | --- |
| Active, clean repository | [macos-terminal-settings](https://github.com/muyuzy123-pixel/macos-terminal-settings) | 1377772976 | Private |
| Original archive | [macos-terminal-settings-private-archive](https://github.com/muyuzy123-pixel/macos-terminal-settings-private-archive) | 1377740283 | Private |

The active repository was created independently, not as a fork. Only the audited clean `main` history and `v1.9.0-preview.1` tag were pushed into it. Local development still uses the original repository URL, which now resolves to the new repository. No application code, preference behavior, permissions, or release asset bytes changed during migration.

## Author-email isolation

The maintainer chose GitHub noreply addresses for author and committer metadata. Both original commits were rewritten with their file trees unchanged. The initial clean history contained three commits and 65 objects (47 blobs, 15 trees, 3 commits), all reachable, with no alternate object database. An exact scan of every clean object found no occurrence of the former email. This repository's local Git identity uses noreply; global Git configuration was not changed.

Rewriting refs in the original repository had left old commit objects retrievable from GitHub. That repository was therefore renamed and kept private. After migration, authenticated checks against the **new** repository could not resolve either historical commit: Git-data requests returned 404, and ordinary commit requests returned 422 with a no-commit-found response and no author/committer payload. Valid clean commits remained readable and their identities and file trees matched the local audit.

The original archive and ignored local backups still retain historical data. This is isolation from the active repository, not a claim that all historical copies were erased. The former Actions runs that directly stored the old email were backed up locally and removed before migration. Only fresh CI records belong to the new repository.

## README and source review

The English and Chinese README files share a real English screenshot of the Dock size editor from an isolated preview copy. The screenshot shows current values 35/37 and unapplied numeric drafts 48/64; no setting was applied. Before/after production-state checks were unchanged, and the temporary app and its isolated state were removed. Both READMEs distinguish draft editing from every submission path, limit immediate-action menus to controls that choose system values, and explain default-branch versus preview-tag builds. They clarify actual validation scope, override deletion, failed checksum/build handling, and uninstall behavior. These descriptions were checked against the source; GitHub Markdown rendering and local links passed review.

The content audit covered the original Git history, all refs and tracked files, release metadata/assets, Actions logs/artifacts, and issue/PR/wiki/Pages exposure. No personal filesystem paths, preference exports, recovery records, common token/private-key patterns, or unintended build artifacts were found in the source/asset content selected for migration. GitHub runner paths occur in CI logs. This is a scoped inspection, not a proof against every possible secret. Raw QA, backups, and audit evidence stay in ignored local directories.

## Release and verification

The [v1.9.0-preview.1 prerelease](https://github.com/muyuzy123-pixel/macos-terminal-settings/releases/tag/v1.9.0-preview.1) was recreated in the new repository. The source tag still points to `e1456633dbffc392b3ebb2608f7dea3ee8e41039`; its files are unchanged by email sanitization or migration. The three assets are exactly `TerminalSettings.zip`, `SHA256SUMS`, and `release-manifest.json`.

All three new assets were downloaded independently and matched the old release and local migration baseline byte-for-byte. Server digests, the checksum file, strict code signing, ZIP inventory, all packaged resources, and the embedded MIT notice were verified. New release and asset IDs differ from the archive's IDs.

- ZIP SHA-256: `9c1e3f429ccc4012c1c52854edb5c5706c7c4f7f9819f65809c9d9b549986c52`.
- Fresh [GitHub Actions verification](https://github.com/muyuzy123-pixel/macos-terminal-settings/actions/runs/35481438157) passed for migrated commit `c95b4971d60c663b3c253ee0b24d6a1ec3fd4147`, covering contracts, build, independent archive checks, and artifact upload.
- The subsequent migration-status update changes documentation only; it does not change the tested application or build inputs.

## Remaining public-access steps

Public access has **not** been enabled. When the maintainer authorizes it:

1. Change only `muyuzy123-pixel/macos-terminal-settings` to public. Keep `macos-terminal-settings-private-archive` private. Public visibility exposes the active repository's history, releases, and Actions history/logs; see [GitHub's visibility documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).
2. Enable and verify [private vulnerability reporting](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository), apply the prepared [security-reporting text](publication/security-reporting.md), and publish the prepared [release notes](publication/release-notes.md).
3. Check anonymous access to the active README, MIT license, preview tag, and all three assets, and confirm that the archive remains inaccessible anonymously. Update the distribution status after those checks.

Keep the preview label and the existing disclosures: ad-hoc signing without Developer ID or notarization, legacy privileged execution, and the stated device-validation limits. Changing repository visibility does not change those technical limits.
