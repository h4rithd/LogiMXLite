import SwiftUI
import LogiCore

/// Compact menu-bar list. One click on a device row opens Configuration on that device.
struct LiteMenuView: View {
    @ObservedObject var model: AppModel
    private var connected: Int { model.devices.values.filter(\.connected).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Model.allCases) { row($0) }
            Divider().padding(.vertical, 4).padding(.horizontal, 6)
            HStack(spacing: 6) {
                Circle().fill(connected > 0 ? Lite.green : Color.secondary).frame(width: 6, height: 6)
                Text(connected == 2 ? "Both connected" : connected == 1 ? "One connected" : "No devices")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { model.quit?() } label: {
                    Image(systemName: "power").font(.system(size: 11, weight: .medium)).frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Quit LogiMXLite").accessibilityLabel("Quit LogiMXLite")
            }
            .padding(.horizontal, 8).padding(.bottom, 2)
        }
        .padding(6)
        .frame(width: 220)
        .preferredColorScheme(model.theme)
    }

    private func row(_ m: Model) -> some View {
        let state = model.devices[m]
        let online = state?.connected == true
        let battery = state?.snapshot.battery
        let charge = state?.snapshot.batteryStatus
        return MenuDeviceRow(
            symbol: m == .mouse ? "computermouse" : "keyboard",
            title: m == .mouse ? "MX Master 3S" : "MX Mechanical Mini",
            value: online ? (battery.map { "\($0)%\(charge?.isCharging == true ? " ⚡" : "")" } ?? "—") : "Offline",
            valueColor: online ? (charge?.isCharging == true ? Lite.greenText : (battery ?? 100) > 30 ? Color.primary.opacity(0.6) : Lite.red) : Color.secondary,
            online: online
        ) {
            model.requestedPage = m == .mouse ? .mouse : .keyboard
            model.showSettings?()
        }
        .help(charge?.isCharging == true ? "\(m.name) charging" : "Configure \(m.name)")
        .accessibilityLabel("Configure \(m.name)")
    }
}

private struct MenuDeviceRow: View {
    let symbol: String
    let title: String
    let value: String
    let valueColor: Color
    let online: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(online ? Color.primary : Color.secondary)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 12).monospacedDigit()).foregroundStyle(valueColor)
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Color.primary.opacity(0.08) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
