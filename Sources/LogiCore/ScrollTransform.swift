import Foundation

/// Per-axis factors derived from a profile. A negative factor reverses direction.
public struct ScrollTransform: Equatable, Sendable {
    public var verticalFactor = 1.0
    public var horizontalFactor = 1.0
    public var smooth = false
    public var isIdentity: Bool { verticalFactor == 1 && horizontalFactor == 1 && !smooth }
    public init() {}
    /// `systemNatural` is the macOS Natural scrolling preference. Options+ keeps the mouse direction independent of it,
    /// so the wheel is reversed only when the requested direction differs from the system one.
    public init(settings: ScrollSettings, systemNatural: Bool) {
        verticalFactor = settings.verticalScale * (settings.natural == systemNatural ? 1 : -1)
        horizontalFactor = settings.horizontalScale * (settings.horizontalInverted ? -1 : 1)
        smooth = settings.smooth
    }
}
/// Scales integer wheel units while carrying the fractional remainder, so slow settings do not swallow ticks.
public struct ResidualScaler: Sendable {
    private var carry = 0.0
    public init() {}
    public mutating func scale(_ value: Double, by factor: Double) -> Int {
        guard value.isFinite, factor.isFinite else { return 0 }
        let total = value * factor + carry
        let whole = total.rounded(.towardZero)
        carry = total - whole
        return Int(max(-100_000, min(100_000, whole)))
    }
    public mutating func reset() { carry = 0 }
}
/// Spreads accumulated wheel pixels over time with exponential easing. The total distance is conserved.
public struct SmoothScroller: Sendable {
    private var remainX = 0.0, remainY = 0.0
    private var carryX = 0.0, carryY = 0.0
    public init() {}
    public var isIdle: Bool { abs(remainX) < 0.001 && abs(remainY) < 0.001 && abs(carryX) < 0.001 && abs(carryY) < 0.001 }
    public mutating func add(x: Double, y: Double) {
        guard x.isFinite, y.isFinite else { return }
        remainX = max(-20_000, min(20_000, remainX + x)); remainY = max(-20_000, min(20_000, remainY + y))
    }
    public mutating func step(dt: Double, tau: Double = 0.06) -> (x: Int, y: Int) {
        let portion = 1 - exp(-max(0, min(dt, 0.1)) / tau)
        func advance(_ remain: inout Double, _ carry: inout Double) -> Int {
            var emit = remain * portion
            if abs(remain) < 1.5 { emit = remain }
            remain -= emit
            let total = emit + carry
            let whole = abs(remain) < 0.001 ? total.rounded() : total.rounded(.towardZero)
            carry = abs(remain) < 0.001 ? 0 : total - whole
            if abs(remain) < 0.001 { remain = 0 }
            return Int(whole)
        }
        return (advance(&remainX, &carryX), advance(&remainY, &carryY))
    }
    public mutating func cancel() { remainX = 0; remainY = 0; carryX = 0; carryY = 0 }
}
