import SwiftUI
import AppKit
import LogiCore

extension Color {
    static func adaptive(light: Double, dark: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(white: isDark ? dark : light, alpha: 1)
        })
    }
    static let detailBackground = adaptive(light: 1.0, dark: 0.118)
    static let sidebarBackground = adaptive(light: 0.955, dark: 0.16)
    static let cardBackground = adaptive(light: 1.0, dark: 0.165)
    static let fieldBackground = adaptive(light: 1.0, dark: 0.25)
    static let trackBackground = adaptive(light: 0.93, dark: 0.22)
    static let hairline = Color.primary.opacity(0.08)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidPanel(radius: 10)
    }
}

/// Solid card surface with a hairline edge. Follows the light/dark appearance.
struct LiquidPanel: ViewModifier {
    var radius: CGFloat
    var tint: Color?
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: min(radius, 10), style: .continuous)
        content
            .background(shape.fill(tint ?? Color.cardBackground))
            .overlay(shape.strokeBorder(Color.hairline, lineWidth: tint == nil ? 1 : 0))
    }
}
extension View {
    func liquidPanel(radius: CGFloat = 18, tint: Color? = nil) -> some View {
        modifier(LiquidPanel(radius: radius, tint: tint))
    }
}

struct Panel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        Card { VStack(alignment: .leading, spacing: 12) { Text(title).font(.headline); content } }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: ButtonStyleConfiguration) -> some View { PillBody(configuration: configuration, prominent: prominent) }
    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .padding(.horizontal, 12).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(prominent ? Lite.accent : Lite.control))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(prominent ? Color.clear : Color.primary.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(prominent ? 0 : 0.04), radius: 0.5, y: 0.5)
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
        }
    }
}
extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var pillProminent: PillButtonStyle { PillButtonStyle(prominent: true) }
}

struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var back: (() -> Void)?
    var trailing: Trailing
    init(title: String, subtitle: String? = nil, back: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title; self.subtitle = subtitle; self.back = back; self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(.plain).help("Back to Devices").accessibilityLabel("Back to Devices")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(back == nil ? .system(size: 24, weight: .bold) : .system(size: 14, weight: .semibold))
                if let subtitle { Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing
        }
    }
}
extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, back: (() -> Void)? = nil) {
        self.init(title: title, subtitle: subtitle, back: back) { EmptyView() }
    }
}

func batterySymbol(_ percent: Int?) -> String {
    guard let percent else { return "battery.0" }
    switch percent {
    case 88...: return "battery.100"
    case 63..<88: return "battery.75"
    case 38..<63: return "battery.50"
    case 13..<38: return "battery.25"
    default: return "battery.0"
    }
}

struct BatteryLabel: View {
    var percent: Int?
    var status: BatteryStatus? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status?.isCharging == true ? "battery.100.bolt" : batterySymbol(percent))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(percent.map { $0 > 30 || status?.isCharging == true ? Color.green : Color.red } ?? Color.secondary)
            Text(percent.map { "\($0)%" } ?? "Unknown").foregroundStyle(percent == nil ? .secondary : .primary)
            if status?.isCharging == true { Text("Charging").foregroundStyle(.green) }
            if status == .full { Text("Charged").foregroundStyle(.green) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((percent.map { "Battery \($0) percent" } ?? "Battery unknown") + (status?.isCharging == true ? ", charging" : status == .full ? ", fully charged" : ""))
    }
}

/// Compact dropdown field used for action assignments.
struct DropdownField: View {
    var text: String
    var width: CGFloat = 176
    var body: some View {
        HStack(spacing: 6) {
            Text(text).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9).padding(.vertical, 4)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.fieldBackground))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.16), lineWidth: 1))
    }
}

extension Action {
    /// Readable name for dropdowns. Unsupported source actions keep their intent in the tooltip, not the field.
    var displayLabel: String {
        if kind == .requiresConfirmation && note == "Native horizontal scroll" { return "Horizontal scroll (native)" }
        return kind == .requiresConfirmation ? "Needs confirmation" : label
    }
}

/// Full-width tab bar: light track, accent-filled selected segment.
struct SegmentedTabs: View {
    let items: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                let on = selection == item
                Button { selection = item } label: {
                    Text(item).font(.system(size: 12, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? Color.accentColor : Color.clear))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.trackBackground))
    }
}
