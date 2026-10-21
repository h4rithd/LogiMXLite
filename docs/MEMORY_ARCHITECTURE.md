# Memory and process architecture

Since 1.2.1, LogiMXLite has two **process roles** using one signed executable and one bundle identifier:

- The resident menu-bar process owns HID++ reports, mouse gestures, scrolling, active profiles, and battery status. It does not construct the large configuration window or decode its device PNGs.
- A configuration child starts on demand. The resident process first stops input diversion and releases its IOHID manager. The child then opens the SwiftUI window and temporarily owns the devices. Closing the window makes the child restore native control state and exit. Only after that exit does the resident process reload saved settings and reconnect.

The parent retains a `Process` handle and receives its termination callback. A crash or ordinary window close both trigger reconnection. A Quit from the resident process also requests the child to quit and waits for its shutdown. The child validates that its `--parent-pid` is its actual OS parent, so a normal standalone launch cannot accidentally start a second device owner. Settings are exchanged through the existing private, validated settings file; no socket, network listener, or separately installed daemon is introduced.

This design ensures only **one process owns the devices at a time** and releases the SwiftUI window's allocator and image caches when it closes. It does introduce a short mapping pause during handoff; gestures already in progress should finish before opening or closing Configuration. It does not claim that physical input latency or battery impact is identical to Logi Options+.

On the development Apple M4 Mac, the resident process remained at **16–17 MB physical footprint** with the UI closed, including after visiting the mouse and keyboard pages repeatedly. The short-lived UI process reached **58–64 MB** on those pages, then exited. A 10-sample, 20-second `top` series showed **0.0–0.4% CPU** for the connected resident process. See the [README](../README.md) and [test results](TEST_RESULTS.md) for the measurement method and limits.
