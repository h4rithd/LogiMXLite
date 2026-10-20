# LogiMXLite

A focused, native macOS app for **exactly two Bluetooth Low Energy devices**:

| Device | USB product ID | Supported connection |
|---|---:|---|
| Logitech MX Master 3S for Mac mouse | `046D:B034` | Already-paired Bluetooth Low Energy |
| Logitech MX Mechanical Mini for Mac keyboard | `046D:B36D` | Already-paired Bluetooth Low Energy |

The packaged build runs on **Apple M-series Macs (arm64) with macOS 15 or later**. It is not a general Logitech device manager: other MX models, Unifying/Bolt receivers, USB-only control, and Flow are outside its scope. A USB cable can charge a device while it continues communicating over Bluetooth; charging status is shown when the device reports it.

LogiMXLite is an independent project by Harith Dilshan. It is not affiliated with Logitech.

## Screenshots

The images below are captures of the running macOS app, not design mockups. Battery levels and assignments reflect the test Mac at capture time.

![Overview showing the two connected devices](screenshots/overview.png)

| MX Master 3S buttons | MX Mechanical Mini keys |
|---|---|
| ![Mouse button assignments and connector lines](screenshots/mouse-buttons.png) | ![Keyboard function-key assignments](screenshots/keyboard-keys.png) |

## Install

1. Download [LogiMXLite 1.2.0.pkg](https://github.com/h4rithd/LogiMXLite/releases/download/v1.2.0/LogiMXLite-1.2.0.pkg) from the [Releases page](https://github.com/h4rithd/LogiMXLite/releases).
2. Check its SHA-256 if you want to verify the download: `96607b0d3efba8f84f71a5fe97bb0ceb1f5ad649c949ab40d8c7ab7ace420b81`.
3. Open the package and launch **LogiMXLite** from Applications. This locally built package is **unsigned and not notarized**; the app inside is ad-hoc signed. macOS may require **Control-click → Open** on first launch. The package does not establish a verified publisher identity.
4. Pair both supported devices in macOS Bluetooth settings, select this Mac on each Easy-Switch control, and grant **Input Monitoring** and **Accessibility** to LogiMXLite in System Settings → Privacy & Security. Relaunch after granting access.
5. Quit Logi Options+ or another tool that diverts the same controls before enabling mappings. The Settings screen shows permission and conflict status.

The app runs in the menu bar. Open its configuration window from the status item; use the same item to quit. Settings are stored locally in `~/Library/Application Support/LogiMXLite/` with private file permissions.

## What works

- **Mouse:** assign supported buttons to navigation, window, media, system, or recorded keyboard shortcuts. The thumb button supports click and four-direction gestures. Primary left/right clicks remain native.
- **Pointer and scrolling:** supported DPI values and presets, SmartShift/free-spin controls, vertical and horizontal scroll speed/direction, and optional smoothing. The scroll transform stops when the app quits.
- **Keyboard:** assign supported function-row controls, invert Fn mode, and configure supported backlight mode, brightness, inactivity timeout, and effects.
- **Profiles:** a Desktop configuration with optional per-application overrides. Profiles inherit unchanged controls from Desktop.
- **Device status:** battery percentage, reported charge state, connection state, and available Easy-Switch channel/host readback. Low-battery menu-bar indicators appear at 30% or below when the device is not charging.
- **Portability:** export/import validated JSON settings or preview an import of a local Logi Options+ `settings.db`. Imports do not run scripts and create a local recovery copy before applying changes.

Host names for other Easy-Switch channels appear only when the device provides verified HID++ data. No cloud account is needed. Some Options+ actions and exact physical scroll feel remain unverified; see the [hardware matrix](docs/HARDWARE_MATRIX.md) and [comparison notes](docs/OPTIONS_PLUS_COMPARISON.md).

## CPU and memory measurements

Measured on an **Apple M4 Mac, 24 GB RAM, macOS 27.0.1**, using the 1.2.0 arm64 build. These are local samples, not a claim that LogiMXLite matches Options+ latency or power use.

| Workload | CPU | Memory | Method |
|---|---:|---:|---|
| Connected menu-bar app, configuration window open, 20-second sample | 0.0–0.7% of one CPU core (mostly 0.6%) | 71 MB reported by `top` | `top -l 10 -s 2 -pid <pid> -stats pid,cpu,mem` |
| Device-free high-load benchmark: **100 million** button transitions, gesture movements, and scroll-state updates | 9.34 s user + 0.05 s system CPU over 9.76 s wall time (about **96% of one core** while busy) | **7.4 MiB** maximum RSS for the separate headless benchmark process | `/usr/bin/time -l LogiMXLite --stress-benchmark 100000000` |

The benchmark runs the app's core state machines without Bluetooth I/O, event injection, UI rendering, or physical device traffic. Its small headless-process RSS is **not** the GUI app's memory footprint and must not be added to or compared directly with the 71 MB GUI sample. Sustained real gestures, battery impact, and long-session memory behavior still need physical-device testing.

## Build and verify

Requires Xcode command-line tools with Swift 6. Packaging currently produces **arm64 only**.

```sh
swift build                # compile the production targets
make package               # app, unsigned PKG, ZIP, and DMG in dist/
make smoke                 # opens and closes a test configuration window
make benchmark             # repeatable 100-million-cycle core workload
```

The 1.2.0 app bundle passed `codesign --verify --strict`; the DMG verified and the PKG expanded with the app executable present. The 39 Swift tests passed before their source folder was removed at the owner's request because tests are not part of the installed app. This repository now contains production targets only, so `swift test` is no longer an available verification step. `pkgbuild` emitted local provenance-metadata warnings even though the package expanded successfully; signing and notarization require the maintainer's Apple Developer credentials. See the [security audit](docs/SECURITY_AUDIT_2026-10-20.md) for details.

## Privacy and project notes

There are no accounts, telemetry endpoints, network requests, or external Swift package dependencies in this build. The app uses IOHID for the two already-paired devices and macOS Accessibility for assigned actions. Exported settings may contain your profile names, app IDs, and shortcuts; treat exports as private. Review [privacy](docs/PRIVACY.md), [architecture](docs/ARCHITECTURE.md), [settings format](docs/SETTINGS_FORMAT.md), and [third-party notices](docs/THIRD_PARTY_NOTICES.md).

Device imagery is derived from owner-supplied Logitech screenshots; the project's code license does not grant rights to Logitech marks or imagery. This release is provided as an independent, experimental build, with physical device behavior documented only where tested.
