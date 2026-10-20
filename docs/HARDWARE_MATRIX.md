# Hardware and feature matrix

Evidence collected 2026-10-19, Asia/Singapore. Labels: VERIFIED means observed on
this host; MOCK-VERIFIED means software simulation only; BLOCKED/UNTESTED means no
successful physical operation was observed. Product UI never substitutes mock data.

| Requirement | Status | Evidence / limitation |
|---|---|---|
| MX Master 3S BLE identity | VERIFIED, initial registry only | IOHID reported VID 046D, PID B034, name MX Master 3S M, BLE |
| MX Mechanical Mini for Mac BLE identity | VERIFIED, initial registry only | VID 046D, PID B36D, name MX MCHNCL M, BLE |
| Live HID++ endpoint and feature enumeration | VERIFIED 2026-10-19 | `make diagnose` read both feature tables (35 and 34 features) over BLE, device index 0x01 for replies and 0xFF for events. Needs Input Monitoring and the run-loop IOHIDManager pattern |
| Unknown-device exclusion | MOCK-VERIFIED + code audit | Exact model/PID/name/transport and usage-pair gates; no receiver path |
| Device sleep/wake/Bluetooth interruption | PARTIAL | Workspace/IOHID lifecycle implemented; reconnect simulation passes; physical sequence untested |
| Battery / firmware readings | PARTIAL | Battery read live (mouse 45%, keyboard 80% at test time). Firmware strings not shown in the UI yet |
| Hardware DPI / supported steps / readback | PARTIAL | Live read: 1650 DPI, range 200 to 8000, 157 values. Writes are mock-verified only |
| DPI presets and per-app selection | SOFTWARE VERIFIED | Create/edit/delete/reorder UI; schema and inheritance tests; requires live range for validated examples |
| SmartShift / ratchet / free-spin | MOCK-VERIFIED | Separate 2110 and 2111 functions, readback and rollback; physical mode untested |
| Mouse button mapping / gestures | VERIFIED on hardware 2026-10-19 | CIDs 82, 83, 86, 195, 196 diverted; Back/Forward checked in Safari and Finder; all five gestures fire; Smart Zoom and desktop switching confirmed via live window-server state |
| Keyboard special-key mapping | VERIFIED 2026-10-19 | Search, emoji, screenshot, Home/End/Page Up/Down, play/pause through the app; backlight, mute, volume, dictation and DND keys left native (mute/volume/DND observed natively) |
| Fn inversion | MOCK-VERIFIED | Current-host read/write/readback; physical Fn+Esc and host switching untested |
| Backlight brightness/mode/duration/effect | MOCK-VERIFIED | 1982 v3 only, reported capability/effect gates, all four durations preserved; Reaction untested |
| Vertical / thumb scroll scaling, direction and smoothing | VERIFIED in Safari | Session event tap: measured distance matches native x profile speed (0.0221 vs 0.0220 expected); trackpads untouched; native on quit |
| OS pointer speed | PARTIAL | Explicit link to macOS Mouse Settings; no global acceleration writer or conversion from normalized source values |
| Smart Zoom / proprietary app zoom / dictation / Focus | PARTIAL | Smart Zoom implemented and verified; PowerPoint/Word zoom stay native; dictation and Focus keys left to the keyboard |
| Native public-API actions | IMPLEMENTED, physical acceptance untested | AX zoom, Mission Control app launch, Downloads, shortcuts/media/volume/mic mute and middle down/up |
| Profiles / inheritance / app associations | SOFTWARE VERIFIED | First run has one neutral Desktop profile; users can add application profiles or import their own Options+ configuration. Existing local profiles are preserved. |
| Native settings import/export | VERIFIED by tests | Round-trip, stale preview, transactional backup failure, hostile data and path tests |
| Options+ settings.db import | IMPLEMENTED | Read-only immutable SQLite open; preview and backup before apply; mappings, gestures, scroll, SmartShift and bundle IDs |
| One menu icon / Settings / Quit | VERIFIED by launch smoke + UI inspection | One status item created; configuration visible; clean exit status 0 |
| Accessibility/Input Monitoring denied | SOFTWARE VERIFIED | Permission gates and unavailable UI; physical TCC revoke testing still needed |
| Login item | UNTESTED | SMAppService implemented; actual local approval/ad-hoc signing requirements remain |
| Crash restoration | PARTIAL | Temporary diversion only; leftover diversion is released on next launch or with --restore-native |

## Physical acceptance checklist

Run `make diagnose` with both devices awake and no competing HID software. Keep the
app at its installed path when granting permissions. Save the redacted diagnostics.
Do not infer support from a feature ID alone: inspect successful per-feature reads.

1. Confirm both names/PIDs, FF43:0202 endpoint availability, battery, firmware and
   feature table. Confirm reconnect separately for mouse and keyboard after sleep,
   Bluetooth toggle and device power cycle. Unknown hardware must remain untouched.
2. Grant/revoke Input Monitoring and Accessibility separately. Denial must leave
   normal pointing, primary clicks, typing and wheels usable. Retry/relaunch must
   recover without repeated prompts or CPU spin. Test secure password input.
3. Create three presets from the live DPI list. Verify actual movement and readback,
   cycle order, invalid value rejection, app selection, rapid switches and unchanged
   value suppression. Check readback after reconnect. Do not compare normalized
   Logitech numbers to DPI as if they were calibrated.
4. Inspect CIDs/task IDs and enable temporary mappings. Check c82 maximize, c196
   Downloads, c86 next track, and gestures. Choose/confirm a Back shortcut substitute
   before expecting it. Check press/release, middle hold/drag, debounce, timeout,
   cancellation and the physical keyboard layout for slash/quote/brackets.
5. Associate Excel/PowerPoint through their installed bundles. Test Safari, Excel,
   Word, PowerPoint, Resolve and unknown apps; verify Desktop inheritance and no
   actions leaking between apps. Word down gesture must do nothing; up sends Cmd+S.
6. Verify actual wheel free-spin/ratchet/automatic threshold. Native scrolling must
   continue after failed writes, Quit and crash. Check speed, natural direction and
   smoothing separately with a long scroll; compare actual event distances to native.
7. Query keyboard backlight support and current mode before changing it. Test one
   parameter at a time: level, auto/manual/off, duration, then supported Reaction.
   Check Fn inversion and physical native special keys before and after Quit/crash.
8. Test each action against real apps and media consumers. AX zoom is the public
   zoom-button action, not full-screen; some apps have nonstandard zoom behavior.
   Verify CoreAudio mute on the actual microphone device and hardware readback.
9. Quit normally with a held control, simulate lost BLE during a mapping transaction,
   then test a deliberate app crash only when prepared to power-cycle devices. Do
   not claim crash-safe hardware diversion before completing this test.
10. Run sustained scrolling and repeated reconnects for hours; record memory/CPU and
    power with Activity Monitor/Instruments. Short disconnected measurements do not
    establish long-duration performance or parity with other tools.
