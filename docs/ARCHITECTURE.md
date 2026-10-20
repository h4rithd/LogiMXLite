# Architecture

One process, Swift 6 language mode, SwiftUI views hosted by AppKit. No helper,
Electron runtime, web view, server, updater or external packages.

## Boundaries

- `LogiCore/Configuration.swift`: allowlisted Codable model, semantic validation,
  inheritance, portable diff, explicit USB HID usage to ANSI virtual-key mapping.
- `ReferenceMigration.swift`: privacy-neutral native first-run defaults. Existing settings remain in Application Support.
  Removes identical per-app values for inheritance; retains source-only observations.
- `SettingsStore.swift`: actor-owned bounded file I/O, atomic save, backup and
  transactional preview/commit. Stale previews are rejected. UI adopts only committed
  settings. An unreadable existing file is not silently overwritten at startup.
- `IOHIDTransport.swift`: one IOHIDManager using public dispatch-queue APIs; exact
  VID/PID/transport/name allowlist followed by FF43:0202 usage-pair and output-size
  checks. Manager callbacks, devices, pending requests and queues are serialized on
  one queue. `@unchecked Sendable` is confined to this queue-owned boundary and a
  lock-protected cancellation flag. C callback contexts retain async report buffers
  through IOKit completion. No manager/device is seized exclusively.
- `HIDPP.swift`: strict 7/20-byte decoder, device routing index 1, feature/function/
  software correlation, error correlation, bounded range and control parsers.
  BLE output always uses long 20-byte report 0x11. Unknown models receive no requests.
- `Hardware.swift`: actor and transaction gate serialize complete read/write/readback
  sequences across suspension points. Probe precedes write. DPI ranges are expanded
  from device values, not product specifications. Writes are spaced at least 150 ms.
  Busy error 8 gets at most two retries with 50/100 ms delay. Transport timeouts,
  permission and write errors fail closed without blind retries. Timed-out or
  cancelled in-flight endpoints are quarantined until reopen, preventing late replies
  from satisfying new transactions. Queue length is bounded at 64 per model.
- `InputState.swift`: pure gesture, button-edge, permission, conflict, revision and
  smoothing state machines. No idle input timer.
- `ScrollEngine.swift`: a session scroll tap, installed only when a saved profile
  changes scrolling or assigns a thumb-wheel mode. Gesture-phase trackpad events
  pass through; smoothing runs an 8 ms timer only while output remains queued.
- `Actions.swift`: main-actor native dispatch and HID++ event handling. Actions use
  press snapshots, pair middle down/up, debounce, gesture timeout, on-demand repeats
  and held-control watchdogs. Injected events carry a unique marker; no injected
  event stream is listened to, so there is no synthesis loop. Secure input is respected.
- `AppModel.swift`: one active-profile NSWorkspace listener, selected editing draft,
  saved configuration, confirmed device state, explicit import review. Rapid switches
  invalidate old work; a serial mapping reconciliation worker restores before enabling
  the new profile's actionable controls. No primary click or standard typing diversion.
- `Main.swift` / `OptionsWorkspace.swift`: one original template status icon and
  transient popover, demand-created native SwiftUI device workspace. Closing the
  window releases its view tree. Device art is packaged locally; no Electron or
  background web renderer is used. macOS 26+ uses native Liquid Glass on the
  workspace panels, with material fallback on macOS 15–25. Native menus provide
  quit, edit shortcuts and configuration access.

## State and lifecycle

Disconnected → exact device discovered → vendor endpoint opened → read-only ping
and feature enumeration → individual capability reads → optional verified writes.
Discovery, feature support and successful writes are separate facts. Device absence
and all unknown readings remain explicit. Firmware strings contain only firmware
fields; unit IDs and serial fields are discarded and serial functions never requested.

Sleep, removal, Quit and permission failures cancel input work and attempt to restore
saved temporary control flags. Retry rebuilds the manager and invalidates capabilities.
Temporary mapping is session-only; persistent diversion bits are never written.
Clean restoration is checked by reading the flags. Crash restoration still requires
physical validation and may require a device power cycle. Hardware scroll is not
diverted, so it does not depend on cleanup for normal scrolling. The session tap
is removed on quit or when settings are identity.

Battery status notifications update the UI; an infrequent five-minute read-only
refresh covers missing notifications. The two-second permission/secure-input check
exists only while mappings are enabled. Gesture/repeat timers exist only while held.
All I/O outside native UI operations runs off the UI actor.

## Intentional gates

Backlight 0x1982 writes require version 3 and valid configuration/info responses.
Unknown backlight protocols remain unavailable. The source effect is not applied
until hardware reports support. Full config writes preserve all four duration fields;
effect-only writes use the volatile effect command. Identical settings skip writes.
Other documented feature IDs use their backward-compatible base functions; hidden
and obsolete features are excluded from the write lookup.

There is no reliable public CGEvent device-identity filter here. The scroll tap
excludes gesture-phase trackpad events, but an unrelated discrete-wheel mouse
could also be transformed while a profile's scrolling is active. This requires
physical multi-device testing before claiming device-specific scroll parity.
