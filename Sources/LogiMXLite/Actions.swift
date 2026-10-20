import AppKit
import ApplicationServices
import Carbon
import CoreAudio
import LogiCore
import os

let inputLog = Logger(subsystem: "com.h4rithd.LogiMXLite", category: "input")

@MainActor final class ActionExecutor {
    static let injectionTag: Int64 = 0x4C4D584C
    var onHardwareAction: ((ActionKind) -> Void)?
    var onError: ((String) -> Void)?
    private var heldButtons: Set<Int> = []
    var canPost: Bool { AXIsProcessTrusted() && !IsSecureEventInputEnabled() }
    static let mouseButtons: [ActionKind: Int] = [.middleClick: 2]
    func perform(_ action: Action, down: Bool = true) {
        if action.kind == .back || action.kind == .forward {
            if down { guard !IsSecureEventInputEnabled() else { onError?("Secure input active; actions paused"); return }; navigationSwipe(back: action.kind == .back) }
            return
        }
        if let button = Self.mouseButtons[action.kind] { mouseButton(button, down); return }
        guard down else { return }
        guard !IsSecureEventInputEnabled() else { onError?("Secure input active; actions paused"); return }
        switch action.kind {
        case .none, .nativeHorizontalScroll, .middleClick, .back, .forward: break
        case .requiresConfirmation: onError?("Not supported: \(action.note ?? "source action")")
        case .downloads:
            if let url = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first { NSWorkspace.shared.open(url) }
        case .missionControl: launch(["com.apple.exposelauncher"])
        case .maximize: maximizeFocusedWindow()
        case .shortcut: if let u = action.usage { shortcut(u,action.modifiers ?? []) }
        case .launchpad: launch(["com.apple.launchpad.launcher", "com.apple.apps.launcher"])
        case .appExpose: launch(["com.apple.exposelauncher"], arguments: ["2"])
        case .desktopLeft: switchSpace(0x7B)
        case .desktopRight: switchSpace(0x7C)
        case .backlightUp, .backlightDown: onHardwareAction?(action.kind)
        case .smartZoom: smartZoom()
        case .showDesktop: launch(["com.apple.exposelauncher"], arguments: ["1"])
        case .brightnessUp: media(2)
        case .brightnessDown: media(3)
        case .scrollLeft, .scrollRight: scrollHorizontal(action.kind == .scrollLeft ? 3 : -3)
        case .fnLockToggle: onHardwareAction?(action.kind)
        case .calculator: open(bundle: "com.apple.calculator")
        case .systemSettings: open(bundle: "com.apple.systempreferences")
        case .siri: open(bundle: "com.apple.Siri")
        case .thumbZoom, .thumbDesktops, .thumbVolume, .thumbApps, .thumbTabs, .thumbPages, .thumbTracks, .thumbBrightness: break
        case .emoji: shortcut(44,[224,227])
        case .screenshot: screenshotRegion()
        case .nextTrack: media(17)
        case .previousTrack: media(18)
        case .playPause: media(16)
        case .mute: media(7)
        case .volumeUp: media(0)
        case .volumeDown: media(1)
        case .microphoneMute: microphoneMute()
        case .cycleDPI, .wheelMode: onHardwareAction?(action.kind)
        }
    }
    func releaseAll() { for button in heldButtons.sorted() { mouseButton(button, false) } }
    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData,value:Self.injectionTag); event.post(tap:.cghidEventTap)
    }
    private func shortcut(_ usage: Int, _ modifiers: [Int]) {
        guard canPost, let code = HIDKeyMap.virtualKey[usage] else { onError?("Accessibility is required to post shortcuts"); return }
        var flags: CGEventFlags = []
        for m in modifiers { flags.formUnion([224:.maskControl,225:.maskShift,226:.maskAlternate,227:.maskCommand][m] ?? []) }
        postKey(code, flags: flags)
    }
    /// The Options+ Maximize preset operates on the frontmost window. Pressing its
    /// accessibility Zoom button preserves macOS's native toggle and avoids entering
    /// full screen (which Control-Command-F would do).
    private func maximizeFocusedWindow() {
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            onError?("Accessibility is required to zoom the focused window"); return
        }
        let application = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let window = focused, CFGetTypeID(window) == AXUIElementGetTypeID() else { onError?("No focused window to zoom"); return }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXZoomButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { onError?("This window has no zoom button"); return }
        if AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) != .success {
            onError?("Could not zoom this window")
        }
    }
    /// Same as Options+ PostKeyboardEvent: key-down keeps the flags macOS assigns to the key (Fn and keypad for arrows,
    /// Home, End, Page Up/Down) and adds the modifiers; key-up carries only the modifiers.
    private func postKey(_ code: CGKeyCode, flags: CGEventFlags) {
        for down in [true,false] {
            guard let e = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:down) else { continue }
            e.flags = down ? e.flags.union(flags) : flags
            post(e)
        }
    }
    /// Buttons 4 and 5 (macOS numbers 3 and 4) are what the mouse itself sends natively, so apps react exactly as before.
    private func mouseButton(_ number: Int, _ down: Bool) {
        guard down ? canPost : heldButtons.contains(number) else { return }
        if down { heldButtons.insert(number) } else { heldButtons.remove(number) }
        let point = CGEvent(source:nil)?.location ?? .zero
        let event = CGEvent(mouseEventSource:nil,mouseType:down ? .otherMouseDown : .otherMouseUp,mouseCursorPosition:point,mouseButton:CGMouseButton(rawValue:UInt32(number)) ?? .center)
        event?.setIntegerValueField(.mouseEventButtonNumber,value:Int64(number))
        post(event)
    }
    /// Same as Options+ (logi::gestures back_forward): a navigation-swipe gesture, began then ended with a direction mask.
    private func navigationSwipe(back: Bool) {
        guard canPost else { onError?("Accessibility is required for back and forward"); return }
        for (phase, mask) in [(Int64(1), Int64(0)), (Int64(4), back ? Int64(4) : Int64(8))] {
            guard let event = CGEvent(source:nil) else { return }
            event.setIntegerValueField(Self.field(55),value:29)    // gesture event
            event.setIntegerValueField(Self.field(110),value:16)   // HID navigation swipe
            event.setIntegerValueField(Self.field(132),value:phase)
            // Options+ writes the direction mask as raw float bits, not as a numeric value.
            event.setDoubleValueField(Self.field(113),value:Double(Float(bitPattern:UInt32(mask))))
            event.setIntegerValueField(.eventSourceUserData,value:Self.injectionTag)
            event.post(tap:.cgSessionEventTap)
        }
    }
    private static func field(_ raw: UInt32) -> CGEventField { CGEventField(rawValue:raw)! }
    /// Same as Options+ InjectMoveToLeft/RightSpace: Control+arrow, then an explicit Control release.
    private func switchSpace(_ code: CGKeyCode) {
        guard canPost else { onError?("Accessibility is required to switch desktops"); return }
        postKey(code, flags: .maskControl)
        let release = CGEvent(keyboardEventSource:nil,virtualKey:0x3B,keyDown:false); release?.flags = []; post(release)
    }
    /// Same as Options+ injector: Mission Control, App Exposé, Show Desktop and Launchpad are system launcher apps.
    private func launch(_ bundles: [String], arguments: [String] = []) {
        guard let url = bundles.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0) }).first else { onError?("\(bundles[0]) is not available"); return }
        let configuration = NSWorkspace.OpenConfiguration(); configuration.arguments = arguments
        NSWorkspace.shared.openApplication(at:url,configuration:configuration)
    }
    /// One thumb-wheel step in a two-way mode. `forward` is the wheel turned toward the screen's right/up.
    func thumb(_ mode: ActionKind, forward: Bool) {
        let pairs: [ActionKind: (Action, Action)] = [
            .thumbZoom: (Action(.shortcut, usage: 45, modifiers: [227]), Action(.shortcut, usage: 46, modifiers: [227])),
            .thumbDesktops: (Action(.desktopLeft), Action(.desktopRight)),
            .thumbVolume: (Action(.volumeDown), Action(.volumeUp)),
            .thumbApps: (Action(.shortcut, usage: 43, modifiers: [225, 227]), Action(.shortcut, usage: 43, modifiers: [227])),
            .thumbTabs: (Action(.shortcut, usage: 43, modifiers: [224, 225]), Action(.shortcut, usage: 43, modifiers: [224])),
            .thumbPages: (Action(.back), Action(.forward)),
            .thumbTracks: (Action(.previousTrack), Action(.nextTrack)),
            .thumbBrightness: (Action(.brightnessDown), Action(.brightnessUp)),
        ]
        guard let pair = pairs[mode] else { return }
        let action = forward ? pair.1 : pair.0
        perform(action); perform(action, down: false)
    }
    /// Same as Options+ screen_capture_handler (region, to file): `screencapture -i -tpng <file>`.
    private func screenshotRegion() {
        let saved = UserDefaults(suiteName:"com.apple.screencapture")?.string(forKey:"location").map { ($0 as NSString).expandingTildeInPath }
        let folder = saved ?? FileManager.default.urls(for:.desktopDirectory,in:.userDomainMask)[0].path
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let file = URL(fileURLWithPath:folder).appendingPathComponent("Screenshot \(format.string(from:Date())).png")
        let task = Process(); task.executableURL = URL(fileURLWithPath:"/usr/sbin/screencapture"); task.arguments = ["-i","-tpng",file.path]; task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { onError?("Screenshot failed: \(error.localizedDescription)") }
    }
    private func open(bundle: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle) else { onError?("\(bundle) is not installed"); return }
        NSWorkspace.shared.openApplication(at:url,configuration:NSWorkspace.OpenConfiguration())
    }
    private func scrollHorizontal(_ lines: Int32) {
        guard canPost, let e = CGEvent(scrollWheelEvent2Source:nil,units:.line,wheelCount:2,wheel1:0,wheel2:lines,wheel3:0) else { return }
        e.setIntegerValueField(.eventSourceUserData,value:ScrollEngine.marker); e.post(tap:.cghidEventTap)
    }
    /// Smart zoom is the double-tap gesture; apps receive it as a gesture event of HID type zoom-toggle at the pointer.
    private func smartZoom() {
        guard canPost, let event = CGEvent(source:nil), let type = CGEventField(rawValue:55), let hid = CGEventField(rawValue:110) else { onError?("Accessibility is required for smart zoom"); return }
        event.setIntegerValueField(type,value:29)
        event.setIntegerValueField(hid,value:22)
        event.setIntegerValueField(.eventSourceUserData,value:Self.injectionTag)
        event.post(tap:.cgSessionEventTap)
    }
    private func media(_ code: Int) {
        guard canPost else { onError?("Accessibility is required for media actions"); return }
        for down in [true,false] {
            let event = NSEvent.otherEvent(with:.systemDefined,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,subtype:8,data1:(code << 16) | (down ? 0xA00 : 0xB00),data2:-1)
            post(event?.cgEvent)
        }
    }
    private var savedInputVolume: [AudioDeviceID: Float32] = [:]
    private func inputProperty(_ selector: AudioObjectPropertySelector, element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput, mElement: element)
    }
    private func settable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: UInt32) -> Bool {
        var address = inputProperty(selector, element: element); var can: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address) && AudioObjectIsPropertySettable(device, &address, &can) == noErr && can.boolValue
    }
    private func readUInt32(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ element: UInt32) -> UInt32? {
        var address = inputProperty(selector, element: element); var value: UInt32 = 0; var size = UInt32(4)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    private func readFloat(_ device: AudioDeviceID, _ element: UInt32) -> Float32? {
        var address = inputProperty(kAudioDevicePropertyVolumeScalar, element: element); var value: Float32 = 0; var size = UInt32(4)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    /// Uses the hardware mute switch when the input device has one. Many USB and built-in microphones do not, so the
    /// fallback toggles the input volume between zero and the previously read level, with readback.
    private func microphoneMute() {
        var address = AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultInputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device) == noErr, device != 0 else { onError?("No default microphone"); return }
        let elements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        let muteElements = elements.filter { settable(device, kAudioDevicePropertyMute, $0) }
        if !muteElements.isEmpty {
            let current = readUInt32(device, kAudioDevicePropertyMute, muteElements[0]) ?? 0
            var target: UInt32 = current == 0 ? 1 : 0
            for element in muteElements {
                var a = inputProperty(kAudioDevicePropertyMute, element: element)
                guard AudioObjectSetPropertyData(device, &a, 0, nil, 4, &target) == noErr, readUInt32(device, kAudioDevicePropertyMute, element) == target else { onError?("Microphone mute write failed"); return }
            }
            onError?(target == 1 ? "Microphone muted" : "Microphone unmuted"); return
        }
        let volumeElements = elements.filter { settable(device, kAudioDevicePropertyVolumeScalar, $0) }
        guard let first = volumeElements.first, let level = readFloat(device, first) else {
            onError?("Default microphone exposes no writable mute or input volume"); return
        }
        var target: Float32
        if level > 0.001 { savedInputVolume[device] = level; target = 0 } else { target = savedInputVolume[device] ?? 0.75 }
        for element in volumeElements {
            var a = inputProperty(kAudioDevicePropertyVolumeScalar, element: element)
            guard AudioObjectSetPropertyData(device, &a, 0, nil, 4, &target) == noErr, let read = readFloat(device, element), abs(read - target) < 0.02 else { onError?("Microphone volume readback failed"); return }
        }
        onError?(target == 0 ? "Microphone muted (input volume 0)" : "Microphone unmuted")
    }
}
@MainActor final class InputController {
    private static let trace = ProcessInfo.processInfo.environment["LOGIMX_TRACE"] != nil
    let executor = ActionExecutor()
    var profile: Profile?
    var allowed: [Model:Set<UInt16>] = [:]
    private var transitions: [Model:ButtonTransitions] = [:]
    private var gesture = GestureMachine()
    private var held: [String:Action] = [:]
    private var repeats: [String:Task<Void,Never>] = [:]
    private var watchdogs: [String:Task<Void,Never>] = [:]
    var onStuckControl: ((Model, UInt16) -> Void)?
    private var gestureActions: [String:Action] = [:]
    func notification(_ model: Model, _ packet: Packet, snapshot: HardwareSnapshot) {
        guard packet.software == 0, snapshot.features[0x1B04]?.index == packet.feature else { return }
        if Self.trace {
            inputLog.info("event \(model.rawValue, privacy: .public) fn=\(packet.function) data=\(packet.parameters.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "), privacy: .public)")
        }
        guard !IsSecureEventInputEnabled(), AXIsProcessTrusted() else {
            // A release can arrive after secure input ends. Discard the held gesture
            // now so it cannot turn into a delayed click or shortcut later.
            cancel()
            inputLog.error("event dropped: secure input or accessibility")
            return
        }
        if packet.function == 1, model == .mouse, allowed[model]?.contains(195) == true, packet.parameters.count >= 4 {
            let p = packet.parameters
            if let dir = gesture.move(dx:Double(Int16(bitPattern:UInt16(p[0]) << 8 | UInt16(p[1]))),dy:Double(Int16(bitPattern:UInt16(p[2]) << 8 | UInt16(p[3]))),at:ProcessInfo.processInfo.systemUptime) {
                runGesture(dir)
            }
        }
        guard packet.function == 0 else { return }
        var state = transitions[model] ?? ButtonTransitions()
        guard let edges = try? state.update(packet.parameters) else { return }; transitions[model] = state
        for id in edges.down where allowed[model]?.contains(id) == true {
            let key = "\(model.rawValue).\(id)"
            watchdogs[key]?.cancel()
            watchdogs[key] = Task { [weak self] in
                // A lost BLE release must not keep the thumb gesture armed for
                // half a minute. Other held controls retain the longer drag limit.
                do { try await Task.sleep(for:.seconds(model == .mouse && id == 195 ? 8 : 30)) } catch { return }
                guard let self else { return }; self.cancel(); self.onStuckControl?(model, id)
            }
            if model == .mouse && id == 195 { gesture.press(at:ProcessInfo.processInfo.systemUptime); gestureActions = profile?.gestures ?? [:]; continue }
            let action = (model == .mouse ? profile?.mouse : profile?.keyboard)?["c\(id)"] ?? Action(.none)
            inputLog.info("press \(model.rawValue, privacy: .public) cid=\(id) action=\(action.kind.rawValue, privacy: .public)")
            held[key] = action; executor.perform(action)
            if let delay = action.repeatDelayMS, let interval = action.repeatIntervalMS, [.volumeDown,.volumeUp,.shortcut].contains(action.kind) {
                repeats[key]?.cancel()
                repeats[key] = Task { [weak self] in
                    do {
                        try await Task.sleep(for:.milliseconds(delay))
                        while !Task.isCancelled { guard let self, self.held[key] != nil, self.executor.canPost else { return }; self.executor.perform(action); try await Task.sleep(for:.milliseconds(interval)) }
                    } catch { }
                }
            }
        }
        for id in edges.up {
            let key = "\(model.rawValue).\(id)"; repeats.removeValue(forKey:key)?.cancel(); watchdogs.removeValue(forKey:key)?.cancel()
            if model == .mouse && id == 195 { inputLog.info("gesture release") }
            if model == .mouse && id == 195, let dir = gesture.release(at:ProcessInfo.processInfo.systemUptime) { runGesture(dir) }
            if let action = held.removeValue(forKey:key) { executor.perform(action,down:false) }
        }
    }
    private func runGesture(_ dir: GestureMachine.Direction) {
        guard let action = gestureActions[dir.rawValue] else { return }
        inputLog.info("gesture \(dir.rawValue, privacy: .public) action=\(action.kind.rawValue, privacy: .public)")
        executor.perform(action); executor.perform(action,down:false)
    }
    func cancel() {
        watchdogs.values.forEach { $0.cancel() }; watchdogs.removeAll()
        repeats.values.forEach { $0.cancel() }; repeats.removeAll(); held.removeAll(); transitions.removeAll(); gesture.cancel(); executor.releaseAll()
    }
}
