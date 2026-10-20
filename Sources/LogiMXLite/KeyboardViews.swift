import SwiftUI
import LogiCore

struct SpecialKey: Identifiable {
    let id: String      // source control id, matched only to live-enumerated CIDs
    let name: String
    let symbol: String?
    let short: String
}

struct KeyboardView: View {
    @ObservedObject var model: AppModel
    @State private var tab = "Keys"
    @State private var selected = "c212"
    @State private var duration = 30
    static let keys: [SpecialKey] = [
        SpecialKey(id: "c212", name: "Search", symbol: "magnifyingglass", short: ""),
        SpecialKey(id: "c226", name: "Backlight Down", symbol: "light.min", short: ""),
        SpecialKey(id: "c227", name: "Backlight Up", symbol: "light.max", short: ""),
        SpecialKey(id: "c259", name: "Dictation", symbol: "mic", short: ""),
        SpecialKey(id: "c264", name: "Emoji", symbol: "face.smiling", short: ""),
        SpecialKey(id: "c266", name: "Screenshot", symbol: "camera.viewfinder", short: ""),
        SpecialKey(id: "c284", name: "Microphone Mute", symbol: "mic.slash", short: ""),
        SpecialKey(id: "c285", name: "Do Not Disturb", symbol: "moon", short: ""),
        SpecialKey(id: "c321", name: "Play / Pause", symbol: "playpause", short: ""),
        SpecialKey(id: "c231", name: "Mute", symbol: "speaker.slash", short: ""),
        SpecialKey(id: "c232", name: "Volume Down", symbol: "speaker.wave.1", short: ""),
        SpecialKey(id: "c233", name: "Volume Up", symbol: "speaker.wave.3", short: ""),
        SpecialKey(id: "c280", name: "Home", symbol: nil, short: "Home"),
        SpecialKey(id: "c281", name: "End", symbol: nil, short: "End"),
        SpecialKey(id: "c282", name: "Page Up", symbol: nil, short: "PgUp"),
        SpecialKey(id: "c283", name: "Page Down", symbol: nil, short: "PgDn")
    ]
    private func verified(_ key: String) -> Bool {
        model.devices[.keyboard]?.snapshot.controls.contains { "c\($0.id)" == key && $0.divertible } == true
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SegmentedTabs(items: ["Keys", "Backlight", "Fn Mode"], selection: $tab)
            content
        }
    }
    @ViewBuilder private var content: some View {
        switch tab {
        case "Keys": keys
        case "Backlight":
            Panel(title: "Backlighting") {
                if let b = model.devices[.keyboard]?.snapshot.backlight {
                    Text("Readback: mode \(b.mode), level \(b.level), effect \(b.effect), hands-out duration \(b.duration)s")
                    HStack {
                        Button("Off") { model.applyBacklight(mode: 0) }
                        Button("Automatic") { model.applyBacklight(mode: 1) }.disabled(!b.supportsAuto)
                        Button("Manual") { model.applyBacklight(mode: 3) }.disabled(!b.supportsManual)
                    }.buttonStyle(.pill)
                    Picker("Brightness", selection: Binding(get: { b.level }, set: { model.applyBacklight(mode: 3, level: $0) })) { ForEach(0..<b.levels, id: \.self) { Text(String($0)).tag($0) } }.disabled(!b.supportsManual)
                    HStack { Stepper("Hands-out duration: \(duration)s", value: $duration, in: 5...600, step: 5); Button("Apply Duration") { model.applyBacklight(seconds: duration) }.buttonStyle(.pill) }
                    Picker("Effect", selection: Binding(get: { b.effect }, set: { model.applyBacklight(effect: $0) })) {
                        ForEach(Array(["Static", "None", "Breathing", "Contrast", "Reaction", "Random", "Waves"].enumerated()), id: \.offset) { i, n in if b.effects & (1 << i) != 0 { Text(n).tag(i) } }
                    }
                } else {
                    Text("Backlight state not read yet. Wake the keyboard, then use Retry Devices.").foregroundStyle(.secondary)
                }
            }
        case "Fn Mode":
            Panel(title: "Function-key inversion") {
                Text("Live state: \(model.devices[.keyboard]?.snapshot.fnInverted.map { $0 ? "Inverted" : "Normal" } ?? "Unknown")")
                Toggle("Invert function-key mode", isOn: Binding(get: { model.devices[.keyboard]?.snapshot.fnInverted ?? false }, set: model.applyFn)).disabled(model.devices[.keyboard]?.snapshot.fnInverted == nil)
            }
        default: EmptyView()
        }
    }
    private var keys: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                DevicePhoto(model: .keyboard).frame(width: 600).frame(maxWidth: .infinity)
                VStack(spacing: 8) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 16), spacing: 4) {
                        ForEach(Self.keys) { key in tile(key) }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color(white: 0.16)))
                    .frame(width: 600)
                }.frame(maxWidth: .infinity)
            }
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Special Keys").font(.system(size: 13, weight: .semibold)).padding(.horizontal, 6).padding(.bottom, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 2) {
                        ForEach(Self.keys) { key in
                            AssignmentRow(model: model, group: "keyboard", key: key.id, label: key.name, highlight: selected == key.id)
                        }
                    }
                }
            }
            Text("Keys set to their own built-in function (backlight, mute, volume, dictation, Do Not Disturb) are left to the keyboard.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func tile(_ key: SpecialKey) -> some View {
        let live = verified(key.id)
        let isSelected = selected == key.id
        return Button { selected = key.id } label: {
            Group {
                if let symbol = key.symbol { Image(systemName: symbol).font(.system(size: 10)) }
                else { Text(key.short).font(.system(size: 7.5, weight: .medium)) }
            }
            .foregroundStyle(Color.white.opacity(live ? 1 : 0.45))
            .frame(maxWidth: .infinity, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(white: live ? 0.52 : 0.34), Color(white: live ? 0.36 : 0.24)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help("\(key.name): " + (live ? "remappable" : "native only"))
        .accessibilityLabel(key.name)
    }
}
