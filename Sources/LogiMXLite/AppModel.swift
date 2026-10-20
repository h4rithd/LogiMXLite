import SwiftUI
import AppKit
import ApplicationServices
import IOKit.hid
import ServiceManagement
import UniformTypeIdentifiers
import Carbon
import LogiCore

struct DeviceViewState {
    var connected = false
    var liveName: String?
    var status = "Disconnected"
    var snapshot = HardwareSnapshot()
}
@MainActor final class AppModel: ObservableObject {
    @Published var configuration: Configuration
    @Published var draft: Configuration
    @Published var selectedProfile: UUID
    @Published var activeProfile: UUID
    @Published var devices: [Model:DeviceViewState] = [.mouse:DeviceViewState(),.keyboard:DeviceViewState()]
    @Published var notice = "Loading local settings…"
    @Published var errorMessage: String?
    @Published var preview: ImportPreview?
    @Published var busy = false
    @Published var mappingEnabled = false
    @Published var inputAllowed = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published var accessibilityAllowed = AXIsProcessTrusted()
    @Published var conflicts: [String] = []
    @Published var diagnostics: [String] = []
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    /// Page the configuration window should jump to when opened from the menu-bar popover.
    @Published var requestedPage: SectionPage?
    /// App preference, not part of exported settings. Mappings still require every permission gate to pass.
    @Published var autoEnableMappings = UserDefaults.standard.object(forKey: "autoEnableMappings") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoEnableMappings, forKey: "autoEnableMappings"); if autoEnableMappings { autoEnableIfReady() } }
    }
    private let transport = IOHIDTransport()
    private let hardware: Hardware
    private let store: SettingsStore
    let input = InputController()
    private let scroll = ScrollEngine()
    private var observers: [NSObjectProtocol] = []
    private var profileTask: Task<Void,Never>?
    private var batteryTask: Task<Void,Never>?
    private var safetyTask: Task<Void,Never>?
    private var probes: [Model:Task<Void,Never>] = [:]
    private var revision = ProfileRevision()
    private var shuttingDown = false
    private var started = false
    private var mappingsRequested = false
    private var mappingRevision = 0
    private var mappingWorker: Task<Void,Never>?
    var showSettings: (() -> Void)?
    var quit: (() -> Void)?
    var onDeviceStatusChange: (() -> Void)?
    init() {
        let initial = try! ReferenceMigration.defaults()
        configuration = initial; draft = initial; selectedProfile = initial.desktop.id; activeProfile = initial.desktop.id
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LogiMXLite",isDirectory:true)
        store = SettingsStore(directory:directory); hardware = Hardware(transport:transport)
        scroll.onThumbStep = { [weak self] mode, forward in self?.input.executor.thumb(mode, forward: forward) }
        input.onStuckControl = { [weak self] model, id in
            guard let self else { return }
            if model == .mouse && id == 195 {
                self.softNotice("Gesture reset after a missing release; try again.")
            } else {
                Task {
                    await self.disableMappings()
                    self.softNotice("A held control timed out. Check the device before re-enabling mappings.")
                }
            }
        }
        input.executor.onError = { [weak self] in self?.softNotice($0) }
        input.executor.onHardwareAction = { [weak self] kind in
            guard let self else { return }
            if kind == .cycleDPI { self.cycleDPI() }
            else if kind == .wheelMode { self.applyWheel(mode:self.devices[.mouse]?.snapshot.wheelMode == 1 ? 2 : 1,threshold:255) }
            else if kind == .backlightUp || kind == .backlightDown { self.stepBacklight(kind == .backlightUp ? 1 : -1) }
            else if kind == .fnLockToggle, let current = self.devices[.keyboard]?.snapshot.fnInverted { self.applyFn(!current) }
        }
    }
    var selected: Profile { draft.profiles.first { $0.id == selectedProfile } ?? draft.desktop }
    var resolvedSelected: Profile { draft.resolved(selectedProfile) }
    var dirty: Bool { configuration != draft }
    var overall: String { let n = devices.values.filter(\.connected).count; return n == 2 ? "Both connected" : n == 1 ? "One connected" : "Disconnected" }
    var activeName: String { configuration.profiles.first { $0.id == activeProfile }?.name ?? "Desktop" }
    var theme: ColorScheme? {
        // `--theme light|dark` is a per-launch override for screenshots and testing; it is never saved.
        let flag = CommandLine.arguments.firstIndex(of: "--theme").flatMap { CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }
        switch flag ?? configuration.theme { case "dark": return .dark; case "light": return .light; default: return nil }
    }
    func start() {
        Task { [self] in
            do { let loaded = try await store.load(); configuration = loaded; draft = loaded; selectedProfile = loaded.desktop.id; notice = "Local settings loaded" }
            catch { report("Settings were not overwritten: \(error.localizedDescription)") }
            requestMissingPermissions(); started = true; startTransport(); activate()
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification,NSWorkspace.didTerminateApplicationNotification] {
                observers.append(center.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.activate(); self?.checkPermissions() } })
            }
            DistributedNotificationCenter.default().addObserver(forName:.init("SwipeScrollDirectionDidChangeNotification"),object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.activate() } }
            observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in await self?.suspend() } })
            observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in await self?.retry() } })
            batteryTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for:.seconds(300)) } catch { return }
                    guard let self, !self.shuttingDown else { return }
                    // Full read-only refresh is infrequent; vendor notifications update battery immediately.
                    for model in Model.allCases where self.devices[model]?.connected == true { self.probe(model) }
                }
            }
        }
    }
    private func startTransport() {
        checkPermissions()
        // The transport emits button edges and raw XY on one serial queue. Enqueue them
        // directly on the main queue so press, movement, and release keep that order;
        // separate unstructured Tasks can be scheduled out of order under UI load.
        transport.start { [weak self] event in
            DispatchQueue.main.async { self?.receive(event) }
        }
    }
    private func receive(_ event: DeviceEvent) {
        guard !shuttingDown else { return }
        switch event {
        case .connected(let model,let name): devices[model]?.connected = true; devices[model]?.liveName = name; devices[model]?.status = "Connected over BLE; probing access"; onDeviceStatusChange?()
        case .removed(let model):
            devices[model] = DeviceViewState(); probes.removeValue(forKey:model)?.cancel(); input.cancel()
            onDeviceStatusChange?()
            Task { await disableMappings(); await hardware.forget(model) }
        case .diagnosis(let model,let message):
            log(message)
            if let model { devices[model]?.status = message; if message.hasPrefix("Vendor report endpoint open") { probe(model) } }
            else { for m in Model.allCases { devices[m]?.status = message } }
        case .notification(let model,let packet):
            guard let snapshot = devices[model]?.snapshot else { return }
            if snapshot.features[0x1004]?.index == packet.feature, packet.function == 0,
               snapshot.battery != nil, packet.parameters.first ?? 255 <= 100 {
                devices[model]?.snapshot.battery = Int(packet.parameters[0])
                devices[model]?.snapshot.batteryStatus = BatteryStatus.parse(packet.parameters)
                onDeviceStatusChange?()
            }
            if mappingEnabled { input.notification(model,packet,snapshot:snapshot) }
        }
    }
    func probe(_ model: Model) {
        guard probes[model] == nil else { return }
        probes[model] = Task {
            defer { probes[model] = nil }
            do {
                let snapshot = try await hardware.probe(model)
                guard !Task.isCancelled else { return }
                devices[model]?.snapshot = snapshot
                onDeviceStatusChange?()
                await releaseStaleDiversion(model)
                devices[model]?.status = snapshot.issues.isEmpty ? "HID++ readback available; physical behavior unverified" : "Partial capabilities: \(snapshot.issues.joined(separator:"; "))"
                log("\(model.name): \(snapshot.features.count) features; \(snapshot.controls.count) controls")
                activate(); autoEnableIfReady()
            } catch { devices[model]?.status = "Read-only: \(error.localizedDescription)"; log("\(model.name): \(error.localizedDescription)") }
        }
    }
    /// A previous tool or run can leave Back, Forward or the gesture button diverted with nobody listening. When no other
    /// Logitech tool is running those controls are handed back to the device so native behavior returns.
    private func releaseStaleDiversion(_ model: Model) async {
        checkPermissions()
        guard conflicts.isEmpty else { return }
        let cleared = await hardware.clearStale(model)
        guard !cleared.isEmpty else { return }
        for id in cleared { if let i = devices[model]?.snapshot.controls.firstIndex(where: { $0.id == id }) { devices[model]?.snapshot.controls[i].reporting = 0 } }
        log("\(model.name): released leftover diversion on controls \(cleared)")
    }
    private func stepBacklight(_ delta: Int) {
        guard let state = devices[.keyboard]?.snapshot.backlight else { softNotice("Backlight state unavailable"); return }
        let target = max(0, min(state.levels - 1, state.level + delta))
        guard target != state.level else { return }
        applyBacklight(level: target)
    }
    /// Asks macOS once per launch so the app appears in the Privacy lists. No bypass is attempted.
    private func requestMissingPermissions() {
        checkPermissions()
        if !inputAllowed { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        if !accessibilityAllowed { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary) }
    }
    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true; configuration.arguments = ["--settings"]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.quit?() }
    }
    func autoEnableIfReady() {
        guard autoEnableMappings, !shuttingDown, !mappingEnabled else { return }
        guard PermissionGate.evaluate(input:inputAllowed,accessibility:accessibilityAllowed,secure:IsSecureEventInputEnabled(),conflicts:!conflicts.isEmpty) == .ready,
              devices.values.contains(where: { !$0.snapshot.controls.isEmpty }) else { return }
        Task { if mappingsRequested { await reconcileMappings() } else { await enableMappings() } }
    }
    func checkPermissions() {
        let wasAllowed = inputAllowed
        inputAllowed = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if inputAllowed && !wasAllowed && started { Task { await retry() } }
        let hadAccessibility = accessibilityAllowed
        accessibilityAllowed = AXIsProcessTrusted()
        if accessibilityAllowed != hadAccessibility && started { activate() }
        let hadConflicts = !conflicts.isEmpty
        conflicts = NSWorkspace.shared.runningApplications.compactMap { app in
            let b = (app.bundleIdentifier ?? "").lowercased()
            return ConflictDetector.matches(b) ? app.localizedName : nil
        }
        if mappingEnabled && (!inputAllowed || !accessibilityAllowed || !conflicts.isEmpty) { Task { await disableMappings() } }
        if hadConflicts && conflicts.isEmpty { autoEnableIfReady() }
    }
    func requestPermission(_ accessibility: Bool) {
        if accessibility { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt":true] as CFDictionary) }
        else { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        let page = accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?\(page)") { NSWorkspace.shared.open(url) }
    }
    func log(_ text: String) { inputLog.info("diag \(text, privacy: .private)"); diagnostics.append(text); if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count-100) } }
    /// Action-level problems (unsupported source action, window without a zoom button) must not raise a modal alert on every press.
    func softNotice(_ message: String) { notice = message; log(message); inputLog.error("\(message, privacy: .private)") }
    func report(_ message: String) { errorMessage = message; notice = message; log(message); inputLog.error("\(message, privacy: .private)") }
    func activate() {
        let p = configuration.selected(bundleID:NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        let changed = activeProfile != p.id
        if changed { input.cancel() }
        activeProfile = p.id; input.profile = configuration.resolved(p.id)
        let thumb = input.profile?.mouse["thumbWheel"].flatMap { $0.kind.isThumbMode || $0.kind == ActionKind.none ? $0.kind : nil }
        scroll.configure(accessibilityAllowed ? input.profile?.scroll : nil, thumbMode: accessibilityAllowed ? thumb : nil)
        if changed && mappingsRequested { Task { await reconcileMappings() } }
        profileTask?.cancel(); let token = revision.next()
        let hardwareProfile = configuration.resolved(configuration.switchHardwareWithApps ? p.id : configuration.desktop.id)
        profileTask = Task {
            do {
                try await Task.sleep(for:.milliseconds(200))
                guard revision.isCurrent(token) else { return }
                if let id = hardwareProfile.dpiPreset, let preset = configuration.dpiPresets.first(where: { $0.id == id }), devices[.mouse]?.snapshot.dpiRange != nil {
                    let value = try await hardware.setDPI(preset.dpi)
                    guard revision.isCurrent(token), !Task.isCancelled else { return }; devices[.mouse]?.snapshot.dpi = value
                }
                if let mode = hardwareProfile.wheelMode, devices[.mouse]?.snapshot.wheelMode != nil {
                    let result = try await hardware.setWheel(mode:mode,threshold:hardwareProfile.smartShiftThreshold ?? 255)
                    guard revision.isCurrent(token), !Task.isCancelled else { return }; devices[.mouse]?.snapshot.wheelMode = result.0; devices[.mouse]?.snapshot.threshold = result.1
                }
                if let keys = hardwareProfile.keyboardSettings {
                    if let fn = keys.fnInverted, devices[.keyboard]?.snapshot.fnInverted != nil {
                        let value = try await hardware.setFn(fn)
                        guard revision.isCurrent(token), !Task.isCancelled else { return }
                        devices[.keyboard]?.snapshot.fnInverted = value
                    }
                    if devices[.keyboard]?.snapshot.backlight != nil,
                       keys.backlightMode != nil || keys.brightness != nil || keys.durationSeconds != nil || keys.effect != nil {
                        let value = try await hardware.setBacklight(mode:keys.backlightMode,level:keys.brightness,seconds:keys.durationSeconds,effect:keys.effect)
                        guard revision.isCurrent(token), !Task.isCancelled else { return }
                        devices[.keyboard]?.snapshot.backlight = value
                    }
                }
            } catch is CancellationError { } catch { if revision.isCurrent(token) { softNotice("Profile hardware apply failed: \(error.localizedDescription)") } }
        }
    }
    func editProfile(id: UUID? = nil, _ body: (inout Profile) -> Void) { guard let i = draft.profiles.firstIndex(where: { $0.id == (id ?? selectedProfile) }) else { return }; body(&draft.profiles[i]) }
    func setAction(_ group: String, key: String, action: Action?) {
        editProfile { p in
            if group == "mouse" { p.mouse[key] = action }
            else if group == "keyboard" { p.keyboard[key] = action }
            else { p.gestures[key] = action }
        }
    }
    /// Draft-only reset. Desktop returns to the migrated source mappings; app profiles drop their overrides.
    func resetDevice(_ device: Model) {
        guard let defaults = try? ReferenceMigration.defaults() else { report("Default mappings are unavailable"); return }
        let source = defaults.desktop
        editProfile { p in
            if device == .mouse {
                p.mouse = p.isDefault ? source.mouse : [:]; p.gestures = p.isDefault ? source.gestures : [:]
                p.scroll = p.isDefault ? source.scroll : nil; p.wheelMode = p.isDefault ? source.wheelMode : nil
                p.smartShiftThreshold = p.isDefault ? source.smartShiftThreshold : nil; p.dpiPreset = nil
            } else {
                p.keyboard = p.isDefault ? source.keyboard : [:]; p.keyboardSettings = p.isDefault ? source.keyboardSettings : nil
            }
        }
        notice = "\(device.name) reset in the draft. Save to keep it."
    }
    func save() {
        guard !busy else { return }; busy = true; let candidate = draft
        Task {
            defer { busy = false }
            do {
                try await store.save(candidate)
                configuration = candidate; notice = "Settings saved locally"; activate()
                // Saving scroll speed or an action on an already-diverted control does
                // not require restoring every button and claiming it again.
                if mappingsRequested { await reconcileMappings() }
            }
            catch { report(error.localizedDescription) }
        }
    }
    func revert() {
        draft = configuration
        if !draft.profiles.contains(where: { $0.id == selectedProfile }) { selectedProfile = draft.desktop.id }
        previewScrollIfActive()
    }
    func previewScrollIfActive() {
        guard selectedProfile == activeProfile else { return }
        let profile = draft.resolved(activeProfile)
        let thumb = profile.mouse["thumbWheel"].flatMap { $0.kind.isThumbMode || $0.kind == .none ? $0.kind : nil }
        scroll.configure(accessibilityAllowed ? profile.scroll : nil, thumbMode: accessibilityAllowed ? thumb : nil)
    }
    func chooseApplication(associate: Bool) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, url.pathExtension == "app", let bundle = Bundle(url:url), let id = bundle.bundleIdentifier else { return }
        let name = (bundle.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent
        if associate && !selected.isDefault { editProfile { $0.bundleID = id } }
        else { let p = Profile(name:name,bundleID:id); draft.profiles.append(p); selectedProfile = p.id }
    }
    func duplicate() { var p = selected; p.id = UUID(); p.name += " copy"; p.bundleID = nil; p.isDefault = false; draft.profiles.append(p); selectedProfile = p.id }
    func deleteProfile() { guard !selected.isDefault else { return }; draft.profiles.removeAll { $0.id == selectedProfile }; selectedProfile = draft.desktop.id }
    func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "LogiMXLite-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let current = configuration
        Task { do { try await store.export(current,to:url); notice = "Saved settings exported" } catch { report(error.localizedDescription) } }
    }
    func importSettings() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; let current = configuration
        Task { defer { busy = false }; do { preview = try await store.preview(url,current:current); showSettings?() } catch { report(error.localizedDescription) } }
    }
    func importOptionsPlus() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        panel.message = "Choose the Logi Options+ settings.db file"
        panel.directoryURL = FileManager.default.urls(for:.downloadsDirectory,in:.userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; let current = configuration
        Task { defer { busy = false }; do { preview = try await store.previewOptionsPlus(url,current:current); showSettings?() } catch { report(error.localizedDescription) } }
    }
    func applyImport() {
        guard let candidate = preview, !busy else { return }; busy = true
        Task {
            defer { busy = false }
            do {
                await disableMappings()
                let new = try await store.commit(candidate,current:configuration)
                configuration = new; draft = new; selectedProfile = new.desktop.id; preview = nil; notice = "Import applied; pre-import backup saved"; activate()
            } catch { report(error.localizedDescription) }
        }
    }
    func backup() { let c = configuration; Task { do { try await store.backup(c); notice = "Manual backup saved locally" } catch { report(error.localizedDescription) } } }
    func restore() { let c = configuration; Task { do { preview = try await store.restorePreview(current:c); showSettings?() } catch { report(error.localizedDescription) } } }
    func reset() { do { let c = try ReferenceMigration.defaults(); preview = ImportPreview(configuration:c,changes:ConfigCodec.diff(configuration,c),baseline:configuration); showSettings?() } catch { report(error.localizedDescription) } }
    func applyDPI(_ value: Int) { Task { do { devices[.mouse]?.snapshot.dpi = try await hardware.setDPI(value); notice = "DPI \(value) confirmed by device" } catch { devices[.mouse]?.snapshot.dpi = nil; report(error.localizedDescription) } } }
    func cycleDPI() {
        let presets = configuration.dpiPresets.filter { devices[.mouse]?.snapshot.dpiRange?.supports($0.dpi) == true }
        guard !presets.isEmpty else { report("Create presets validated against the live DPI range first"); return }
        let i = presets.firstIndex { $0.dpi == devices[.mouse]?.snapshot.dpi } ?? -1
        applyDPI(presets[(i+1)%presets.count].dpi)
    }
    func applyWheel(mode: Int, threshold: Int) { Task { do { let v = try await hardware.setWheel(mode:mode,threshold:threshold); devices[.mouse]?.snapshot.wheelMode = v.0; devices[.mouse]?.snapshot.threshold = v.1; notice = "Wheel configuration confirmed" } catch { devices[.mouse]?.snapshot.wheelMode = nil; report(error.localizedDescription) } } }
    func applyFn(_ value: Bool) { let profileID = selectedProfile; Task { do { devices[.keyboard]?.snapshot.fnInverted = try await hardware.setFn(value); editProfile(id:profileID) { if $0.keyboardSettings == nil { $0.keyboardSettings = KeyboardSettings() }; $0.keyboardSettings?.fnInverted = value }; notice = "Fn inversion confirmed; Save to retain in profile" } catch { devices[.keyboard]?.snapshot.fnInverted = nil; report(error.localizedDescription) } } }
    func applyBacklight(mode: Int? = nil, level: Int? = nil, seconds: Int? = nil, effect: Int? = nil) {
        let profileID = selectedProfile
        Task { do { devices[.keyboard]?.snapshot.backlight = try await hardware.setBacklight(mode:mode,level:level,seconds:seconds,effect:effect); editProfile(id:profileID) { p in
            if p.keyboardSettings == nil { p.keyboardSettings = KeyboardSettings() }
            if let mode {p.keyboardSettings?.backlightMode = mode}; if let level {p.keyboardSettings?.brightness = level}
            if let seconds {p.keyboardSettings?.durationSeconds = seconds}; if let effect {p.keyboardSettings?.effect = effect}
        }; notice = "Backlight readback confirmed; Save to retain in profile" } catch { report(error.localizedDescription); probe(.keyboard) } }
    }
    func enableMappings() async {
        checkPermissions()
        guard PermissionGate.evaluate(input:inputAllowed,accessibility:accessibilityAllowed,secure:IsSecureEventInputEnabled(),conflicts:!conflicts.isEmpty) == .ready else { report("Mappings need Input Monitoring, Accessibility and no conflicting HID app"); return }
        mappingsRequested = true
        await reconcileMappings()
    }
    func disableMappings() async {
        mappingsRequested = false
        await reconcileMappings()
    }
    /// Controls to divert for the active profile: mapped, divertible, not left to the device's own function.
    private func desiredDiversion() -> [Model:Set<UInt16>] {
        let p = configuration.resolved(activeProfile)
        var result: [Model:Set<UInt16>] = [:]
        for model in Model.allCases {
            let mappings = model == .mouse ? p.mouse : p.keyboard
            let controls = devices[model]?.snapshot.controls ?? []
            var ids = Set(controls.filter { control in
                let a = mappings["c\(control.id)"]
                if let a, model == .keyboard, Self.nativeKeyboard[control.id] == a.kind { return false }
                return control.divertible && a != nil && a?.kind != .requiresConfirmation
            }.map(\.id))
            if model == .mouse, p.gestures.values.contains(where: { $0.kind != .requiresConfirmation }),
               controls.contains(where: { $0.id == 195 && $0.divertible && $0.rawXY }) { ids.insert(195) }
            result[model] = ids
        }
        return result
    }
    private static let nativeKeyboard: [UInt16: ActionKind] = [226: .backlightDown, 227: .backlightUp, 231: .mute, 232: .volumeDown, 233: .volumeUp]
    private func reconcileMappings() async {
        mappingRevision += 1
        if let worker = mappingWorker { await worker.value; return }
        let worker = Task { [self] in
            var processed = -1
            while processed != mappingRevision {
                processed = mappingRevision
                let requestedRevision = processed
                guard mappingsRequested else {
                    safetyTask?.cancel(); safetyTask = nil
                    input.cancel(); input.allowed = [:]; mappingEnabled = false
                    if !(await hardware.restore()) {
                        // BLE can be asleep during a readback. Retry once and keep the
                        // warning in the workspace instead of raising a startup modal.
                        try? await Task.sleep(for: .milliseconds(350))
                        if !(await hardware.restore()) {
                            softNotice("Button restoration was not confirmed. Wake or power-cycle the affected device if a control does not respond.")
                            break
                        }
                    }
                    if conflicts.isEmpty { for m in Model.allCases { _ = await hardware.clearStale(m) } }
                    continue
                }
                let desired = desiredDiversion()
                // App switches usually keep the same controls diverted; then nothing is written to the devices.
                if mappingEnabled && desired.filter({ !$0.value.isEmpty }) == input.allowed { continue }
                safetyTask?.cancel(); safetyTask = nil
                input.cancel(); mappingEnabled = false
                if conflicts.isEmpty { for m in Model.allCases { _ = await hardware.clearStale(m) } }
                do {
                    for model in Model.allCases {
                        guard requestedRevision == mappingRevision else { break }
                        try await hardware.setDiversion(model,ids:desired[model] ?? [])
                    }
                    guard requestedRevision == mappingRevision else { continue }
                    let enabled = desired.filter { !$0.value.isEmpty }
                    guard !enabled.isEmpty else { throw HIDError.unavailable("No verified divertible controls. Wake devices, grant permissions, then Retry.") }
                    input.allowed = enabled; mappingEnabled = true; notice = "Mappings active for \(activeName)"; log("mappings enabled: \(enabled.mapValues { $0.sorted() })")
                    safetyTask = Task { [weak self] in
                        while !Task.isCancelled {
                            do { try await Task.sleep(for:.seconds(2)) } catch { return }
                            guard let self else { return }
                            self.checkPermissions()
                            if !self.input.executor.canPost { await self.disableMappings(); return }
                        }
                    }
                } catch {
                    _ = await hardware.restore(); mappingsRequested = false; report(error.localizedDescription)
                }
            }
        }
        mappingWorker = worker
        await worker.value
        mappingWorker = nil
    }
    func suspend() async {
        profileTask?.cancel(); probes.values.forEach { $0.cancel() }; probes.removeAll()
        await disableMappings(); await transport.stop()
        for model in Model.allCases { devices[model] = DeviceViewState(); await hardware.forget(model) }
    }
    func retry() async { await suspend(); startTransport() }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginEnabled = SMAppService.mainApp.status == .enabled }
        catch { report("Launch at Login: \(error.localizedDescription)"); loginEnabled = SMAppService.mainApp.status == .enabled }
    }
    func shutdown() async {
        shuttingDown = true; batteryTask?.cancel(); profileTask?.cancel(); scroll.stop(); await suspend()
        for token in observers { NSWorkspace.shared.notificationCenter.removeObserver(token) }; observers.removeAll()
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "LogiMXLite-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let lines = ["LogiMXLite 1.0 local diagnostics", "Input Monitoring: \(inputAllowed); Accessibility: \(accessibilityAllowed)"] + Model.allCases.flatMap { m in
            [m.name,devices[m]?.status ?? "Unknown"] + (devices[m]?.snapshot.features.values.sorted { $0.id < $1.id }.map { String(format:"Feature %04X index %d version %d",$0.id,$0.index,$0.version) } ?? [])
        }
        Task.detached { do { try lines.joined(separator:"\n").write(to:url,atomically:true,encoding:.utf8) } catch { await MainActor.run { self.report(error.localizedDescription) } } }
    }
}
