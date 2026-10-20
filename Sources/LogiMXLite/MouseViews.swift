import SwiftUI
import AppKit
import LogiCore

struct MouseHotspot: Identifiable {
    let id: String
    let title: String
    let spot: CGPoint      // fraction of the product render (x, y)
    let leftSide: Bool
    let calloutY: CGFloat  // vertical centre of the callout in the 360x300 frame
}

struct MouseDiagram: View {
    @Binding var selected: String
    var label: (String) -> String
    // Positions are approximate and drawn on the supplied render; live enumeration decides what is actually usable.
    static let hotspots: [MouseHotspot] = [
        MouseHotspot(id: "c86", title: "Forward", spot: CGPoint(x: 0.41, y: 0.28), leftSide: true, calloutY: 44),
        MouseHotspot(id: "c83", title: "Back", spot: CGPoint(x: 0.40, y: 0.325), leftSide: true, calloutY: 112),
        MouseHotspot(id: "thumbWheel", title: "Thumb Wheel", spot: CGPoint(x: 0.48, y: 0.43), leftSide: true, calloutY: 180),
        MouseHotspot(id: "click", title: "Gesture Button", spot: CGPoint(x: 0.25, y: 0.70), leftSide: true, calloutY: 250),
        MouseHotspot(id: "c82", title: "Middle Click", spot: CGPoint(x: 0.65, y: 0.175), leftSide: false, calloutY: 50),
        MouseHotspot(id: "c196", title: "Top Button", spot: CGPoint(x: 0.755, y: 0.365), leftSide: false, calloutY: 130)
    ]
    private let imageSize = CGSize(width: 188, height: 280)
    private var origin: CGPoint { CGPoint(x: 180 - imageSize.width / 2, y: 10) }
    private func absolute(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * imageSize.width, y: origin.y + p.y * imageSize.height)
    }
    var body: some View {
        ZStack {
            DevicePhoto(model: .mouse).frame(width: imageSize.width, height: imageSize.height).position(x: 180, y: 150)
            ForEach(Self.hotspots) { hot in
                let target = absolute(hot.spot)
                let start = CGPoint(x: hot.leftSide ? 100 : 260, y: hot.calloutY)
                Path { p in p.move(to: start); p.addLine(to: target) }
                    .stroke(selected == hot.id ? Color.accentColor : Color.white.opacity(0.85), lineWidth: 1.2)
                    .shadow(color: Color.black.opacity(0.35), radius: 0.5)
                Circle().fill(selected == hot.id ? Color.accentColor : Color.white).frame(width: 8, height: 8)
                    .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 0.6)).position(target)
            }
            ForEach(Self.hotspots) { hot in
                Button { selected = hot.id } label: {
                    VStack(spacing: 1) {
                        Text(hot.title).font(.system(size: 10.5, weight: .medium))
                        Text(label(hot.id)).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 96, height: 34)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.cardBackground))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selected == hot.id ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: selected == hot.id ? 1.5 : 0.8))
                }
                .buttonStyle(.plain)
                .position(x: hot.leftSide ? 52 : 308, y: hot.calloutY)
                .help("\(hot.title): \(label(hot.id)). Drawn position is approximate.")
                .accessibilityLabel("\(hot.title), \(label(hot.id))")
            }
        }
        .frame(width: 360, height: 300)
    }
}

struct MouseView: View {
    @ObservedObject var model: AppModel
    @State private var tab = "Buttons"
    @State private var control = "c82"
    let tabs = ["Buttons", "Point & Scroll", "Gestures", "SmartShift", "DPI Presets"]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SegmentedTabs(items: tabs, selection: $tab)
            content
        }
    }
    private func actionLabel(_ id: String) -> String {
        let profile = model.resolvedSelected
        let action = id == "click" ? profile.gestures["click"] : profile.mouse[id]
        guard let action else { return "Native" }
        return action.displayLabel
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case "Buttons": buttons
        case "Gestures":
            Panel(title: "Thumb button · press, hold and drag") {
                Text("Hold the thumb button, move, then release. A press without movement is a click.").foregroundStyle(.secondary)
                ForEach(["click", "up", "down", "left", "right"], id: \.self) { AssignmentRow(model: model, group: "gestures", key: $0, label: $0.capitalized) }
            }
        case "Point & Scroll":
            Panel(title: "Hardware DPI and pointer speed") {
                Text("Live hardware DPI: \(model.devices[.mouse]?.snapshot.dpi.map(String.init) ?? "Unknown")")
                Text("OS pointer speed is a separate macOS acceleration setting. Logitech normalized values have no verified conversion to DPI.").foregroundStyle(.secondary)
                Button("Open macOS Mouse Settings") { if let url = URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension") { NSWorkspace.shared.open(url) } }.buttonStyle(.pill)
            }
            Panel(title: "Scroll wheels") {
                let base = model.resolvedSelected.scroll ?? ScrollSettings()
                let edit: (@escaping (inout ScrollSettings) -> Void) -> Void = { change in model.editProfile { var s = $0.scroll ?? base; change(&s); $0.scroll = s } }
                Toggle("Natural vertical scrolling", isOn: Binding(get: { base.natural }, set: { v in edit { $0.natural = v } }))
                Toggle("Smooth scrolling", isOn: Binding(get: { base.smooth }, set: { v in edit { $0.smooth = v } }))
                Toggle("Reverse thumb wheel", isOn: Binding(get: { base.horizontalInverted }, set: { v in edit { $0.horizontalInverted = v } }))
                speedRow("Wheel speed", scale: base.verticalScale) { v in edit { $0.verticalScale = v } }
                speedRow("Thumb wheel speed", scale: base.horizontalScale) { v in edit { $0.horizontalScale = v } }
                Text("Applied through macOS, so it needs Accessibility. Trackpads are never changed, and native scrolling returns instantly if the app quits.").font(.caption).foregroundStyle(.secondary)
            }
        case "SmartShift":
            Panel(title: "Wheel mode · live readback") {
                Text("Mode: \(model.devices[.mouse]?.snapshot.wheelMode.map { $0 == 1 ? "Free-spin" : "Ratchet" } ?? "Unknown")")
                HStack {
                    Button("Free-spin; auto-shift off") { model.applyWheel(mode: 1, threshold: 255) }
                    Button("Ratchet; auto-shift off") { model.applyWheel(mode: 2, threshold: 255) }
                    Button("SmartShift auto (50)") { model.applyWheel(mode: 2, threshold: 50) }
                }.buttonStyle(.pill).disabled(model.devices[.mouse]?.snapshot.wheelMode == nil)
                Picker("Desired profile mode", selection: Binding(get: { model.selected.wheelMode ?? 0 }, set: { v in model.editProfile { $0.wheelMode = v == 0 ? nil : v; $0.smartShiftThreshold = v == 0 ? nil : 255 } })) {
                    Text("Inherit / unchanged").tag(0); Text("Free-spin").tag(1); Text("Ratchet").tag(2)
                }
            }
        default: DPIPresetsView(model: model)
        }
    }
    private var buttons: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 18) {
                MouseDiagram(selected: $control, label: actionLabel).frame(width: 360, height: 300)
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Button Actions").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 6).padding(.bottom, 6)
                        FixedRow(label: "Left Click", value: "Click")
                        FixedRow(label: "Right Click", value: "Right Click")
                        row("Middle Click", group: "mouse", key: "c82")
                        row("Forward", group: "mouse", key: "c86")
                        row("Back", group: "mouse", key: "c83")
                        row("Top Button", group: "mouse", key: "c196")
                        row("Thumb Wheel", group: "mouse", key: "thumbWheel")
                        row("Gesture Button", group: "gestures", key: "click")
                    }
                }
            }
            Text("Thumb button swipes are on the Gestures tab.").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func row(_ label: String, group: String, key: String) -> some View {
        AssignmentRow(model: model, group: group, key: key, label: label, highlight: control == key)
    }
    private func speedRow(_ title: String, scale: Double, set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).frame(width: 140, alignment: .leading)
            Slider(value: Binding(get: { log(scale) / log(4) }, set: { set(pow(4, max(-1, min(1, $0)))) }), in: -1...1)
            Text(String(format: "%.2fx", scale)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}

struct DPIPresetsView: View {
    @ObservedObject var model: AppModel
    @State private var name = "Current DPI"
    @State private var dpi = 800
    var range: DPIRange? { model.devices[.mouse]?.snapshot.dpiRange }
    var body: some View {
        Panel(title: "DPI presets") {
            Text(range.map { "Live range: \($0.values.first ?? 0) to \($0.values.last ?? 0) DPI; \($0.values.count) supported values" } ?? "Unavailable: hardware DPI range has not been read. No presets are presented as hardware-validated.").foregroundStyle(.secondary)
            if let current = model.devices[.mouse]?.snapshot.dpi {
                Text("Current device setting: \(current) DPI").foregroundStyle(.secondary)
            }
            ForEach(Array(model.draft.dpiPresets.enumerated()), id: \.element.id) { index, preset in
                HStack {
                    TextField("Name", text: Binding(get: { preset.name }, set: { model.draft.dpiPresets[index].name = $0 })).frame(width: 140)
                    TextField("DPI", value: Binding(get: { preset.dpi }, set: { model.draft.dpiPresets[index].dpi = $0 }), format: .number).frame(width: 90)
                    Text(range?.supports(preset.dpi) == true ? "Range verified" : "Unverified").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") { model.applyDPI(preset.dpi) }.disabled(range?.supports(preset.dpi) != true)
                    Button { model.draft.dpiPresets.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move preset up")
                    Button(role: .destructive) { model.draft.dpiPresets.removeAll { $0.id == preset.id }; for i in model.draft.profiles.indices where model.draft.profiles[i].dpiPreset == preset.id { model.draft.profiles[i].dpiPreset = nil } } label: { Image(systemName: "trash") }.accessibilityLabel("Delete preset")
                }
            }
            HStack { TextField("Preset name", text: $name); TextField("DPI", value: $dpi, format: .number).frame(width: 100); Button("Add") { model.draft.dpiPresets.append(DPIPreset(name: name, dpi: dpi)) }.disabled(range?.supports(dpi) != true || name.isEmpty) }
            Picker("Profile DPI", selection: Binding(get: { model.selected.dpiPreset }, set: { v in model.editProfile { $0.dpiPreset = v } })) {
                Text("Inherit / unchanged").tag(Optional<UUID>.none); ForEach(model.draft.dpiPresets) { Text($0.name).tag(Optional($0.id)) }
            }
            Toggle("Apply per-app hardware settings on app activation", isOn: $model.draft.switchHardwareWithApps)
        }
        .onAppear { if let current = model.devices[.mouse]?.snapshot.dpi { dpi = current } }
    }
}
