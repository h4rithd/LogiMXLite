# Privacy and security

No networking code, remote services, telemetry, analytics, ads, accounts, AI runtime,
auto-updater or cloud synchronization. Normal operation uses local AppKit, SwiftUI,
IOKit/IOHID, ApplicationServices, CoreAudio, Carbon secure-input status and
ServiceManagement. Build-time research fetched two public source repositories into
system temporary storage; they are not runtime dependencies or bundled sources.

No administrator rights, private APIs, kernel extensions or system extensions are
used. The Options+ database is read only when the user invokes its import preview;
it is opened read-only and never copied into this repository. `.gitignore` excludes database files,
build products and local artifacts. The app bundles neutral first-run defaults,
not the owner's source configuration. Settings contain no pairing keys, account IDs,
serials, credentials, tokens or private absolute paths. App associations are bundle
IDs resolved from selected application bundles; paths are not retained.
User-defined profile names, assignments and application bundle IDs can still
reveal personal preferences, so exported settings should be treated as private.

Diagnostics are an in-memory bounded 100-message history; dynamic OSLog messages
are private, and raw HID packet tracing is disabled. The explicit diagnostic
export includes permission booleans, model names, transport errors and feature
indices/versions. It excludes raw packets, unique identifiers, app history and paths.
The command-line device probe reports paired host slot availability without
printing host names.
Firmware reads discard unique unit fields and never request a serial number. Source
observations are length-bounded nonexecuting text. Unknown import extensions are
stripped; action enums cannot carry arbitrary commands or URLs.

HID writes are routed only to two exact BLE identities after vendor usage-pair checks.
Feature reads and live control enumeration precede writes. No firmware, DFU,
receiver, persistent key-diversion or hardware scroll-diversion command is issued.
Prior temporary button flags are retained and restored on clean stop where reachable.
A crash or a lost device may prevent restoration; a power cycle is the documented
recovery. Hardware verification is still required before claiming parity.

The app asks for Input Monitoring for IOHID access and Accessibility for native action
posting/AX window zoom. It does not scan with CoreBluetooth, so does not request
Bluetooth access. It does not capture screenshots itself: the screenshot action
launches the system `screencapture -i` tool when invoked. CoreAudio mute uses a hardware mute
property if settable; it does not record audio or request microphone capture access.

The application is ad-hoc signed locally. It is not notarized and carries no special
entitlements. Stable Developer ID signing and distribution notarization are separate
release requirements. Rebuilding ad-hoc binaries can invalidate macOS permissions.
Never disable macOS protections to work around a denied feature.
