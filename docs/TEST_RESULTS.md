# Test results

## 1.2.4 optional menu-bar UI

On 2026-10-21, the installed build's Settings page showed **Show menu-bar icon** with the same switch style as Launch at Login. Switching it off, closing Configuration, and inspecting the resident process showed zero accessible menu bars and one remaining LogiMXLite process. Reopening the app from Applications launched one short-lived configuration child. Switching the icon back on and closing Configuration restored the monochrome status item. The Quit button in Settings stopped both the configuration child and resident agent. Preference persistence was confirmed through macOS defaults. With the icon off after a fresh launch, `footprint` reported **9,089 KB** and five idle `top` samples reported **0.0% CPU**. After an on/off cycle without restarting, the allocator retained about **13 MB**. The supported devices were offline during this run, so live mappings, battery polling suppression on hardware, and physical actions were not verified here. Code inspection confirms the headless probe skips firmware, battery, and host readback and the periodic battery task is not started.

## 1.2.3 status icon and idle-memory check

On 2026-10-21, the original template-drawn mouse-and-keyboard symbol was visually confirmed in the installed menu bar. The Finder/Dock `.icns` remained packaged and the temporary `StatusIcon.png` was absent. The SwiftUI dropdown opened from the status item after its view was made lazy. `footprint -p` measured 15 MB immediately after a fresh launch and 22 MB after opening and closing the dropdown; five idle `top` samples showed 0.0% CPU before opening it. This is one open/close cycle, not a long-duration leak test. The arm64 build and app signature verified, the DMG verified, the PKG contained the app icon, and installed and packaged executable SHA-256 values matched. The PKG remains unsigned and unnotarized.

## 1.2.2 application icon verification

On 2026-10-21, the arm64 app and PKG/DMG/ZIP built with a multi-resolution `LogiMXLite.icns` generated from the supplied 1024-pixel PNG. `iconutil` extracted all ten expected iconset variants, `CFBundleIconFile` resolved in the installed app, and `NSWorkspace` returned the installed app icon. The resident process used the packaged 36-pixel menu-bar image; its physical footprint was 16 MB both with the configuration process open and after it closed. The configuration child reported regular activation policy, so its installed app icon appears in the Dock; the menu-bar agent remained accessory-only. `codesign --verify --strict`, DMG verification, PKG payload inspection, matching packaged/installed executable hashes, and the five-second configuration-process smoke test passed. The PKG remains unsigned and unnotarized.

## 1.2.1 process split and memory verification

On 2026-10-20, the arm64 release build and application signature verified. The PKG expanded, the DMG verified, and the configuration-process smoke hook reported `configurationProcessRunning=true`. The installed 1.2.1 binary matched the packaged executable by SHA-256. The live configuration child showed both supported BLE devices connected and mappings active; after closing its window, the child exited and the menu-bar process remained alone. The Settings → Relaunch button closed the old child and opened one new child while the resident process stayed at 17 MB; closing that new window again left the resident process alone. Quitting the resident process with a child open ended both processes.

On the Apple M4 / 24 GB Mac running macOS 27.0.1, `footprint -p` measured the resident device process at 16–17 MB before, during, and after configuration. The child measured 44 MB on Overview, 58 MB on Mouse, and 64 MB after visiting Keyboard. Ten `top -l 10 -s 2` samples over about 20 seconds measured the connected resident process at 0.0–0.4% CPU. A separate 100-million-iteration device-free stress process used 8.80 seconds wall / 8.77 seconds user CPU and 7,684,096 bytes maximum RSS. This does not verify sustained physical gestures or transition latency.

## 1.2.0 release verification

On 2026-10-20, `swift test` passed all 39 tests before the test sources and test target were removed at the owner's request; that command is no longer available in the current source tree. The arm64 app built and passed `codesign --verify --strict`; the DMG verified and the unsigned PKG expanded with the executable present. The installed 1.2.0 binary matched the packaged binary by SHA-256 and the live overview showed both supported devices connected. This is not a full physical-control acceptance test.

On an Apple M4 Mac with 24 GB RAM and macOS 27.0.1, ten `top` samples over roughly 20 seconds showed the connected GUI process at 71 MB and 0.0–0.7% CPU (mostly 0.6%). A separate headless 1.2.0 process ran 100 million deterministic button, gesture and scroll-state cycles in 9.403 seconds of loop time: `/usr/bin/time -l` measured 9.76 seconds wall, 9.34 seconds user CPU, 0.05 seconds system CPU, and 7,733,248 bytes maximum resident set size. That benchmark does not exercise Bluetooth, macOS input injection, or UI rendering. See the README for interpretation.

Collected 2026-10-20 on the development Mac. Software and readback results are observed command output; physical behavior still needs the checks in [HARDWARE_MATRIX.md](HARDWARE_MATRIX.md).

| Check | Result |
|---|---|
| 1.1.5 security build | 39 tests passed; private-file scan passed; app signature verified; PKG expanded and DMG verified; removed reference resource absent from app, ZIP, and PKG |
| 1.1.1 interface and quit | 37 tests passed; packaged smoke returned `statusItems=1 settingsVisible=true`, exit 0; native UI inspection confirmed fixed-size window, connected mouse callout lines, native thumb-wheel label, responsive scroll slider, closable DPI sheet and Quit |
| `make package` | arm64 app, ZIP, DMG and PKG produced; `codesign --verify --strict` passed |
| 1.1.0 gesture build | Packaged after axis-snapping and ordered event delivery; 37 tests passed, launch smoke returned `statusItems=1 settingsVisible=true` |
| Local installation | `/Applications/LogiMXLite.app` replaced and reopened; installed binary SHA-256 matches the new package app binary |
| Installer payload | `pkgutil --payload-files` contains `Applications/LogiMXLite.app/Contents/MacOS/LogiMXLite` |
| Launch smoke | `SMOKE: statusItems=1 settingsVisible=true`, exit 0; home, mouse and keyboard windows captured and visually inspected |
| 1.1.0 installed UI | Old process quit; `/Applications/LogiMXLite.app` launched with the new Liquid Glass dashboard on macOS 27.0.1 |
| HID++ read-only diagnosis | Both devices enumerated with feature tables; battery 45%/80%, mouse DPI 1650 with 200–8000 range, keyboard Fn/backlight state read |
| Settings import preview | Installed Options+ `settings.db` opened read-only; preview only, not applied to the user's configuration |

The package is ad-hoc signed, not Developer ID signed or notarized. macOS may require the user to allow opening it. The images in the UI come from owner-supplied reference screenshots via generated cutouts; no hashed Options+ assets were copied into the app.

The 1.1.0 PKG was also unsigned (`pkgutil --check-signature`: no signature). Its SHA-256 for that build was `14d1b951e295c16eaaa02c0d6600df9ad3b531456f1140fd23a5792d68ce3172`. A single post-launch idle sample of that app was about 79 MiB RSS and 0% CPU; this is not a latency, energy or long-duration footprint measurement.

The 1.1.1 PKG is unsigned and expands successfully with `pkgutil --expand-full`. Its SHA-256 is `02062b706546d5f76f96ef640bb838b95a647e7b939056332a727e25530be284`. The installed binary hash matches the packaged app binary, and opening Configuration after installation showed no restoration modal.

The 1.1.1 window was visually checked at its fixed 1380 × 820 point size. The mouse and Point and Scroll connector lines stay attached to the image and the inspector does not overlap it. The menu-bar battery and physical control paths could not be accepted on both devices in this run: the app reported them offline and the local status command reported an active `LogiPluginService` conflict. The 60%/84% slider positions are confirmed in UI and configuration; identical physical scroll acceleration remains unverified.

The smoke run was short and happened while another LogiMXLite instance and Options+ were running. Device access and mappings can be blocked by those processes; its battery display is not evidence of stable reconnection. No long-duration memory, CPU, energy, button, DPI-write, SmartShift-write, host-switch or keyboard-backlight-write comparison was performed for this build. These need a separate physical acceptance run without the competing app.

The 1.1.2 follow-up fixes the HID++ 0x1982 backlight Off command: it now clears the independent enable bit while retaining the selected mode and verifies that bit on readback. A mock transport test covers Off, changing duration while Off, and On. `swift test --enable-swift-testing` passed all 37 tests, the packaged app passed launch smoke, and the 1.1.2 PKG expanded successfully; SHA-256 is `00913ecf81817d487738aa68aee3917ee507731ba08dd8eaed3de62de33c4ea2`. The installed binary hash matched the packaged app. The mouse page now displays why mappings are inactive, and mapping enablement is retried when a conflicting application exits. The installed `LogiPluginService` was quit and the app status then showed no conflict. macOS Bluetooth still listed both MX devices as *not connected*, so actual backlight, middle-button, and gesture behavior remains unverified on hardware.

Later the same day, both devices reconnected to the test Mac. macOS Bluetooth and `hidutil` listed both active HID devices; the LogiMXLite dashboard showed mouse 40% and keyboard 80% battery, and its Settings page showed mappings enabled with HID++ readback available. Backlighting → Off returned a confirmed device readback, was saved to the Desktop profile, and still displayed Off after navigating away and back. The owner physically pressed the mouse wheel button and performed one left thumb gesture and reported that both assigned actions worked. Other gesture directions, long-session reliability, and identical Options+ scroll feel remain untested.

A short packaged-app home-window smoke run after the UI redesign took 5.24 s wall time, 0.18 s user CPU, 0.05 s system CPU, 119.8 MB maximum RSS and 40.2 MB peak physical footprint. Those metrics are not a controlled comparison with Options+; remeasure under connected idle and sustained input workloads.
