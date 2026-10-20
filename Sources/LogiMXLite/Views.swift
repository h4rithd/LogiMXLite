import SwiftUI
import LogiCore
import AppKit

struct MenuRow: View {
    let icon: String
    let title: String
    var checked: Bool? = nil
    var highlighted = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let checked {
                    Image(systemName: checked ? "checkmark" : "circle.dotted").frame(width: 22).foregroundStyle(checked ? Color.primary : Color.secondary.opacity(0.4))
                } else {
                    Image(systemName: icon).font(.system(size: 14)).frame(width: 24).foregroundStyle(.secondary)
                }
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hover || highlighted ? Color.primary.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityAddTraits(checked == true ? .isSelected : [])
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    private var statusText: String {
        switch model.overall { case "Both connected": "Both devices connected"; case "One connected": "One device connected"; default: "No devices connected" }
    }
    private var statusColor: Color {
        switch model.overall { case "Both connected": .green; case "One connected": .orange; default: .secondary }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LogiMXLite").font(.system(size: 17, weight: .bold))
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 9, height: 9)
                    Text(statusText).font(.system(size: 13)).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }.padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 8)
            Divider().padding(.vertical, 5)
            ForEach(Model.allCases) { device in
                let state = model.devices[device]
                Button { model.showSettings?() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: device == .mouse ? "computermouse" : "keyboard").font(.system(size: 15)).frame(width: 24).foregroundStyle(.secondary)
                        Text(device.name).font(.system(size: 13)).lineLimit(1).layoutPriority(1)
                        Spacer(minLength: 8)
                        if state?.connected == true { BatteryLabel(percent: state?.snapshot.battery, status: state?.snapshot.batteryStatus).font(.system(size: 13)) }
                        else { Text("Offline").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }.padding(.horizontal, 10).padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open configuration for \(device.name)")
            }
            Divider().padding(.vertical, 5)
            MenuRow(icon: "power", title: "Quit LogiMXLite") { model.quit?() }
        }
        .padding(12).frame(width: 344).preferredColorScheme(model.theme)
    }
}

enum SectionPage: String, CaseIterable, Identifiable {
    case devices = "Devices", mouse = "Mouse", keyboard = "Keyboard", profiles = "Profiles"
    case general = "General", backup = "Export / Import", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .devices: "rectangle.connected.to.line.below"
        case .mouse: "computermouse"
        case .keyboard: "keyboard"
        case .profiles: "app.badge"
        case .general: "gearshape"
        case .backup: "square.and.arrow.up"
        case .about: "info.circle"
        }
    }
    static let primary: [SectionPage] = [.devices, .mouse, .keyboard, .profiles]
    static let secondary: [SectionPage] = [.general, .backup, .about]
    init?(argument: String) {
        let key = argument.lowercased()
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == key || $0.rawValue.lowercased().hasPrefix(key) }) else { return nil }
        self = match
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    let initialPage: SectionPage
    init(model: AppModel, initialPage: SectionPage = .devices) {
        self.model = model
        self.initialPage = initialPage
    }
    var body: some View {
        OptionsWorkspace(model: model, initialPage: initialPage)
        .frame(minWidth: 1100, minHeight: 650)
        .ignoresSafeArea()
        .preferredColorScheme(model.theme)
        .sheet(isPresented: Binding(get: { model.preview != nil }, set: { if !$0 { model.preview = nil } })) { ImportReview(model: model) }
        .alert("LogiMXLite", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
}

struct AssignmentRow: View {
    @ObservedObject var model: AppModel
    let group: String
    let key: String
    let label: String
    var highlight = false
    @State private var shortcut = false
    var own: Action? { group == "mouse" ? model.selected.mouse[key] : group == "keyboard" ? model.selected.keyboard[key] : model.selected.gestures[key] }
    var effective: Action? { group == "mouse" ? model.resolvedSelected.mouse[key] : group == "keyboard" ? model.resolvedSelected.keyboard[key] : model.resolvedSelected.gestures[key] }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11.5)).lineLimit(1).fixedSize().foregroundStyle(highlight ? Color.accentColor : Color.secondary)
                if own == nil && !model.selected.isDefault { Text("Inherited from Desktop").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Menu {
                if !model.selected.isDefault { Button("Inherit Desktop") { model.setAction(group, key: key, action: nil) } }
                if key == "thumbWheel" { Button("Horizontal scroll (native)") { model.setAction(group, key: key, action: Action(.nativeHorizontalScroll)) } }
                else { Button("Keyboard shortcut…") { shortcut = true } }
                ForEach(ActionKind.allCases.filter { kind in
                    kind != .shortcut && kind != .requiresConfirmation && kind != .nativeHorizontalScroll && (key == "thumbWheel" ? kind.isThumbMode || kind == .none : !kind.isThumbMode)
                }, id: \.self) { kind in
                    Button(Action(kind).label) { model.setAction(group, key: key, action: Action(kind)) }
                }
            } label: { DropdownField(text: effective?.displayLabel ?? "Native / unassigned") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help(effective.map { $0.kind == .requiresConfirmation ? $0.label : "Edits desired mappings. Save, then enable verified mappings in General." } ?? "Native behavior is retained")
            .accessibilityLabel("\(label) action")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(highlight ? Color.accentColor.opacity(0.10) : Color.clear))
        .sheet(isPresented: $shortcut) { ShortcutEditor { action in model.setAction(group, key: key, action: action); shortcut = false } cancel: { shortcut = false } }
    }
}

/// Primary clicks are never diverted, so they are shown as fixed.
struct FixedRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Text(value).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "lock.fill").font(.caption2)
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, 9).padding(.vertical, 4).frame(width: 176)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.fieldBackground.opacity(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .help("Primary mouse buttons are never intercepted")
    }
}

/// Captures the next key combination pressed while the sheet is open, including ones the menu bar would normally claim.
final class KeyCaptureView: NSView {
    var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
    var onModifiers: ((NSEvent.ModifierFlags) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self) } }
    override func keyDown(with event: NSEvent) { if !event.isARepeat { onKey?(event.keyCode, event.modifierFlags) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { if !event.isARepeat { onKey?(event.keyCode, event.modifierFlags) }; return true }
    override func flagsChanged(with event: NSEvent) { onModifiers?(event.modifierFlags) }
}
struct KeyCapture: NSViewRepresentable {
    var onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    var onModifiers: (NSEvent.ModifierFlags) -> Void
    func makeNSView(context: Context) -> KeyCaptureView { let v = KeyCaptureView(); v.onKey = onKey; v.onModifiers = onModifiers; return v }
    func updateNSView(_ view: KeyCaptureView, context: Context) { view.onKey = onKey; view.onModifiers = onModifiers }
}

struct ShortcutEditor: View {
    var save: (Action) -> Void
    var cancel: () -> Void
    @State private var captured: Action?
    @State private var live: [Int] = []
    @State private var problem: String?
    private static func usages(_ flags: NSEvent.ModifierFlags) -> [Int] {
        [(flags.contains(.control), 224), (flags.contains(.shift), 225), (flags.contains(.option), 226), (flags.contains(.command), 227)].compactMap { $0.0 ? $0.1 : nil }
    }
    private var shown: String {
        if let captured { return captured.label }
        if !live.isEmpty { return [224: "⌃", 226: "⌥", 225: "⇧", 227: "⌘"].filter { live.contains($0.key) }.sorted { [224, 226, 225, 227].firstIndex(of: $0.key)! < [224, 226, 225, 227].firstIndex(of: $1.key)! }.map(\.value).joined() + " …" }
        return "Press the shortcut now"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard shortcut").font(.title2.bold())
            Text("Press the key combination you want this control to send.").foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.fieldBackground)
                RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(captured == nil ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: captured == nil ? 2 : 1)
                Text(shown).font(.system(size: 26, weight: .medium, design: .rounded)).foregroundStyle(captured == nil && live.isEmpty ? Color.secondary : Color.primary)
                KeyCapture(onKey: { code, flags in
                    guard let usage = HIDKeyMap.usage(forVirtualKey: code) else { problem = "That key cannot be sent. Try another."; return }
                    problem = nil; live = []
                    captured = Action(.shortcut, usage: usage, modifiers: Self.usages(flags))
                }, onModifiers: { flags in if captured == nil { live = Self.usages(flags) } }).frame(width: 1, height: 1).opacity(0.01)
            }.frame(height: 84)
            if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            HStack {
                Button("Cancel", action: cancel)
                Button("Record again") { captured = nil; live = []; problem = nil }.disabled(captured == nil)
                Spacer()
                Button("Use Shortcut") { if let captured { save(captured) } }.buttonStyle(.borderedProminent).disabled(captured == nil)
            }
        }.padding(24).frame(width: 440)
    }
}
