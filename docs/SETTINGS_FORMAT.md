# Native settings format, version 1

Location: `~/Library/Application Support/LogiMXLite/settings.json`.
A single `backup.json` is retained beside it. Directory mode 0700 and file mode 0600
are requested. Atomic replacement prevents partially written JSON. No raw Options+
database is used at runtime. First-run defaults are generated in code; existing
local settings are not replaced by those defaults.

Root fields:

| Field | Meaning |
|---|---|
| schemaVersion | Exactly 1; other versions explicitly rejected |
| profiles | 1–64 profiles; exactly one default; unique UUIDs and app associations |
| dpiPresets | Up to 32 named UUID/value records; order is cycling order |
| switchHardwareWithApps | False uses Desktop hardware preferences; true permits app overrides |
| theme | system, light or dark |

Each profile contains `id`, `name`, `isDefault`, optional verified `bundleID`, `mouse`,
`keyboard`, `gestures`, optional `dpiPreset`, `scroll`, `keyboardSettings`, `wheelMode`,
`smartShiftThreshold`, and read-only `observations`. The Desktop bundle ID must be null.
Absent app mapping keys inherit Desktop. `none` is an explicit no-op and does not
inherit. Keyboard hardware fields inherit individually. Scroll preferences inherit as
one optional record. Dangling preset references are rejected.

Mouse source slots are c82, c83, c86, c195, c196 and thumbWheel. Keyboard slots are
c212, c226, c227, c231, c232, c233, c259, c264, c266, c280–c285 and c321. Gesture keys
are click/up/down/left/right. These keys do not establish runtime hardware capabilities.

An action has `kind`, optional `usage`, `modifiers`, `note`, `repeatDelayMS` and
`repeatIntervalMS`. `kind` is a closed Swift enum. `shortcut` requires a supported
USB usage; other kinds cannot carry a key payload. Modifiers are USB usages 224–227
(Control, Shift, Option, Command). Delays are bounded to 250–2000 ms and intervals
25–1000 ms. Source PowerPoint 200 ms timing is conservatively bounded to 250 ms for
unsupported actions; the original payload remains in the reference file. No URL,
command, executable, bookmark, script or home path is an action payload. Downloads
is represented by the `downloads` kind, resolved by FileManager at invocation.

Preset values are syntactically bounded to 50–30000, then validated against the live
sensor's discrete set/range before writes. Imported presets remain unverified while
offline. The live device response, not the schema bound, defines supported values.
There are no prepopulated fake presets. The preset editor starts with the live
device DPI and validates new values against its supported range.

Scroll settings preserve vertical/horizontal scale, direction and smooth preference;
the session event tap applies them to discrete-wheel events while the app runs.
Keyboard settings preserve Fn inversion,
mode, brightness, hands-out duration and effect, subject to live capability checks.
Source normalized pointer observations are provenance, not executable settings.
Source normalized scroll values are converted to bounded scale factors; the exact
Options+ response curve has not been independently established.

Import: regular file, not a symlink, bounded read of at most 1 MiB; strict Codable
types and enum values; semantic count/range/string/association validation. Unknown
optional JSON fields are discarded during decoding and never retained in an export.
Unknown versions are rejected. Future native schema migrations must explicitly map
validated old types; there is no implicit permissive migration today.

Preview decodes and computes a field diff without executing actions. Confirmation
checks the saved baseline, writes a pre-import backup, then atomically replaces the
configuration. Backup failure prevents replacement. Atomic save failure leaves the
existing file intact. The old in-memory configuration is retained until commit returns.
Restoring a backup goes through the same preview and confirmation flow.
