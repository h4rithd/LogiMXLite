import AppKit
import IOKit.hid
import Carbon
import Darwin
import SwiftUI
import LogiCore

@main @MainActor struct LogiMXLiteMain {
    static func main() {
        if CommandLine.arguments.contains("--stress-benchmark") {
            StressBenchmark.run()
            return
        }
        if CommandLine.arguments.contains("--configuration-process") {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "--parent-pid"),
                  arguments.indices.contains(index + 1),
                  Int32(arguments[index + 1]) == getppid() else {
                FileHandle.standardError.write(Data("Configuration must be opened by the menu-bar agent.\n".utf8))
                return
            }
        }
        let app = NSApplication.shared
        let delegate = ApplicationDelegate()
        app.delegate = delegate
        // Only the on-demand configuration process appears in the Dock. The
        // resident device agent stays menu-bar-only and keeps its small footprint.
        app.setActivationPolicy(CommandLine.arguments.contains("--configuration-process") ? .regular : .accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel?
    private var status: NSStatusItem?
    private var lowBatteryItems: [Model:NSStatusItem] = [:]
    private let popover = NSPopover()
    private var window: NSWindow?
    /// The menu-bar instance owns devices until a configuration child takes over.
    /// Keeping the UI in a separate process lets macOS reclaim all SwiftUI memory
    /// when its window closes, without keeping a second resident helper binary.
    private var configurationProcess: Process?
    private var openingConfiguration = false
    private var relaunchConfigurationRequested = false
    private var isConfigurationProcess: Bool { CommandLine.arguments.contains("--configuration-process") }
    private var terminating = false
    private var terminationRequested = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--status") {
            let conflicts = NSWorkspace.shared.runningApplications.compactMap { ConflictDetector.matches($0.bundleIdentifier ?? "") ? $0.localizedName : nil }
            print("STATUS inputMonitoring=\(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted) accessibility=\(AXIsProcessTrusted()) secureInput=\(IsSecureEventInputEnabled()) conflicts=\(conflicts)")
            NSApplication.shared.terminate(nil); return
        }
        if CommandLine.arguments.contains("--diagnose") { runDiagnostics(); return }
        if let i = CommandLine.arguments.firstIndex(of: "--import-optionsplus"), CommandLine.arguments.indices.contains(i + 1) { runOptionsPlusImport(path: CommandLine.arguments[i + 1], apply: CommandLine.arguments.contains("--apply")); return }
        if CommandLine.arguments.contains("--restore-native") { runRestoreNative(); return }
        if let i = CommandLine.arguments.firstIndex(of: "--perform"), CommandLine.arguments.indices.contains(i + 1), let kind = ActionKind(rawValue: CommandLine.arguments[i + 1]) {
            // Test hook: runs one action through the same executor a button press uses, then exits.
            let executor = ActionExecutor(); executor.onError = { print("ACTION ERROR: \($0)") }
            let extra = CommandLine.arguments.dropFirst(i + 2).compactMap { Int($0) }
            let action = kind == .shortcut && !extra.isEmpty ? Action(.shortcut, usage: extra[0], modifiers: Array(extra.dropFirst())) : Action(kind)
            Task { executor.perform(action); try? await Task.sleep(for: .milliseconds(80)); executor.perform(action, down: false); try? await Task.sleep(for: .milliseconds(400)); print("PERFORMED \(kind.rawValue)"); NSApplication.shared.terminate(nil) }
            return
        }
        installMenus()
        let model = AppModel(); self.model = model
        if isConfigurationProcess {
            model.quit = { NSApplication.shared.terminate(nil) }
            model.requestRelaunch = { [weak self] in
                self?.relaunchConfigurationRequested = true
                NSApplication.shared.terminate(nil)
            }
            model.start()
            openSettings()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status = item; item.button?.image = Self.mark(); item.button?.toolTip = "LogiMXLite · mouse and keyboard"; item.button?.setAccessibilityLabel("LogiMXLite devices")
        item.button?.target = self; item.button?.action = #selector(togglePopover)
        popover.behavior = .transient; popover.contentViewController = NSHostingController(rootView:LiteMenuView(model:model))
        model.showSettings = { [weak self] in self?.openSettings() }
        model.quit = { NSApplication.shared.terminate(nil) }
        model.onDeviceStatusChange = { [weak self] in self?.updateBatteryItems() }
        model.start()
        if CommandLine.arguments.contains("--settings") { openSettings() }
        if CommandLine.arguments.contains("--smoke-test") {
            openSettings()
            Task {
                try? await Task.sleep(for: .seconds(5))
                print("SMOKE: statusItems=1 configurationProcessRunning=\(configurationProcess?.isRunning == true)")
                NSApplication.shared.terminate(nil)
            }
        }
    }
    private func installMenus() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu(title:"LogiMXLite")
        appMenu.addItem(withTitle:"Open Configuration",action:#selector(openConfiguration),keyEquivalent:",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:"Quit LogiMXLite",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu = appMenu; bar.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"Edit")
        for (name,action,key) in [("Undo","undo:","z"),("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            editMenu.addItem(withTitle:name,action:Selector(action),keyEquivalent:key)
        }
        editItem.submenu = editMenu; bar.addItem(editItem); NSApplication.shared.mainMenu = bar
    }
    @objc private func openConfiguration() { openSettings() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    @objc private func togglePopover() {
        if let child = configurationProcess, child.isRunning {
            NSRunningApplication(processIdentifier: child.processIdentifier)?.activate()
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else if let button = status?.button { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY); model?.checkPermissions() }
    }
    private func updateBatteryItems() {
        guard let model else { return }
        for device in Model.allCases {
            let state = model.devices[device]
            let percentage = state?.snapshot.battery
            let low = state?.connected == true && percentage.map { $0 <= 30 } == true
                && state?.snapshot.batteryStatus?.isCharging != true
            if low, let percentage {
                let item = lowBatteryItems[device] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                lowBatteryItems[device] = item
                item.button?.image = NSImage(systemSymbolName: device == .mouse ? "computermouse" : "keyboard", accessibilityDescription: device.name)
                item.button?.imagePosition = .imageLeading
                item.button?.title = "\(percentage)%"
                item.button?.toolTip = "\(device.name) battery low: \(percentage)%"
                item.button?.setAccessibilityLabel("\(device.name) battery low, \(percentage) percent")
                item.button?.target = self
                item.button?.action = #selector(togglePopover)
            } else if let item = lowBatteryItems.removeValue(forKey: device) {
                NSStatusBar.system.removeStatusItem(item)
            }
        }
    }
    private func openSettings() {
        guard let model else { return }; popover.performClose(nil)
        if !isConfigurationProcess {
            if let process = configurationProcess, process.isRunning {
                NSRunningApplication(processIdentifier: process.processIdentifier)?.activate()
                return
            }
            guard !openingConfiguration else { return }
            openingConfiguration = true
            let requestedPage = model.requestedPage
            Task { [self] in
                // Only one process may own the HID++ vendor reports and temporary
                // control diversion. Await full restoration before launching the UI.
                await model.suspend()
                guard !terminating else { openingConfiguration = false; return }
                let child = Process()
                child.executableURL = Bundle.main.executableURL
                child.arguments = ["--configuration-process", "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
                    + (requestedPage.map { ["--page", $0.rawValue] } ?? [])
                child.terminationHandler = { [weak self] process in
                    let reopen = process.terminationReason == .exit && process.terminationStatus == 42
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.configurationProcess = nil
                        guard !self.terminating else { return }
                        if reopen {
                            self.openSettings()
                        } else {
                            await self.model?.resumeAfterConfiguration()
                        }
                    }
                }
                do {
                    try child.run()
                    configurationProcess = child
                } catch {
                    model.report("Could not open configuration: \(error.localizedDescription)")
                    await model.resumeAfterConfiguration()
                }
                openingConfiguration = false
            }
            return
        }
        if window == nil {
            let w = NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:820),styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
            w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isMovableByWindowBackground = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            // 52pt unified titlebar: window buttons sit centred in the sidebar's top band, aligned with its text.
            let bar = NSToolbar(identifier: "LogiMXLite.main")
            w.toolbar = bar; w.toolbarStyle = .unified; w.titlebarSeparatorStyle = .none
            w.collectionBehavior.insert(.fullScreenNone)
            let page = CommandLine.arguments.firstIndex(of:"--page").flatMap { i in CommandLine.arguments.indices.contains(i+1) ? SectionPage(argument:CommandLine.arguments[i+1]) : nil } ?? .devices
            w.delegate = self; w.title = "LogiMXLite"; w.isReleasedWhenClosed = false; w.contentView = NSHostingView(rootView:SettingsView(model:model,initialPage:page)); w.contentMinSize = NSSize(width:1380,height:820); w.contentMaxSize = w.contentMinSize; w.standardWindowButton(.zoomButton)?.isHidden = true; w.center(); window = w
        }
        NSApplication.shared.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
        LiteImage.clearWindowCache()
        if isConfigurationProcess {
            NSApplication.shared.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateNow }; terminating = true
        popover.performClose(nil)
        Task {
            if isConfigurationProcess, let model {
                // A Save or Import task may still be writing atomically when the
                // user closes the window immediately after clicking its button.
                for _ in 0..<100 where model.busy {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            if let child = configurationProcess, child.isRunning {
                _ = NSRunningApplication(processIdentifier: child.processIdentifier)?.terminate()
                for _ in 0..<50 where child.isRunning {
                    try? await Task.sleep(for: .milliseconds(200))
                }
                if child.isRunning { child.terminate() }
            }
            await model?.shutdown()
            if let status { NSStatusBar.system.removeStatusItem(status) }
            for item in lowBatteryItems.values { NSStatusBar.system.removeStatusItem(item) }
            lowBatteryItems.removeAll()
            finishTermination(sender)
        }
        // A sleeping BLE device can delay HID++ readback. Quit must remain
        // responsive even if native-control restoration cannot be confirmed.
        Task {
            try? await Task.sleep(for: .seconds(10))
            finishTermination(sender)
        }
        return .terminateCancel
    }
    private func finishTermination(_ sender: NSApplication) {
        guard !terminationRequested else { return }
        terminationRequested = true
        if isConfigurationProcess && relaunchConfigurationRequested { Darwin.exit(42) }
        sender.terminate(nil)
    }
    static func mark() -> NSImage {
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        // SwiftPM command-line development builds do not have the packaged icon.
        let image = NSImage(size:NSSize(width:22,height:22),flipped:false) { _ in
            NSColor.labelColor.setStroke()
            let keyboard = NSBezierPath(roundedRect:NSRect(x:1,y:4,width:13,height:10),xRadius:2,yRadius:2); keyboard.lineWidth=1.4; keyboard.stroke()
            let mouse = NSBezierPath(roundedRect:NSRect(x:15,y:3,width:6,height:15),xRadius:3,yRadius:3); mouse.lineWidth=1.4; mouse.stroke()
            let keys = NSBezierPath(); for y in [7,10] { for x in [4,7,10] {keys.move(to:NSPoint(x:x,y:y));keys.line(to:NSPoint(x:x+1,y:y))} };keys.lineWidth=1.2;keys.stroke()
            let wheel = NSBezierPath();wheel.move(to:NSPoint(x:18,y:12));wheel.line(to:NSPoint(x:18,y:15));wheel.lineWidth=1.4;wheel.stroke();return true
        }; image.isTemplate=true; return image
    }
    /// Prints the settings.db import preview. Only --apply writes, and a backup of the current settings is saved first.
    private func runOptionsPlusImport(path: String, apply: Bool) {
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LogiMXLite",isDirectory:true)
        let store = SettingsStore(directory:directory)
        Task {
            do {
                let current = try await store.load()
                let preview = try await store.previewOptionsPlus(URL(fileURLWithPath:path),current:current)
                preview.changes.forEach { print($0) }
                if apply { _ = try await store.commit(preview,current:current); print("APPLIED; backup saved as backup.json") } else { print("PREVIEW ONLY; pass --apply to write") }
            } catch { print("FAILED: \(error.localizedDescription)") }
            NSApplication.shared.terminate(nil)
        }
    }
    /// Releases any diversion left on the devices by another tool or a crashed run so native buttons work again.
    private func runRestoreNative() {
        let transport = IOHIDTransport(); let hardware = Hardware(transport:transport)
        transport.start { _ in }
        Task {
            try? await Task.sleep(for:.seconds(3))
            for m in Model.allCases {
                do { _ = try await hardware.probe(m); print("\(m.name): released controls \(await hardware.clearStale(m))") }
                catch { print("\(m.name): \(error.localizedDescription)") }
            }
            await transport.stop(); NSApplication.shared.terminate(nil)
        }
    }
    private func runDiagnostics() {
        let transport = IOHIDTransport(); let hardware = Hardware(transport:transport)
        transport.start { event in
            switch event {
            case .connected(let m,_): print("CONNECTED \(m.name)")
            case .diagnosis(let m,let text): print("DIAG \(m?.name ?? "manager"): \(text)")
            case .removed(let m): print("REMOVED \(m.name)")
            case .notification: break
            }
        }
        Task {
            try? await Task.sleep(for:.seconds(3))
            for m in Model.allCases {
                do {
                    let s = try await hardware.probe(m)
                    print("PROBE \(m.name): battery=\(s.battery.map(String.init) ?? "unknown") charge=\(s.batteryStatus.map { String(describing:$0) } ?? "unknown") host=\(s.currentHost.map(String.init) ?? "unknown")/\(s.hostCount.map(String.init) ?? "unknown") dpi=\(s.dpi.map(String.init) ?? "unknown")")
                    for host in s.hosts { print("HOST \(m.name): channel=\(host.channel) paired=\(host.paired) nameAvailable=\(host.name != nil)") }
                    for f in s.features.values.sorted(by:{$0.id<$1.id}) {print(String(format:"FEATURE %04X index=%d version=%d",f.id,f.index,f.version))}
                    for issue in s.issues {print("PARTIAL \(issue)")}
                    for c in s.controls {print("CONTROL \(m.name) cid=\(c.id) task=\(c.task) flags=\(String(c.flags,radix:16)) divertible=\(c.divertible) rawXY=\(c.rawXY) reporting=\(String(c.reporting,radix:16)) remap=\(c.remap) divertedByOther=\(c.divertedByOther)")}
                    if let w = s.wheelMode {print("WHEEL mode=\(w == 1 ? "free-spin" : "ratchet") threshold=\(s.threshold.map(String.init) ?? "?")")}
                    if let r = s.dpiRange {print("DPI range \(r.values.first ?? 0)...\(r.values.last ?? 0) count=\(r.values.count)")}
                    if let f = s.fnInverted {print("FN inverted=\(f)")}
                    if let b = s.backlight {print("BACKLIGHT mode=\(b.mode) level=\(b.level)/\(b.levels) effect=\(b.effect) effects=\(String(b.effects,radix:2)) duration=\(b.duration)")}
                } catch {print("BLOCKED \(m.name): \(error.localizedDescription)")}
            }
            await transport.stop(); NSApplication.shared.terminate(nil)
        }
    }
}
