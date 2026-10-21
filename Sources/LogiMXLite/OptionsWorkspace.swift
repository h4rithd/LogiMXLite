import AppKit
import SwiftUI
import ImageIO
import LogiCore

// MARK: - Style

enum Lite {
    /// Light/dark adaptive sRGB colour from two hex values.
    static func dyn(_ l: UInt32, _ d: UInt32, _ la: CGFloat = 1, _ da: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let dark = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let v = dark ? d : l
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: dark ? da : la)
        })
    }
    static let ink = dyn(0x1d1d1f, 0xffffff)
    static let content = dyn(0xffffff, 0x1e1e20)
    static let sidebar = dyn(0xf4f4f6, 0x252527)
    static let stage = dyn(0xf8f8f9, 0x19191b)
    static let page = dyn(0xf6f6f8, 0x1b1b1d)
    static let card = dyn(0xffffff, 0x2a2a2c)
    static let control = dyn(0xffffff, 0x3a3a3c)
    static let segOn = dyn(0xffffff, 0x636366)
    static let well = dyn(0xe9e9ec, 0x2c2c2e)
    static let hair = dyn(0x000000, 0xffffff, 0.09, 0.09)
    static let accent = dyn(0x6e6e73, 0x7c7c80)
    static let onAccent = Color.white
    static let green = Color(red: 0.204, green: 0.78, blue: 0.345)
    static let greenText = dyn(0x248a3d, 0x5ee07c)
    static let amber = dyn(0xc26b00, 0xffc354)
    static let red = dyn(0xd70015, 0xff8a80)
    static let effects = ["Static", "None", "Breathing", "Contrast", "Reaction", "Random", "Waves"]
}

extension View {
    /// Solid surface with a hairline edge (Liquid Glass removed from the configuration window).
    func liteGlass(_ radius: CGFloat, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 10), style: .continuous)
        return self.background(shape.fill(tint ?? Lite.card))
            .overlay(shape.strokeBorder(Lite.hair, lineWidth: tint == nil ? 1 : 0))
    }
    func liteCapsule(tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return self.background(shape.fill(tint ?? Lite.control))
            .overlay(shape.strokeBorder(Lite.hair, lineWidth: tint == nil ? 1 : 0))
    }
}

/// Keep decoded product art only while the configuration window is open. SwiftUI can
/// reevaluate a view body many times per second during edits and animations; decoding
/// a fresh NSImage there made closed-window memory grow with every visited page.
@MainActor private enum LiteImageCache {
    static var images: [String: NSImage] = [:]
    static func image(names: [String]) -> NSImage? {
        for name in names {
            if let image = images[name] { return image }
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { continue }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                // The keyboard can be 660 pt wide on a Retina display.
                kCGImageSourceThumbnailMaxPixelSize: 1400,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let image = NSImage(cgImage: bitmap, size: NSSize(width: bitmap.width, height: bitmap.height))
            images[name] = image
            return image
        }
        return nil
    }
    static func clear() { images.removeAll(keepingCapacity: false) }
}

/// Loads a bundled PNG, trying the redesign assets first, then the original renders.
struct LiteImage: View {
    let names: [String]
    var body: some View {
        if let image = LiteImageCache.image(names: names) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit().accessibilityHidden(true)
        } else { Color.clear }
    }
    static func clearWindowCache() { LiteImageCache.clear() }
    static let mouse = LiteImage(names: ["lite-mouse", "mx-master-3s-white", "mx-master-3s"])
    static let mouseRear = LiteImage(names: ["lite-mouse-rear", "mx-master-3s-rear-white"])
    static let keyboard = LiteImage(names: ["lite-keyboard", "mx-mechanical-mini-white", "mx-mechanical-mini"])
    static func of(_ m: Model) -> LiteImage { m == .mouse ? mouse : keyboard }
}

struct LiteBattery: View {
    let percent: Int?
    let connected: Bool
    let status: BatteryStatus?
    var body: some View {
        let p = percent ?? 0
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Lite.ink.opacity(0.5), lineWidth: 1).frame(width: 22, height: 11)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(p > 30 || status?.isCharging == true ? Lite.green : Color.red)
                    .frame(width: max(2, 18 * CGFloat(p) / 100), height: 7).padding(.leading, 2)
            }
            Text(connected ? (percent.map { "\($0)%" } ?? "—") : "Offline")
                .font(.system(size: 12).monospacedDigit())
            if connected && status?.isCharging == true { Image(systemName: "bolt.fill").foregroundStyle(Lite.greenText).help("Charging") }
            if connected && status == .full { Image(systemName: "checkmark.circle.fill").foregroundStyle(Lite.greenText).help("Charged") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(connected ? "Battery \(percent.map { "\($0) percent" } ?? "unknown")\(status?.isCharging == true ? ", charging" : status == .full ? ", charged" : "")" : "Device offline")
    }
}

struct LiteSegmented<T: Hashable>: View {
    let items: [(String, T)]
    let selection: T?
    var height: CGFloat = 28
    let pick: (T) -> Void
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let on = item.1 == selection
                Button { withAnimation(.smooth(duration: 0.25)) { pick(item.1) } } label: {
                    Text(item.0).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        .foregroundStyle(on ? Lite.ink : Lite.ink.opacity(0.62))
                        .frame(maxWidth: .infinity).frame(height: height)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Lite.segOn)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Lite.well))
    }
}

private struct Chip: View {
    let title: String
    var on = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(on ? Lite.onAccent : Lite.ink.opacity(0.85))
                .padding(.horizontal, 10).frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Lite.accent : Lite.ink.opacity(0.08)))
        }.buttonStyle(.plain)
    }
}

private struct GlassButton: View {
    let title: String
    var prominent = false
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: prominent ? .semibold : .regular))
                .foregroundStyle(prominent ? Lite.onAccent : destructive ? Lite.red : Lite.ink)
                .padding(.horizontal, 12).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(prominent ? Lite.accent : destructive ? Color.red.opacity(0.14) : Lite.ink.opacity(0.09)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(destructive ? Color.red.opacity(0.3) : Lite.ink.opacity(prominent ? 0 : 0.12), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }.buttonStyle(.plain)
    }
}

// MARK: - Callouts

private struct Callout: Identifiable {
    let id: String
    let title: String
    let value: String
    let dot: CGPoint
    let right: Bool
    let labelY: CGFloat
    var active = false
    var tap: (() -> Void)? = nil
}

private struct CalloutView: View {
    let c: Callout
    var body: some View {
        let anchor = CGPoint(x: c.right ? 532 : 168, y: c.labelY + 28)
        ZStack {
            Path { p in p.move(to: anchor); p.addLine(to: c.dot) }
                .stroke(c.active ? Lite.accent : Lite.ink.opacity(0.25), lineWidth: 1)
                .allowsHitTesting(false)
            Circle().fill(c.active ? Lite.accent : Lite.content)
                .frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(c.active ? Lite.accent : Lite.ink.opacity(0.4), lineWidth: 1.5))
                .position(c.dot)
                .onTapGesture { c.tap?() }
            Button { c.tap?() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.system(size: 12, weight: .semibold))
                    Text(c.value).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(c.active ? Lite.onAccent.opacity(0.75) : Lite.ink.opacity(0.6))
                }
                .foregroundStyle(c.active ? Lite.onAccent : Lite.ink)
                .padding(.horizontal, 14)
                .frame(width: 168, height: 46, alignment: .leading)
                .liteGlass(8, tint: c.active ? Lite.accent : Lite.control)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Lite.hair, lineWidth: c.active ? 0 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(c.tap == nil)
            .position(x: c.right ? 532 + 84 : 84, y: c.labelY + 28)
            .accessibilityLabel("\(c.title), \(c.value)")
        }
        .frame(width: 700, height: 560)
        .animation(.smooth(duration: 0.2), value: c.active)
    }
}

// MARK: - Workspace

private enum DeviceTab: String, Identifiable {
    case buttons = "Buttons", point = "Point & Scroll", keys = "Keys", light = "Backlighting", easySwitch = "Easy-Switch", settings = "Settings"
    var id: String { rawValue }
}

private struct ShortcutTarget: Identifiable {
    let group: String
    let key: String
    var id: String { group + key }
}

/// Configuration window. Every control reads and writes through AppModel,
/// keeping its permission gates, verified HID++ readback and draft/save semantics.
struct OptionsWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var page: SectionPage
    @State private var tab: DeviceTab
    @State private var mouseControl = "c82"
    @State private var gestureDirection = "click"
    @State private var keyboardControl = "c212"
    @State private var search = ""
    @State private var showingDPIPresets = false
    @State private var pendingDPI: Double?
    @State private var shortcutTarget: ShortcutTarget?
    @State private var pointFocus: String?
    @State private var edges = ScrollEdges()
    @State private var pageEdges = ScrollEdges()
    @Namespace private var tabNS

    init(model: AppModel, initialPage: SectionPage) {
        self.model = model
        _page = State(initialValue: initialPage)
        _tab = State(initialValue: initialPage == .keyboard ? .keys : .buttons)
    }

    private var isDevice: Bool { page == .mouse || page == .keyboard }
    private var device: Model { page == .keyboard ? .keyboard : .mouse }
    private func fullName(_ m: Model) -> String { m == .mouse ? "MX Master 3S for Mac" : "MX Mechanical Mini for Mac" }
    private func shortName(_ m: Model) -> String { m == .mouse ? "MX Master 3S" : "MX Mechanical Mini" }
    private var snapshot: HardwareSnapshot? { model.devices[device]?.snapshot }

    var body: some View {
        ZStack {
            backdrop
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    toolbar.frame(height: 52).frame(maxWidth: .infinity).background(Lite.content).overlay(alignment: .bottom) { Rectangle().fill(Lite.hair).frame(height: 1) }.zIndex(2)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .bottom) {
                    if model.dirty { saveBar.padding(.bottom, 22).transition(.scale(scale: 0.96).combined(with: .opacity)) }
                }
            }
            .ignoresSafeArea()
            if showingDPIPresets {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture { showingDPIPresets = false }
                    .transition(.opacity)
                LiteDPIEditor(model: model) { showingDPIPresets = false }
                    .liteGlass(26)
                    .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.25), value: showingDPIPresets)
        .animation(.smooth(duration: 0.25), value: model.dirty)
        .foregroundStyle(Lite.ink)
        .font(.system(size: 13))
        .onChange(of: page) { _, new in
            tab = new == .keyboard ? .keys : .buttons
            search = ""
        }
        .onAppear { consumeRequestedPage() }
        .onChange(of: model.requestedPage) { _, _ in consumeRequestedPage() }
        .sheet(item: $shortcutTarget) { target in
            ShortcutEditor { action in
                model.setAction(target.group, key: target.key, action: action); shortcutTarget = nil
            } cancel: { shortcutTarget = nil }
        }
    }

    private func consumeRequestedPage() {
        guard let p = model.requestedPage else { return }
        page = p
        model.requestedPage = nil
    }

    private var backdrop: some View { Lite.content.ignoresSafeArea() }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            navRow("Overview", symbol: "square.grid.2x2", on: page == .devices) { page = .devices }
            sectionLabel("Devices").padding(.top, 12)
            ForEach(Model.allCases) { m in deviceRow(m) }
            sectionLabel("App").padding(.top, 12)
            navRow("Profiles", symbol: "person.2.crop.square.stack", on: page == .profiles) { page = .profiles }
            navRow("Export / Import", symbol: "arrow.up.arrow.down.square", on: page == .backup) { page = .backup }
            navRow("Settings", symbol: "gearshape", on: page == .general) { page = .general }
            navRow("About", symbol: "info.circle", on: page == .about) { page = .about }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if !model.notice.isEmpty {
                    Text(model.notice).font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.55))
                        .lineLimit(1).truncationMode(.tail).help(model.notice)
                }
                addDeviceButton.frame(maxWidth: .infinity)
            }
            .padding(.top, 12).padding(.horizontal, 6)
            .overlay(alignment: .top) { Rectangle().fill(Lite.hair).frame(height: 1).padding(.horizontal, -10) }
        }
        .padding(.horizontal, 10).padding(.top, 52).padding(.bottom, 14)
        .frame(width: 220).frame(maxHeight: .infinity)
        .background(Lite.sidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Lite.hair).frame(width: 1) }
    }

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45)).padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func navRow(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(Lite.ink.opacity(0.7))
                Text(title)
                Spacer(minLength: 0)
            }
                .padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Lite.ink.opacity(0.08) : Color.clear))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }

    private func deviceRow(_ m: Model) -> some View {
        let state = model.devices[m]
        let on = page == (m == .mouse ? .mouse : .keyboard)
        let online = state?.connected == true
        return Button { page = m == .mouse ? .mouse : .keyboard } label: {
            HStack(spacing: 10) {
                Image(systemName: m == .mouse ? "computermouse" : "keyboard")
                    .font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(Lite.ink.opacity(online ? 0.7 : 0.35))
                Text(shortName(m)).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(online ? (state?.snapshot.battery.map { "\($0)%\(state?.snapshot.batteryStatus?.isCharging == true ? " ⚡" : "")" } ?? "—") : "Off")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(Lite.ink.opacity(0.5))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Lite.ink.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Configure \(m.name)")
    }

    private var addDeviceButton: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") { NSWorkspace.shared.open(url) }
        } label: {
            Text("Add Device…").font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12).frame(height: 26).frame(maxWidth: .infinity)
                .liteCapsule()
        }.buttonStyle(.plain).help("Open macOS Bluetooth settings to pair a device")
    }

    // MARK: Toolbar

    @ViewBuilder private var toolbar: some View {
        if isDevice {
            ZStack {
                tabBar
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.devices[device]?.liveName ?? fullName(device)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(model.devices[device]?.connected == true ? Lite.green : Color.gray).frame(width: 6, height: 6)
                            Text(model.devices[device]?.connected == true ? "Connected · Bluetooth" : "Offline")
                        }.font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.55))
                    }.frame(width: 240, alignment: .leading)
                    Spacer()
                    LiteBattery(percent: snapshot?.battery, connected: model.devices[device]?.connected == true,
                                status: snapshot?.batteryStatus)
                        .foregroundStyle(Lite.ink.opacity(0.6)).padding(.horizontal, 6)
                    profileMenu
                }
            }.padding(.leading, 20).padding(.trailing, 14)
        } else {
            HStack {
                if page != .devices { Text(page == .general ? "Settings" : page.rawValue).font(.system(size: 13, weight: .semibold)) }
                Spacer()
                if page == .devices { addDeviceButton.fixedSize() }
            }.padding(.horizontal, 20)
        }
    }

    private var tabBar: some View {
        let tabs: [DeviceTab] = device == .mouse ? [.buttons, .point, .easySwitch, .settings] : [.keys, .light, .easySwitch, .settings]
        return HStack(spacing: 0) {
            ForEach(tabs) { t in
                let on = tab == t
                Button { withAnimation(.smooth(duration: 0.2)) { tab = t } } label: {
                    Text(t.rawValue).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? Lite.ink : Lite.ink.opacity(0.6))
                        .padding(.horizontal, 14).frame(height: 22)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Lite.segOn)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                                    .matchedGeometryEffect(id: "tab", in: tabNS)
                            }
                        }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Lite.well))
    }

    private var profileMenu: some View {
        Menu {
            Section("App profiles") {
                ForEach(model.draft.profiles) { profile in
                    Button { model.selectedProfile = profile.id } label: {
                        if profile.id == model.selectedProfile { Label(profile.name, systemImage: "checkmark") } else { Text(profile.name) }
                    }
                }
            }
            Divider()
            Button("Add app profile…") { model.chooseApplication(associate: false) }
            Button("Manage profiles…") { page = .profiles }
        } label: {
            HStack(spacing: 6) {
                Text(model.selected.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.55))
            }
            .padding(.horizontal, 10).frame(height: 24)
            .liteCapsule()
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Application profile being edited")
    }

    // MARK: Content routing

    @ViewBuilder private var content: some View {
        if page == .devices { home }
        else if isDevice {
            switch tab {
            case .settings: FadeScroll(edges: $pageEdges) { settingsContent(device).padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 110) }
            default:
                HStack(spacing: 0) {
                    stage.frame(width: 700, height: 560).frame(maxWidth: .infinity, maxHeight: .infinity).background(Lite.stage)
                    inspectorContent
                }
            }
        } else {
            if page == .profiles {
                ProfilesView(model: model)
            } else {
            FadeScroll(edges: $pageEdges) {
                VStack(alignment: .leading, spacing: 18) {
                    switch page {
                    case .profiles:
                        ProfilesView(model: model)
                    case .general: settingsContent(nil)
                    case .backup: BackupView(model: model)
                    default: AboutView(model: model)
                    }
                }
                .frame(maxWidth: page == .profiles ? 980 : 760, alignment: .leading).frame(maxWidth: .infinity)
                .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 110)
            }
            .background(Lite.page)
            }
        }
    }

    // MARK: Overview

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    private func facts(_ m: Model) -> [(String, String)] {
        let snap = model.devices[m]?.snapshot
        if m == .mouse {
            let smart: String = snap?.wheelMode.map { $0 == 1 ? "Free-spin" : (snap?.threshold ?? 255) >= 255 ? "Ratchet" : "Auto" } ?? "—"
            return [("Pointer speed", snap?.dpi.map { "\($0.formatted()) DPI" } ?? "—"), ("SmartShift", smart), ("Easy-Switch", "This Mac")]
        }
        let light: String = snap?.backlight.map { b in b.enabled ? "\(b.mode == 1 ? "Automatic" : "Manual") · level \(b.level)" : "Off" } ?? "—"
        let fn: String = snap?.fnInverted.map { $0 ? "Inverted" : "Standard" } ?? "—"
        return [("Backlighting", light), ("Function keys", fn), ("Easy-Switch", "This Mac")]
    }

    private func statusRow(_ title: String, ok: Bool, value: String, divider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(ok ? Lite.green : Lite.amber).frame(width: 6, height: 6)
                    Text(value).foregroundStyle(Lite.ink.opacity(0.6))
                }
            }
            .padding(.horizontal, 14).frame(height: 40)
            if divider { Rectangle().fill(Lite.hair).frame(height: 1) }
        }
    }

    private var home: some View {
        let connected = model.devices.values.filter(\.connected).count
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(greeting).font(.system(size: 22, weight: .semibold)).kerning(-0.3)
                        Text("\(connected) \(connected == 1 ? "device" : "devices") connected · Profile: \(model.activeName)")
                            .font(.system(size: 12)).foregroundStyle(Lite.ink.opacity(0.55))
                    }
                    Spacer()
                    HStack(spacing: 7) {
                        Circle().fill(model.mappingEnabled ? Lite.green : Lite.amber).frame(width: 6, height: 6)
                        Text(model.mappingEnabled ? "Mappings active" : "Mappings off").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(model.mappingEnabled ? Lite.greenText : Lite.amber)
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill((model.mappingEnabled ? Lite.green : Lite.amber).opacity(0.13)))
                }
                .padding(.horizontal, 2)

                HStack(alignment: .top, spacing: 16) {
                    ForEach(Model.allCases) { m in
                        HomeCard(name: shortName(m), model: m,
                                 battery: model.devices[m]?.snapshot.battery, batteryStatus: model.devices[m]?.snapshot.batteryStatus,
                                 connected: model.devices[m]?.connected == true,
                                 facts: facts(m),
                                 links: m == .mouse ? [("Buttons", DeviceTab.buttons), ("Point & Scroll", .point)] : [("Keys", .keys), ("Backlighting", .light)],
                                 open: { t in page = m == .mouse ? .mouse : .keyboard; if let t { DispatchQueue.main.async { tab = t } } })
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status").font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45)).padding(.leading, 12)
                    VStack(spacing: 0) {
                        statusRow("Input Monitoring", ok: model.inputAllowed, value: model.inputAllowed ? "Granted" : "Not granted")
                        statusRow("Accessibility", ok: model.accessibilityAllowed, value: model.accessibilityAllowed ? "Granted" : "Not granted")
                        statusRow("App profile switching", ok: model.draft.switchHardwareWithApps,
                                  value: model.draft.switchHardwareWithApps ? "On · \(model.activeName) active" : "Off", divider: false)
                    }
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Lite.card))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Lite.hair, lineWidth: 1))
                }
            }
            .frame(maxWidth: 1040).frame(maxWidth: .infinity)
            .padding(.horizontal, 32).padding(.top, 28).padding(.bottom, 40)
        }
        .scrollIndicators(.never)
        .background(Lite.page)
    }

    // MARK: Stage

    @ViewBuilder private var stage: some View {
        ZStack {
            switch (device, tab) {
            case (.mouse, .easySwitch):
                floorShadow(x: 350, y: 525, w: 260)
                LiteImage.mouseRear.frame(width: 330, height: 480).shadow(color: .black.opacity(0.12), radius: 10, y: 6).position(x: 350, y: 280)
                CalloutView(c: Callout(id: "es", title: "Easy-Switch", value: "Press to change computer", dot: CGPoint(x: 312, y: 281), right: true, labelY: 253, active: true))
            case (.mouse, _):
                floorShadow(x: 350, y: 540, w: 250)
                LiteImage.mouse.frame(width: 320, height: 520).shadow(color: .black.opacity(0.12), radius: 10, y: 6).position(x: 350, y: 280)
                ForEach(mouseCallouts) { CalloutView(c: $0) }
            default:
                keyboardStage
            }
        }
        .frame(width: 700, height: 560)
    }

    private func floorShadow(x: CGFloat, y: CGFloat, w: CGFloat) -> some View {
        Ellipse().fill(.black.opacity(0.14)).frame(width: w, height: 24).blur(radius: 18).position(x: x, y: y)
    }

    private static let mouseControls: [(id: String, title: String, dot: CGPoint, right: Bool, y: CGFloat)] = [
        ("c82", "Wheel button", CGPoint(x: 402, y: 113), true, 70),
        ("c196", "Top button", CGPoint(x: 441, y: 208), true, 190),
        ("c86", "Forward button", CGPoint(x: 305, y: 230), false, 140),
        ("thumbWheel", "Thumb wheel", CGPoint(x: 349, y: 254), false, 228),
        ("c83", "Back button", CGPoint(x: 318, y: 283), false, 316),
        ("click", "Gesture button", CGPoint(x: 240, y: 357), false, 404)
    ]

    private var mouseCallouts: [Callout] {
        if tab == .point {
            let s = model.resolvedSelected.scroll ?? ScrollSettings()
            return [
                Callout(id: "scroll", title: "Scroll wheel", value: "Speed \(speed(s.verticalScale)) · \(s.natural ? "Natural" : "Standard")", dot: CGPoint(x: 402, y: 113), right: true, labelY: 80,
                        active: pointFocus == "scroll", tap: { pointFocus = "scroll" }),
                Callout(id: "pointer", title: "Pointer speed", value: snapshot?.dpi.map { "\($0) DPI" } ?? "DPI unavailable", dot: CGPoint(x: 424, y: 388), right: true, labelY: 380,
                        active: pointFocus == "pointer", tap: { pointFocus = "pointer" }),
                Callout(id: "thumb", title: "Thumb wheel", value: "Speed \(speed(s.horizontalScale))", dot: CGPoint(x: 349, y: 254), right: false, labelY: 230,
                        active: pointFocus == "thumb", tap: { pointFocus = "thumb" })
            ]
        }
        return Self.mouseControls.map { c in
            Callout(id: c.id, title: c.title, value: actionLabel(c.id), dot: c.dot, right: c.right, labelY: c.y,
                    active: mouseControl == c.id, tap: { mouseControl = c.id; search = "" })
        }
    }

    // Keyboard image: 660pt wide at (20,150). Key centres from the 1340pt-wide render.
    private static let kScale: CGFloat = 660.0 / 1340.0
    private static func topKey(_ i: Int) -> CGPoint { CGPoint(x: 20 + (50 + 82.6 * CGFloat(i)) * kScale, y: 150 + 98 * kScale) }
    private static let keyCentres: [String: CGPoint] = {
        var map: [String: CGPoint] = [:]
        let top = ["c226", "c227", "c259", "c264", "c266", "c284", "c212", "c321", "c231", "c232", "c233", "c285"]
        for (i, id) in top.enumerated() { map[id] = topKey(i + 4) }
        for (i, id) in ["c280", "c281", "c282", "c283"].enumerated() {
            map[id] = CGPoint(x: 20 + 1288 * kScale, y: 150 + [180, 262, 345, 427][i] * kScale)
        }
        return map
    }()

    private var keyboardStage: some View {
        let backlight = model.devices[.keyboard]?.snapshot.backlight
        let glow: Double = {
            guard tab == .light, let b = backlight, b.enabled else { return 0 }
            return 0.15 + Double(b.level) / Double(max(b.levels - 1, 1)) * 0.5
        }()
        return ZStack {
            RoundedRectangle(cornerRadius: 30).fill(RadialGradient(colors: [Lite.ink.opacity(0.9), Color(red: 0.63, green: 0.94, blue: 0.9).opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 660, height: 280).blur(radius: 40).opacity(glow).position(x: 350, y: 290)
                .animation(.easeInOut(duration: 0.4), value: glow)
            floorShadow(x: 350, y: 440, w: 540)
            LiteImage.keyboard.frame(width: 660, height: 280).shadow(color: .black.opacity(0.12), radius: 10, y: 6).position(x: 350, y: 290)
            if tab == .keys {
                ForEach(KeyboardView.keys) { key in
                    if let c = Self.keyCentres[key.id] { keyRing(c, on: keyboardControl == key.id) { keyboardControl = key.id; search = "" }.help(key.name) }
                }
                if let c = Self.keyCentres[keyboardControl] {
                    badge("\(keyName(keyboardControl)) · \(model.resolvedSelected.keyboard[keyboardControl]?.displayLabel ?? "Native")", prominent: true)
                        .position(x: min(max(c.x, 110), 590), y: c.y - 52)
                }
                hint("Select a key on the keyboard to edit its assignment.")
            } else if tab == .easySwitch {
                ForEach(1...3, id: \.self) { i in keyRing(Self.topKey(i), on: true, action: nil) }
                badge("Easy-Switch keys · F1–F3", prominent: false).position(x: Self.topKey(2).x, y: 112)
                hint("Hold a channel key for 3 seconds to pair a new computer.")
            } else {
                HStack(spacing: 12) {
                    badge(backlight.map { $0.enabled ? "Backlighting · \($0.duration)s · level \($0.level)" : "Backlighting · Off" } ?? "Backlight readback unavailable", prominent: false)
                    badge("Effect · \(backlight.map { Lite.effects.indices.contains($0.effect) ? Lite.effects[$0.effect] : "Effect \($0.effect)" } ?? "—")", prominent: false)
                }.position(x: 350, y: 112)
            }
        }
    }

    private func keyRing(_ c: CGPoint, on: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            KeyRing(on: on, fixed: action == nil)
        }
        .buttonStyle(.plain).disabled(action == nil)
        .position(c)
        .animation(.smooth(duration: 0.2), value: on)
    }

    private func badge(_ text: String, prominent: Bool) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            .foregroundStyle(prominent ? Lite.onAccent : Lite.ink)
            .padding(.horizontal, 12).frame(height: 30)
            .liteCapsule(tint: prominent ? Lite.accent : nil)
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(Lite.ink.opacity(0.5)).position(x: 350, y: 490)
    }

    // MARK: Inspector

    /// Pinned header, fading scroll body, pinned footer. Used by every inspector.
    private func inspector<H: View, C: View>(footer: String? = nil, @ViewBuilder header: () -> H, @ViewBuilder content: () -> C) -> some View {
        let h = header()
        let c = content()
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) { h }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Lite.ink.opacity(0.1)).frame(height: 1).padding(.horizontal, 16).opacity(edges.top ? 1 : 0)
                }
            FadeScroll(target: pointFocus, edges: $edges) {
                VStack(alignment: .leading, spacing: 16) { c }
                    .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4).padding(.top, 12).padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Lite.ink.opacity(0.08)).frame(height: 1) }
                    .padding(.horizontal, 16)
            }
        }
        .frame(width: 320).frame(maxHeight: .infinity)
        .background(Lite.content)
        .overlay(alignment: .leading) { Rectangle().fill(Lite.hair).frame(width: 1) }
    }

    private func headerRow(symbol: String, label: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45)).lineLimit(1)
            Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var inspectorContent: some View {
        switch tab {
        case .buttons: buttonsInspector
        case .point: pointInspector
        case .keys: keysInspector
        case .light: lightInspector
        default: easySwitchInspector
        }
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
    }
    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45))
    }
    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { c() }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Lite.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Lite.ink.opacity(0.07), lineWidth: 1))
    }
    private func focusCard<C: View>(_ id: String, @ViewBuilder _ c: () -> C) -> some View {
        let on = pointFocus == id
        return VStack(alignment: .leading, spacing: 10) { c() }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Lite.accent.opacity(0.1) : Lite.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Lite.accent.opacity(0.7) : Lite.ink.opacity(0.07), lineWidth: 1))
            .animation(.smooth(duration: 0.2), value: on)
            .id(id)
    }
    private func title(_ s: String) -> some View { Text(s).font(.system(size: 22, weight: .bold)) }
    private func warning(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Lite.amber)
            Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(Lite.amber).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Lite.amber.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Lite.amber.opacity(0.3), lineWidth: 1))
    }

    private func mouseTitle(_ key: String) -> String {
        Self.mouseControls.first { $0.id == key }?.title ?? "Button"
    }
    private func actionLabel(_ key: String) -> String {
        let action = key == "click" ? model.resolvedSelected.gestures["click"] : model.resolvedSelected.mouse[key]
        return action?.displayLabel ?? "Native"
    }
    private func keyName(_ id: String) -> String { KeyboardView.keys.first { $0.id == id }?.name ?? "Key" }

    @ViewBuilder private var mappingStatus: some View {
        if !model.mappingEnabled {
            let d = model.devices[device]
            warning(d?.connected != true
                    ? "\(device.name) offline. Select this Mac with Easy-Switch and wake the device."
                    : !model.conflicts.isEmpty
                    ? "Mappings paused: quit \(model.conflicts.joined(separator: ", ")) to use buttons and gestures."
                    : "Mappings inactive. Check Settings for device access and enable mappings.")
        }
    }

    private func controlSymbol(_ id: String) -> String {
        ["c82": "circle.circle", "c196": "square.on.square", "c86": "arrow.right.circle", "c83": "arrow.left.circle",
         "thumbWheel": "dial.low", "click": "hand.point.up.left"][id] ?? "computermouse"
    }

    private var buttonsInspector: some View {
        let isGesture = mouseControl == "click"
        let group = isGesture ? "gestures" : "mouse"
        let key = isGesture ? gestureDirection : mouseControl
        let current = isGesture ? model.resolvedSelected.gestures[gestureDirection] : model.resolvedSelected.mouse[mouseControl]
        return inspector(footer: "Primary left and right clicks remain native.") {
            headerRow(symbol: controlSymbol(mouseControl),
                      label: isGesture ? "Gesture · \(gestureDirection.capitalized)" : mouseTitle(mouseControl),
                      title: current?.displayLabel ?? "Native")
            SearchField(text: $search)
        } content: {
            mappingStatus
            if isGesture {
                VStack(alignment: .leading, spacing: 8) {
                    label("Hold the gesture button and move").padding(.leading, 10)
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { Color.clear.frame(height: 52); gestureCell("up"); Color.clear.frame(height: 52) }
                        HStack(spacing: 6) { gestureCell("left"); gestureCell("click"); gestureCell("right") }
                        HStack(spacing: 6) { Color.clear.frame(height: 52); gestureCell("down"); Color.clear.frame(height: 52) }
                    }
                }
            }
            ActionList(model: model, group: group, key: key, search: search) { shortcutTarget = ShortcutTarget(group: group, key: key) }
        }
    }

    private func gestureCell(_ dir: String) -> some View {
        let on = gestureDirection == dir
        return Button { withAnimation(.smooth(duration: 0.2)) { gestureDirection = dir } } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(dir.capitalized).font(.system(size: 10, weight: .semibold)).foregroundStyle(on ? Lite.onAccent.opacity(0.7) : Lite.ink.opacity(0.45))
                Text(model.resolvedSelected.gestures[dir]?.displayLabel ?? "Native").font(.system(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(on ? Lite.onAccent : Lite.ink)
            }
            .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Lite.accent : Lite.ink.opacity(0.06)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // Point & Scroll

    private func speed(_ scale: Double) -> String { "\(OptionsPlusImport.sliderPercent(scale))%" }
    private func setScroll(_ change: (inout ScrollSettings) -> Void) {
        let base = model.resolvedSelected.scroll ?? ScrollSettings()
        model.editProfile { profile in
            var scroll = profile.scroll ?? base
            change(&scroll)
            profile.scroll = scroll
        }
        model.previewScrollIfActive()
    }
    private func scrollBinding(_ key: WritableKeyPath<ScrollSettings, Bool>) -> Binding<Bool> {
        Binding(get: { (model.resolvedSelected.scroll ?? ScrollSettings())[keyPath: key] },
                set: { value in setScroll { $0[keyPath: key] = value } })
    }
    private func speedSlider(_ keyPath: WritableKeyPath<ScrollSettings, Double>) -> some View {
        let value = (model.resolvedSelected.scroll ?? ScrollSettings())[keyPath: keyPath]
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Speed"); Spacer(); Text(speed(value)).monospacedDigit().foregroundStyle(Lite.ink.opacity(0.6)) }
            Slider(value: Binding(
                get: { log(max(0.25, min(4, (model.resolvedSelected.scroll ?? ScrollSettings())[keyPath: keyPath]))) / log(4) },
                set: { newValue in setScroll { $0[keyPath: keyPath] = pow(4, newValue) } }
            ), in: -1...1).tint(Lite.accent)
        }
    }
    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Text(title) }.toggleStyle(.switch).tint(Lite.green).controlSize(.small)
    }

    private var pointInspector: some View {
        let snap = model.devices[.mouse]?.snapshot
        let smartSelection: String? = snap?.wheelMode.map { mode in mode == 1 ? "free" : (snap?.threshold ?? 255) >= 255 ? "ratchet" : "auto" }
        return inspector(footer: "Scroll settings apply through macOS when mappings are active. Trackpads are never changed.") {
            headerRow(symbol: "computermouse", label: "MX Master 3S", title: "Point & Scroll")
        } content: {
            focusCard("pointer") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Pointer speed").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text((pendingDPI.map { Int($0) } ?? snap?.dpi).map { "\($0)" } ?? "—").font(.system(size: 20, weight: .bold).monospacedDigit())
                    Text("DPI").font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.5))
                }
                if let range = snap?.dpiRange, let current = snap?.dpi, let lo = range.values.first, let hi = range.values.last, hi > lo {
                    Slider(value: Binding(get: { pendingDPI ?? Double(current) }, set: { pendingDPI = $0 }),
                           in: Double(lo)...Double(hi),
                           onEditingChanged: { editing in
                               if !editing, let pendingDPI,
                                  let nearest = range.values.min(by: { abs(Double($0) - pendingDPI) < abs(Double($1) - pendingDPI) }) {
                                   model.applyDPI(nearest)
                                   self.pendingDPI = nil
                               }
                           }).tint(Lite.green)
                    caption("Selects a supported device DPI when released.")
                } else {
                    caption("Hardware DPI range has not been read yet.")
                }
                HStack(spacing: 6) {
                    ForEach(model.draft.dpiPresets) { preset in
                        Chip(title: "\(preset.dpi)", on: snap?.dpi == preset.dpi) { model.applyDPI(preset.dpi) }
                            .disabled(snap?.dpiRange.map { !$0.supports(preset.dpi) } ?? false)
                            .help("\(preset.name) · click to apply")
                    }
                    Chip(title: model.draft.dpiPresets.isEmpty ? "Add presets…" : "Edit…") { showingDPIPresets = true }
                }
            }
            focusCard("scroll") {
                Text("Scroll wheel").font(.system(size: 13, weight: .semibold))
                toggleRow("Natural direction", scrollBinding(\.natural))
                toggleRow("Smooth scrolling", scrollBinding(\.smooth))
                speedSlider(\.verticalScale)
            }
            focusCard("thumb") {
                Text("Thumb wheel").font(.system(size: 13, weight: .semibold))
                toggleRow("Reverse direction", scrollBinding(\.horizontalInverted))
                speedSlider(\.horizontalScale)
            }
            card {
                Text("SmartShift").font(.system(size: 13, weight: .semibold))
                LiteSegmented(items: [("Free-spin", "free"), ("Ratchet", "ratchet"), ("Auto", "auto")], selection: smartSelection) { v in
                    switch v {
                    case "free": model.applyWheel(mode: 1, threshold: 255)
                    case "ratchet": model.applyWheel(mode: 2, threshold: 255)
                    default: model.applyWheel(mode: 2, threshold: 50)
                    }
                }
                caption(snap?.wheelMode == nil ? "Wheel mode not read yet. Selecting one writes it to the mouse." : "Uses live device readback.")
            }
        }
    }

    // Keys

    private var keysInspector: some View {
        let key = KeyboardView.keys.first { $0.id == keyboardControl }
        return inspector(footer: "Keys set to their own built-in function (backlight, mute, volume, dictation, Do Not Disturb) are left to the keyboard.") {
            HStack(spacing: 12) {
                Group {
                    if let symbol = key?.symbol { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
                    else { Text(key?.short ?? "").font(.system(size: 11, weight: .bold)) }
                }
                .foregroundStyle(Color(white: 0.12))
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.86)], startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Lite.hair, lineWidth: 1))
                .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(key?.name ?? "Key").font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45)).lineLimit(1)
                    Text(model.resolvedSelected.keyboard[keyboardControl]?.displayLabel ?? "Native").font(.system(size: 17, weight: .bold)).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            SearchField(text: $search)
        } content: {
            mappingStatus
            ActionList(model: model, group: "keyboard", key: keyboardControl, search: search) { shortcutTarget = ShortcutTarget(group: "keyboard", key: keyboardControl) }
        }
    }

    // Backlighting

    private var lightInspector: some View {
        let backlight = model.devices[.keyboard]?.snapshot.backlight
        return inspector {
            headerRow(symbol: "light.max",
                      label: backlight.map { $0.enabled ? "Live · level \($0.level) · \($0.duration)s" : "Live · off" } ?? "Readback unavailable",
                      title: "Backlighting")
            if let b = backlight {
                LiteSegmented(items: [("Off", 0), ("Automatic", 1), ("Manual", 3)], selection: b.enabled ? b.mode : 0, height: 30) { mode in
                    if (mode == 1 && !b.supportsAuto) || (mode == 3 && !b.supportsManual) { return }
                    model.applyBacklight(mode: mode)
                }
            }
        } content: {
            if let b = backlight {
                VStack(alignment: .leading, spacing: 14) {
                    card {
                        HStack { Text("Brightness").font(.system(size: 13, weight: .semibold)); Spacer(); Text("Level \(b.level)").monospacedDigit().foregroundStyle(Lite.ink.opacity(0.6)) }
                        LiteSegmented(items: (0..<max(b.levels, 1)).map { ("\($0)", $0) }, selection: b.level, height: 24) { model.applyBacklight(mode: 3, level: $0) }
                            .disabled(!b.supportsManual)
                    }
                    card {
                        Text("Turn off after inactivity").font(.system(size: 13, weight: .semibold))
                        LiteSegmented(items: [("5s", 5), ("10s", 10), ("30s", 30), ("1m", 60), ("5m", 300)], selection: b.duration, height: 24) { model.applyBacklight(seconds: $0) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        label("Effect").padding(.leading, 10)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                            ForEach(Array(Lite.effects.enumerated()).filter { b.effects & (1 << $0.offset) != 0 }, id: \.offset) { i, name in
                                effectTile(name, index: i, on: b.effect == i)
                            }
                        }
                    }
                }
                .opacity(b.enabled ? 1 : 0.35).allowsHitTesting(b.enabled)
                .animation(.smooth(duration: 0.2), value: b.enabled)
            } else {
                caption("Backlight state is unavailable. Select this Mac with Easy-Switch, wake the keyboard, then retry.").padding(.horizontal, 10)
                GlassButton(title: "Retry Devices") { Task { await model.retry() } }.padding(.horizontal, 10)
            }
        }
    }

    private func effectTile(_ name: String, index: Int, on: Bool) -> some View {
        let pattern: [Double] = [[1, 1, 1], [0.2, 0.2, 0.2], [1, 0.55, 0.2], [1, 0.2, 1], [0.2, 1, 0.2], [1, 0.2, 0.6], [0.3, 0.65, 1]][index]
        return Button { model.applyBacklight(effect: index) } label: {
            VStack(alignment: .leading) {
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { RoundedRectangle(cornerRadius: 2).fill(Lite.ink.opacity(pattern[$0])).frame(width: 8, height: 8) } }
                Spacer()
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? Lite.accent : Lite.ink)
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? Lite.accent.opacity(0.18) : Lite.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(on ? Lite.accent : Lite.ink.opacity(0.07), lineWidth: 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // Easy-Switch

    private var easySwitchInspector: some View {
        inspector(footer: "Pairing and host switching are performed with the hardware keys or macOS Bluetooth settings.") {
            headerRow(symbol: "arrow.left.arrow.right", label: "Press the device button to switch", title: "Easy-Switch")
        } content: {
            VStack(spacing: 2) {
                ForEach(1...3, id: \.self) { slot in
                    let host = snapshot?.hosts.first { $0.channel == slot }
                    let current = model.devices[device]?.connected == true && snapshot?.currentHost == slot
                    HStack(spacing: 10) {
                        Text("\(slot)").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Lite.ink.opacity(0.1)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(host?.name ?? (current ? "This Mac" : "Channel \(slot)")).font(.system(size: 13, weight: .semibold))
                            Text(current ? "Connected · Bluetooth" : host?.paired == true ? "Paired · Bluetooth" : host?.paired == false ? "Not paired" : "Host information unavailable")
                                .font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.5)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if current { Text("Current").font(.system(size: 10, weight: .semibold)).foregroundStyle(Lite.greenText) }
                    }
                    .padding(.horizontal, 10).frame(height: 48)
                }
            }
        }
    }

    // MARK: Settings

    private func group<C: View>(_ heading: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45)).padding(.leading, 12)
            VStack(spacing: 0) { c() }.padding(.horizontal, 14).liteGlass(10)
        }
    }
    private func row<T: View>(_ title: String, _ sub: String? = nil, divider: Bool = true, @ViewBuilder trailing: () -> T) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let sub { Text(sub).font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.48)).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 12)
                trailing()
            }.frame(minHeight: 56).padding(.vertical, 6)
            if divider { Rectangle().fill(Lite.ink.opacity(0.07)).frame(height: 1) }
        }
    }
    private func granted(_ ok: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(ok ? Lite.green : Lite.amber).frame(width: 7, height: 7)
            Text(ok ? "Granted" : "Not granted").font(.system(size: 13, weight: .semibold)).foregroundStyle(ok ? Lite.greenText : Lite.amber)
        }
    }

    private func settingsContent(_ device: Model?) -> some View {
        Group {
            if let device { deviceSettings(device) } else { appSettings }
        }
        .frame(maxWidth: 720, alignment: .leading).frame(maxWidth: .infinity)
    }

    /// App-wide settings: the sidebar "Settings" page.
    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !model.conflicts.isEmpty {
                warning("Suspected conflicts: \(model.conflicts.joined(separator: ", ")). Quit them manually before enabling mappings.")
            }
            group("General") {
                row("Appearance", "Applied after Save.") {
                    LiteSegmented(items: [("System", "system"), ("Light", "light"), ("Dark", "dark")], selection: model.draft.theme, height: 26) { model.draft.theme = $0 }
                        .frame(width: 240)
                }
                row("Launch at Login", "May need approval in System Settings and can be rejected for an ad-hoc development build. Actual status and errors are shown.", divider: false) {
                    Toggle("", isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)).labelsHidden().toggleStyle(.switch).tint(Lite.green)
                }
                row("Show menu-bar icon", "Off keeps mappings active without battery/status polling. Reopen LogiMXLite from Applications to change settings. Applies when this window closes.", divider: false) {
                    Toggle("", isOn: $model.showMenuBarIcon).labelsHidden().toggleStyle(.switch).tint(Lite.green)
                }
            }
            group("Permissions & recovery") {
                row("Input Monitoring", "Grants access to BLE vendor reports.") {
                    HStack(spacing: 12) { granted(model.inputAllowed); GlassButton(title: "Open") { model.requestPermission(false) } }
                }
                row("Accessibility", "Needed only for mapped actions.") {
                    HStack(spacing: 12) { granted(model.accessibilityAllowed); GlassButton(title: "Open") { model.requestPermission(true) } }
                }
                HStack(alignment: .center, spacing: 20) {
                    caption("After granting access, quit and reopen the app or Retry Devices. Bluetooth permission is not requested: this app uses IOHID for already-paired BLE devices and does not scan with CoreBluetooth.")
                    Spacer(minLength: 0)
                    GlassButton(title: "Retry Devices") { Task { await model.retry() } }.fixedSize()
                    GlassButton(title: "Relaunch LogiMXLite") { model.relaunch() }.fixedSize()
                }.padding(.vertical, 14)
            }
            group("Input mappings") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Temporary diversion is enabled only for enumerated controls. Primary clicks and standard typing are never intercepted. Leftover diversion from another tool is taken over and released on quit, so Back and Forward always return to native behavior. Scroll speed, direction and smoothing run through macOS and stop the moment the app quits.")
                        .foregroundStyle(Lite.ink.opacity(0.72)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        GlassButton(title: model.mappingEnabled ? "Disable mappings & restore native controls" : "Enable verified mappings", prominent: !model.mappingEnabled) {
                            Task { if model.mappingEnabled { await model.disableMappings() } else { await model.enableMappings() } }
                        }
                        Spacer()
                    }
                    toggleRow("Enable mappings automatically when devices are ready", $model.autoEnableMappings)
                }.padding(.vertical, 16)
            }
            HStack {
                Spacer()
                GlassButton(title: "Quit LogiMXLite") { model.quitAgent?() }
            }
        }
    }

    /// Settings that belong to one device only: the device "Settings" tab.
    private func deviceSettings(_ device: Model) -> some View {
        let d = model.devices[device]
        let online = d?.connected == true
        let firmware = (d?.snapshot.firmware ?? []).joined(separator: "; ")
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(shortName(device)) settings").font(.system(size: 22, weight: .semibold)).kerning(-0.3)
                HStack(spacing: 6) {
                    Circle().fill(online ? Lite.green : Color.gray).frame(width: 6, height: 6)
                    Text(d?.status ?? "Disconnected").font(.system(size: 12)).foregroundStyle(Lite.ink.opacity(0.6))
                }
            }
            .padding(.top, 12).padding(.horizontal, 2)
            group("Device") {
                row("Connection") { Text(online ? "Bluetooth Low Energy" : "Offline").foregroundStyle(Lite.ink.opacity(0.6)) }
                row("Battery") {
                    Text(online ? (d?.snapshot.battery.map { "\($0)%\(d?.snapshot.batteryStatus?.isCharging == true ? " · Charging" : d?.snapshot.batteryStatus == .full ? " · Charged" : "")" } ?? "—") : "—")
                        .monospacedDigit().foregroundStyle(Lite.ink.opacity(0.6))
                }
                row("Firmware", divider: false) { Text(firmware.isEmpty ? "Unknown" : firmware).lineLimit(1).truncationMode(.middle).foregroundStyle(Lite.ink.opacity(0.6)) }
            }
            if device == .keyboard {
                group("Keyboard") {
                    row("Invert function-key mode", "Top-row keys send F1–F12 unless fn is held.", divider: false) {
                        Toggle("", isOn: Binding(get: { model.devices[.keyboard]?.snapshot.fnInverted ?? false }, set: model.applyFn))
                            .labelsHidden().toggleStyle(.switch).tint(Lite.green)
                            .disabled(model.devices[.keyboard]?.snapshot.fnInverted == nil)
                    }
                }
            }
            group("Reset") {
                row("Reset device profile", "Restores every control on this device to its default in the draft. Save to keep it.", divider: false) {
                    GlassButton(title: "Reset to Default", destructive: true) { model.resetDevice(device) }.disabled(model.busy)
                }
            }
            Text("App-wide options such as appearance, permissions and mappings are in Settings in the sidebar.")
                .font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.45)).padding(.horizontal, 12)
        }
    }

    // MARK: Save bar

    private var saveBar: some View {
        HStack(spacing: 10) {
            Circle().fill(Lite.amber).frame(width: 8, height: 8)
            Text("Unsaved changes").font(.system(size: 13, weight: .medium)).padding(.trailing, 8)
            GlassButton(title: "Revert") { model.revert() }.disabled(model.busy)
            GlassButton(title: "Save", prominent: true) { model.save() }.disabled(model.busy).keyboardShortcut("s")
        }
        .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
        .liteCapsule()
        .shadow(color: .black.opacity(0.45), radius: 25, y: 12)
    }
}

// MARK: - DPI presets editor

/// Compact preset editor: click a DPI value to apply it, drag to pick a new one, add with one click.
private struct LiteDPIEditor: View {
    @ObservedObject var model: AppModel
    let done: () -> Void
    @State private var newDPI: Double = 1600
    @State private var newName = ""
    private var range: DPIRange? { model.devices[.mouse]?.snapshot.dpiRange }
    private var lo: Double { Double(range?.values.first ?? 200) }
    private var hi: Double { Double(range?.values.last ?? 8000) }
    private func snapped(_ v: Double) -> Int {
        guard let values = range?.values, !values.isEmpty else { return Int((v / 50).rounded() * 50) }
        return values.min(by: { abs(Double($0) - v) < abs(Double($1) - v) }) ?? Int(v)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DPI presets").font(.system(size: 20, weight: .bold))
                    Text(range.map { "Supported \($0.values.first ?? 0)–\($0.values.last ?? 0) DPI" } ?? "Device range not read yet")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                GlassButton(title: "Done", prominent: true, action: done).keyboardShortcut(.defaultAction)
            }

            VStack(spacing: 0) {
                if model.draft.dpiPresets.isEmpty {
                    Text("No presets yet. Pick a value below and add it.").font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                ForEach(Array(model.draft.dpiPresets.enumerated()), id: \.element.id) { index, preset in
                    let current = model.devices[.mouse]?.snapshot.dpi == preset.dpi
                    HStack(spacing: 10) {
                        Button { model.applyDPI(preset.dpi) } label: {
                            Text("\(preset.dpi)").font(.system(size: 14, weight: .bold).monospacedDigit())
                                .foregroundStyle(current ? Lite.onAccent : Lite.ink)
                                .frame(width: 70, height: 28)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(current ? Lite.accent : Lite.ink.opacity(0.1)))
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain).help("Apply \(preset.dpi) DPI now")
                        .disabled(range.map { !$0.supports(preset.dpi) } ?? false)
                        TextField("Name", text: Binding(get: { preset.name }, set: { model.draft.dpiPresets[index].name = $0 }))
                            .textFieldStyle(.plain).font(.system(size: 13))
                        Stepper("", value: Binding(get: { preset.dpi }, set: { model.draft.dpiPresets[index].dpi = snapped(Double($0)) }), in: Int(lo)...Int(hi), step: 50)
                            .labelsHidden()
                        Button(role: .destructive) {
                            let id = preset.id
                            model.draft.dpiPresets.removeAll { $0.id == id }
                            for i in model.draft.profiles.indices where model.draft.profiles[i].dpiPreset == id { model.draft.profiles[i].dpiPreset = nil }
                        } label: { Image(systemName: "trash").font(.system(size: 12)).frame(width: 24, height: 24).contentShape(Rectangle()) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete preset")
                    }
                    .padding(.horizontal, 10).frame(height: 44)
                    if index < model.draft.dpiPresets.count - 1 { Rectangle().fill(Lite.ink.opacity(0.07)).frame(height: 1).padding(.leading, 90) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Lite.ink.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Lite.ink.opacity(0.08), lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Text("New preset").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text("\(snapped(newDPI))").font(.system(size: 17, weight: .bold).monospacedDigit()).frame(width: 56, alignment: .leading)
                    Slider(value: $newDPI, in: lo...max(hi, lo + 1)).tint(Lite.accent)
                }
                HStack(spacing: 10) {
                    TextField("Name (optional)", text: $newName).textFieldStyle(.plain)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Lite.well))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Lite.ink.opacity(0.1), lineWidth: 1))
                    GlassButton(title: "Add preset", prominent: true) {
                        let dpi = snapped(newDPI)
                        model.draft.dpiPresets.append(DPIPreset(name: newName.isEmpty ? "\(dpi) DPI" : newName, dpi: dpi))
                        newName = ""
                    }
                    .fixedSize()
                    .disabled(range.map { !$0.supports(snapped(newDPI)) } ?? false)
                }
            }

            Rectangle().fill(Lite.ink.opacity(0.07)).frame(height: 1)
            HStack {
                Text("Profile DPI").font(.system(size: 13))
                Spacer()
                Picker("", selection: Binding(get: { model.selected.dpiPreset }, set: { v in model.editProfile { $0.dpiPreset = v } })) {
                    Text("Inherit / unchanged").tag(Optional<UUID>.none)
                    ForEach(model.draft.dpiPresets) { Text("\($0.name) · \($0.dpi)").tag(Optional($0.id)) }
                }.labelsHidden().pickerStyle(.menu).buttonStyle(.plain).frame(width: 220)
                .padding(.horizontal, 10).frame(height: 30).liteCapsule()
            }
            Toggle("Apply per-app hardware settings on app activation", isOn: $model.draft.switchHardwareWithApps)
                .toggleStyle(.switch).tint(Lite.green).controlSize(.small).font(.system(size: 13))
            Text("Changes are kept in the draft. Save in the main window to keep them.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { if let d = model.devices[.mouse]?.snapshot.dpi { newDPI = Double(d) } }
    }
}

// MARK: - Overview card

private struct HomeCard: View {
    let name: String
    let model: Model
    let battery: Int?
    let batteryStatus: BatteryStatus?
    let connected: Bool
    let facts: [(String, String)]
    let links: [(String, DeviceTab)]
    let open: (DeviceTab?) -> Void
    var body: some View {
        VStack(spacing: 0) {
            LiteImage.of(model)
                .frame(maxWidth: model == .mouse ? 120 : 310, maxHeight: model == .mouse ? 170 : 130)
                .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
                .opacity(connected ? 1 : 0.45)
                .frame(maxWidth: .infinity).frame(height: 196)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Lite.stage))
                .padding([.horizontal, .top], 8)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(connected ? Lite.green : Color.gray).frame(width: 6, height: 6)
                        Text(connected ? "Connected · Bluetooth" : "Offline").font(.system(size: 12)).foregroundStyle(Lite.ink.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
                if connected, let battery {
                    HStack(spacing: 8) {
                        ZStack(alignment: .leading) {
                            Capsule().fill(Lite.ink.opacity(0.1))
                            Capsule().fill(battery > 30 || batteryStatus?.isCharging == true ? Lite.green : Color.red).frame(width: 56 * CGFloat(min(max(battery, 3), 100)) / 100)
                        }.frame(width: 56, height: 5)
                        Text("\(battery)%").font(.system(size: 12, weight: .semibold).monospacedDigit()).frame(width: 34, alignment: .trailing)
                        if batteryStatus?.isCharging == true { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(Lite.greenText).help("Charging") }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            VStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    VStack(spacing: 0) {
                        Rectangle().fill(Lite.hair).frame(height: 1)
                        HStack {
                            Text(f.0).foregroundStyle(Lite.ink.opacity(0.6))
                            Spacer()
                            Text(f.1).monospacedDigit()
                        }
                        .font(.system(size: 12)).frame(height: 30)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 6)
            HStack(spacing: 6) {
                ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                    Button(link.0) { open(link.1) }.buttonStyle(.pill)
                }
                Spacer()
                Button("Configure") { open(nil) }.buttonStyle(.pillProminent)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Lite.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Lite.hair, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.name)")
    }
}

// MARK: - Key ring

/// Outline for a keyboard hotspot. The keyboard render is always light, so rings use fixed dark ink in both appearances.
private struct KeyRing: View {
    let on: Bool
    let fixed: Bool
    @State private var hover = false
    var body: some View {
        let ink = Color(white: 0.16)
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(on || fixed ? ink.opacity(fixed && !on ? 0.55 : 0.9) : hover ? ink.opacity(0.4) : Color.clear, lineWidth: on ? 2.5 : 1.5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? ink.opacity(0.08) : Color.clear))
            .frame(width: 38, height: 36)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(.smooth(duration: 0.15), value: hover)
    }
}

// MARK: - Scroll fade

struct ScrollEdges: Equatable {
    var top = false
    var bottom = false
}

/// ScrollView whose content fades under the top edge once scrolled and at the bottom while more remains.
private struct FadeScroll<Content: View>: View {
    var target: String? = nil
    @Binding var edges: ScrollEdges
    @ViewBuilder var content: Content
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: ScrollEdges.self) { g in
                    ScrollEdges(top: g.contentOffset.y + g.contentInsets.top > 2,
                                bottom: g.contentOffset.y + g.containerSize.height < g.contentSize.height - 2)
                } action: { _, new in
                    withAnimation(.easeOut(duration: 0.15)) { edges = new }
                }
                .onChange(of: target) { _, t in
                    guard let t else { return }
                    withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(t, anchor: .top) }
                }
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: edges.top ? 28 : 0)
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: edges.bottom ? 40 : 0)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.45))
            TextField("Search actions", text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Lite.ink.opacity(0.45)) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Lite.well))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Lite.ink.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Action list

/// Grouped, icon-aligned action list. Same filtering rules as AssignmentRow.
private struct ActionList: View {
    @ObservedObject var model: AppModel
    let group: String
    let key: String
    let search: String
    var onShortcut: () -> Void

    private var effective: Action? {
        group == "mouse" ? model.resolvedSelected.mouse[key] : group == "keyboard" ? model.resolvedSelected.keyboard[key] : model.resolvedSelected.gestures[key]
    }
    private var own: Action? {
        group == "mouse" ? model.selected.mouse[key] : group == "keyboard" ? model.selected.keyboard[key] : model.selected.gestures[key]
    }
    private var query: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private func matches(_ s: String) -> Bool { query.isEmpty || s.lowercased().contains(query) }
    private var kinds: [ActionKind] {
        ActionKind.allCases.filter { kind in
            kind != .shortcut && kind != .requiresConfirmation && kind != .nativeHorizontalScroll &&
            (key == "thumbWheel" ? kind.isThumbMode || kind == .none : !kind.isThumbMode)
        }.filter { matches(Action($0).label) }
    }

    static let order = ["Navigation", "Window", "Media & sound", "System", "Mouse"]
    static func category(_ label: String) -> String {
        let s = label.lowercased()
        func has(_ w: [String]) -> Bool { w.contains { s.contains($0) } }
        if has(["backlight", "brightness"]) { return "System" }
        if has(["volume", "mute", "play", "track", "media", "microphone"]) { return "Media & sound" }
        if has(["window", "tab", "zoom", "full screen", "minimi", "maximi"]) { return "Window" }
        if has(["back", "forward", "mission", "exposé", "expose", "desktop", "launchpad", "space"]) { return "Navigation" }
        if has(["click", "dpi", "smartshift", "wheel", "scroll", "gesture", "nothing", "pointer"]) { return "Mouse" }
        return "System"
    }
    static let symbols: [(String, String)] = [
        ("to the left", "arrow.left.square"), ("to the right", "arrow.right.square"), ("smart zoom", "plus.magnifyingglass"),
        ("backlight", "light.max"), ("volume up", "speaker.wave.3"), ("volume down", "speaker.wave.1"), ("microphone", "mic.slash"),
        ("mute", "speaker.slash"), ("play", "playpause"), ("next track", "forward.end"), ("previous track", "backward.end"),
        ("mission", "rectangle.3.group"), ("exposé", "rectangle.stack"), ("expose", "rectangle.stack"), ("show desktop", "menubar.dock.rectangle"),
        ("launchpad", "square.grid.3x3"), ("previous desktop", "chevron.left.2"), ("next desktop", "chevron.right.2"),
        ("back", "arrow.left"), ("forward", "arrow.right"), ("maximi", "arrow.up.left.and.arrow.down.right"), ("zoom", "arrow.up.left.and.arrow.down.right"),
        ("minimi", "minus"), ("next tab", "arrow.right.to.line"), ("previous tab", "arrow.left.to.line"), ("close tab", "xmark"),
        ("download", "arrow.down.circle"), ("capture", "camera.viewfinder"), ("screenshot", "camera.viewfinder"), ("emoji", "face.smiling"),
        ("spotlight", "magnifyingglass"), ("search", "magnifyingglass"), ("dictation", "mic"), ("disturb", "moon"), ("lock", "lock"),
        ("middle", "computermouse"), ("click", "cursorarrow.click"), ("dpi", "gauge.with.dots.needle.50percent"), ("smartshift", "dial.medium"),
        ("horizontal", "arrow.left.and.right"), ("scroll", "arrow.up.and.down"), ("nothing", "nosign"), ("shortcut", "command"), ("inherit", "arrow.uturn.backward")
    ]
    static func symbol(_ label: String) -> String {
        let s = label.lowercased()
        return symbols.first { s.contains($0.0) }?.1 ?? "circle.dashed"
    }

    var body: some View {
        let grouped = Dictionary(grouping: kinds) { Self.category(Action($0).label) }
        let showShortcut = key != "thumbWheel" && matches("keyboard shortcut")
        let showNative = key == "thumbWheel" && matches("horizontal scroll (native)")
        let showInherit = !model.selected.isDefault && matches("inherit desktop")
        VStack(alignment: .leading, spacing: 14) {
            if own == nil && !model.selected.isDefault {
                Text("Inherited from Desktop").font(.system(size: 11)).foregroundStyle(Lite.ink.opacity(0.45)).padding(.leading, 10)
            }
            if showInherit || showShortcut || showNative {
                section("Assignment") {
                    if showInherit { ActionRow(title: "Inherit Desktop", symbol: "arrow.uturn.backward", on: own == nil) { model.setAction(group, key: key, action: nil) } }
                    if showNative { ActionRow(title: "Horizontal scroll (native)", symbol: "arrow.left.and.right", on: effective?.kind == .nativeHorizontalScroll) { model.setAction(group, key: key, action: Action(.nativeHorizontalScroll)) } }
                    if showShortcut {
                        ActionRow(title: effective?.kind == .shortcut ? "Shortcut · \(effective?.label ?? "")" : "Keyboard shortcut…", symbol: "command", on: effective?.kind == .shortcut, action: onShortcut)
                    }
                }
            }
            ForEach(Self.order, id: \.self) { name in
                if let items = grouped[name], !items.isEmpty {
                    section(name) {
                        ForEach(items, id: \.self) { kind in
                            let label = Action(kind).label
                            ActionRow(title: label, symbol: Self.symbol(label), on: effective?.kind == kind) { model.setAction(group, key: key, action: Action(kind)) }
                        }
                    }
                }
            }
            if kinds.isEmpty && !showShortcut && !showNative && !showInherit {
                Text("No actions match \u{201C}\(search)\u{201D}").font(.system(size: 12)).foregroundStyle(Lite.ink.opacity(0.5)).padding(.leading, 10)
            }
            if effective?.kind == .requiresConfirmation {
                Text("Imported action needs confirmation: \(effective?.label ?? ""). Record a shortcut or pick a supported action.")
                    .font(.system(size: 11)).foregroundStyle(Lite.amber).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Lite.ink.opacity(0.42)).padding(.horizontal, 10).padding(.bottom, 4)
            rows()
        }
    }
}

private struct ActionRow: View {
    let title: String
    let symbol: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12))
                    .frame(width: 18)
                    .opacity(on ? 1 : 0.65)
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 14).opacity(on ? 1 : 0)
            }
            .foregroundStyle(on ? Lite.onAccent : Lite.ink)
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Lite.accent : hover ? Lite.ink.opacity(0.06) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
