# Security audit — 20 October 2026

Scope: tracked repository content, Git history, configuration import/export, local persistence, HID input handling, application bundle, installer, dependencies, and runtime network activity on the audit Mac. This is a source and local binary audit, not a professional penetration test or a claim about untested physical device behavior.

## Resolved in 1.1.5

- Removed the source-derived configuration sample, its duplicate bundled resource, and two private analysis/build documents. The first-run configuration now contains only generic defaults. Existing user settings in Application Support are not changed.
- Corrected packaging to clean SwiftPM's products directory and copy only the current app resource bundle. A previous incremental package still contained a deleted resource; the rebuilt 1.1.5 package does not.
- Removed raw HID packet tracing and changed variable runtime log content to private OSLog fields. Diagnostic CLI output no longer prints device or paired-host names.
- Settings, recovery copies, and exported JSON are written with mode `0600`; the settings directory is mode `0700`. JSON imports now inspect the opened file descriptor and reject symlinks, pipes, nonregular files, and files over 1 MiB.
- Options+ database imports are read-only, reject symlinks and nonregular files, have a 64 MiB file limit and 16 MiB SQLite value limit, and disable trusted schema processing.
- Added a repeatable tracked-file/credential-pattern check in `scripts/security-check.sh`.
- ZIP and DMG staging now avoids copying Finder resource forks. The macOS package tool still lists AppleDouble metadata entries for local provenance, but they expand as extended attributes rather than extra files; scanned entries contained none of the removed reference markers, user paths, or email addresses.

## Audit findings and limits

- No private keys, API tokens, raw Options+ database, or external Swift package dependencies were found in the tracked tree or Git object scan. The removed source-derived sample contained personal configuration details, so it is treated as sensitive even though it had no credentials.
- The app requires Input Monitoring and Accessibility to perform its core functions. An app with these grants can observe input and synthesize events; keep the installed binary and updates under the user's control. Standard typing and primary clicks are outside the app's intended mapping scope.
- Configuration exports can contain user-created profile names, application bundle IDs, and shortcuts. They are private files and should only be shared intentionally.
- The locally built app uses an ad-hoc signature; the `.pkg` has no Developer ID signature or notarization. This protects local code integrity checks but does not establish publisher identity for distribution. Release signing/notarization requires the owner's Apple Developer credentials.
- `pkgbuild` emits four `write: Permission denied` warnings while copying macOS provenance metadata on this Mac. The package exits successfully, expands, and contains a code-signature-valid app; the warning remains unresolved and should be checked on the intended release machine before distribution.
- Device product images derive from Logitech product imagery. Distribution rights require separate review; this audit does not establish a license.
- Old Git commits or third-party mirrors may remain available after a branch history replacement. The owner should treat any previously published personal settings as disclosed. No credential rotation was indicated by this scan because none were found.
- The scanner searches common credential formats and private filenames; it cannot prove the absence of all secrets, dependency vulnerabilities in Apple frameworks, or vulnerabilities reachable only with physical devices.

Verification: `swift test`, `scripts/security-check.sh`, `codesign --verify --strict`, bundle and archive-content inspection, DMG verification, PKG expansion, installed-binary hash comparison, launch smoke, and a local process socket check. The installed 1.1.5 app had no active network sockets in the sampled process check. See `docs/TEST_RESULTS.md` for the test suite.
