import SwiftUI
import AppKit
import LogiCore

/// Product renders supplied by the user from their UI reference, for personal local use.
/// See docs/THIRD_PARTY_NOTICES.md. Vector drawings below are the fallback if a file is missing.
enum DeviceImages {
    static func image(for model: Model) -> NSImage? {
        let name = model == .mouse ? "mx-master-3s" : "mx-mechanical-mini"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Real render when available, vector fallback otherwise.
struct DevicePhoto: View {
    let model: Model
    var body: some View {
        if let image = DeviceImages.image(for: model) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .shadow(color: Color.black.opacity(0.22), radius: 8, y: 6)
                .accessibilityHidden(true)
        } else if model == .mouse {
            MouseArt().scaledToFit()
        } else {
            KeyboardArt(width: 340, legends: false) { KeyboardArt<EmptyView>.defaultTopRow(width: 340) }.scaledToFit()
        }
    }
}

/// Original vector renderings. No Logitech product photography or marks are used.
struct MouseArt: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.28)).frame(width: 130, height: 26).blur(radius: 9).position(x: 108, y: 246)
            // Body
            MouseBody().fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            MouseBody().fill(RadialGradient(colors: [Color.white.opacity(0.30), .clear], center: UnitPoint(x: 0.62, y: 0.18), startRadius: 2, endRadius: 120))
            // Rubber thumb pad with grip texture
            ThumbPad().fill(Color(white: 0.07))
            Canvas { ctx, _ in
                var dots = Path()
                for row in 0..<14 { for col in 0..<8 {
                    let x = 38 + CGFloat(col) * 6.5 + (row % 2 == 0 ? 0 : 3)
                    let y = 140 + CGFloat(row) * 6.3
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                } }
                ctx.clip(to: ThumbPad().path(in: CGRect(x: 0, y: 0, width: 200, height: 260)))
                ctx.fill(dots, with: .color(Color.white.opacity(0.16)))
            }
            // Button seams
            Path { p in
                p.move(to: CGPoint(x: 100, y: 8)); p.addLine(to: CGPoint(x: 100, y: 40))
                p.move(to: CGPoint(x: 100, y: 92)); p.addLine(to: CGPoint(x: 100, y: 112))
                p.move(to: CGPoint(x: 62, y: 112)); p.addCurve(to: CGPoint(x: 148, y: 112), control1: CGPoint(x: 90, y: 118), control2: CGPoint(x: 120, y: 118))
            }.stroke(Color.black.opacity(0.65), lineWidth: 1.3)
            // Scroll wheel in a dark recess
            RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.85)).frame(width: 24, height: 56).position(x: 100, y: 64)
            Ridged(width: 17, height: 46, horizontal: true).position(x: 100, y: 64)
            // Mode-shift button behind the wheel
            Capsule().fill(LinearGradient(colors: [Color(white: 0.75), Color(white: 0.45)], startPoint: .top, endPoint: .bottom)).frame(width: 10, height: 20).position(x: 100, y: 102)
            // Thumb wheel
            RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.9)).frame(width: 18, height: 40).rotationEffect(.degrees(-14)).position(x: 47, y: 114)
            Ridged(width: 11, height: 32, horizontal: false).rotationEffect(.degrees(-14)).position(x: 47, y: 114)
            // Side buttons and gesture button
            Capsule().fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.28)], startPoint: .leading, endPoint: .trailing)).frame(width: 7, height: 24).rotationEffect(.degrees(-10)).position(x: 41, y: 146)
            Capsule().fill(LinearGradient(colors: [Color(white: 0.5), Color(white: 0.28)], startPoint: .leading, endPoint: .trailing)).frame(width: 7, height: 24).rotationEffect(.degrees(-14)).position(x: 38, y: 174)
            Circle().fill(RadialGradient(colors: [Color(white: 0.7), Color(white: 0.35)], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 14, height: 14).position(x: 40, y: 202)
            // Rim light
            MouseBody().stroke(LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
        }
        .frame(width: 200, height: 260)
        .accessibilityHidden(true)
    }
}

private struct Ridged: View {
    let width: CGFloat
    let height: CGFloat
    let horizontal: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(white: 0.88), Color(white: 0.42), Color(white: 0.8)], startPoint: horizontal ? .leading : .top, endPoint: horizontal ? .trailing : .bottom))
            Canvas { ctx, size in
                var lines = Path()
                if horizontal { var y: CGFloat = 3; while y < size.height { lines.move(to: CGPoint(x: 0, y: y)); lines.addLine(to: CGPoint(x: size.width, y: y)); y += 3.2 } }
                else { var x: CGFloat = 3; while x < size.width { lines.move(to: CGPoint(x: x, y: 0)); lines.addLine(to: CGPoint(x: x, y: size.height)); x += 3.2 } }
                ctx.stroke(lines, with: .color(Color.black.opacity(0.35)), lineWidth: 0.8)
            }.clipShape(RoundedRectangle(cornerRadius: 6))
        }.frame(width: width, height: height)
    }
}

private struct ThumbPad: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 46, y: 128))
        p.addCurve(to: CGPoint(x: 31, y: 160), control1: CGPoint(x: 38, y: 134), control2: CGPoint(x: 32, y: 146))
        p.addCurve(to: CGPoint(x: 64, y: 226), control1: CGPoint(x: 30, y: 190), control2: CGPoint(x: 42, y: 212))
        p.addCurve(to: CGPoint(x: 92, y: 196), control1: CGPoint(x: 78, y: 224), control2: CGPoint(x: 90, y: 214))
        p.addCurve(to: CGPoint(x: 78, y: 140), control1: CGPoint(x: 94, y: 176), control2: CGPoint(x: 86, y: 154))
        p.addCurve(to: CGPoint(x: 46, y: 128), control1: CGPoint(x: 70, y: 134), control2: CGPoint(x: 58, y: 128))
        p.closeSubpath()
        return p
    }
}

private struct MouseBody: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 70, y: 10))
        p.addCurve(to: CGPoint(x: 130, y: 14), control1: CGPoint(x: 90, y: 2), control2: CGPoint(x: 115, y: 4))
        p.addCurve(to: CGPoint(x: 160, y: 130), control1: CGPoint(x: 154, y: 40), control2: CGPoint(x: 164, y: 90))
        p.addCurve(to: CGPoint(x: 120, y: 240), control1: CGPoint(x: 158, y: 184), control2: CGPoint(x: 148, y: 228))
        p.addCurve(to: CGPoint(x: 60, y: 234), control1: CGPoint(x: 100, y: 250), control2: CGPoint(x: 75, y: 248))
        p.addCurve(to: CGPoint(x: 26, y: 150), control1: CGPoint(x: 34, y: 216), control2: CGPoint(x: 20, y: 182))
        p.addCurve(to: CGPoint(x: 48, y: 100), control1: CGPoint(x: 30, y: 124), control2: CGPoint(x: 42, y: 112))
        p.addCurve(to: CGPoint(x: 70, y: 10), control1: CGPoint(x: 50, y: 60), control2: CGPoint(x: 55, y: 30))
        p.closeSubpath()
        return p
    }
}

/// 75 percent style Mac keyboard drawn from key units. `topRow` replaces the function row.
struct KeyboardArt<TopRow: View>: View {
    var width: CGFloat = 440
    var legends = true
    @ViewBuilder var topRow: TopRow
    private let gap: CGFloat = 3
    private var unit: CGFloat { (width - 24 - 14 * gap) / 15 }
    private var keyHeight: CGFloat { unit * 0.9 }
    private typealias K = (String, CGFloat)
    private var rows: [[K]] {
        let r1: [K] = ["`", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="].map { ($0, 1) } + [("delete", 2)]
        let r2: [K] = [("tab", 1.5)] + "QWERTYUIOP[]".map { (String($0), 1) } + [("\\", 1.5)]
        let r3: [K] = [("caps", 1.75)] + "ASDFGHJKL;'".map { (String($0), 1) } + [("return", 2.25)]
        let r4: [K] = [("shift", 2.25)] + "ZXCVBNM,./".map { (String($0), 1) } + [("shift", 2.75)]
        let r5: [K] = [("fn", 1), ("ctrl", 1), ("opt", 1.25), ("cmd", 1.25), ("", 5), ("cmd", 1.25), ("opt", 1.25), ("◀", 1), ("▼", 1), ("▶", 1)]
        return [r1, r2, r3, r4, r5]
    }
    var body: some View {
        VStack(spacing: gap) {
            topRow
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) { ForEach(Array(row.enumerated()), id: \.offset) { _, key in cap(key.0, key.1) } }
            }
        }
        .padding(12)
        .frame(width: width)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.20), lineWidth: 1)
            }.shadow(color: Color.black.opacity(0.25), radius: 8, y: 5)
        )
    }
    static func defaultTopRow(width: CGFloat) -> some View {
        let gap: CGFloat = 3
        let unit = (width - 24 - 14 * gap) / 15
        return HStack(spacing: gap) {
            ForEach(0..<14, id: \.self) { i in
                let w: CGFloat = (i == 0 || i == 13) ? 1.5 : 1
                RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.21)], startPoint: .top, endPoint: .bottom))
                    .frame(width: w * unit + (w - 1) * gap, height: unit * 0.7)
            }
        }
    }
    private func cap(_ label: String, _ w: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(white: 0.36), Color(white: 0.24)], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            if legends && unit > 24 { Text(label).font(.system(size: label.count > 1 ? unit * 0.2 : unit * 0.3, weight: .medium)).foregroundStyle(Color.white.opacity(0.8)) }
        }
        .frame(width: w * unit + (w - 1) * gap, height: keyHeight)
    }
}
