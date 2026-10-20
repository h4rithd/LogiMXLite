import Foundation

/// Thumb-button gesture, matching Options+ ButtonGesture4wayState (sensitivity 0): movement under 50 raw units is a
/// click on release; once movement along one axis reaches 250 the action fires immediately while the button is held,
/// then again after each further 250 once the action pause has passed.
public struct GestureMachine: Sendable {
    public enum Direction: String, Sendable { case click, up, down, left, right }
    public let startThreshold: Double
    public let actionThreshold: Double
    public let pause: Double
    private var pressed = false
    private var x = 0.0, y = 0.0
    private var started = false
    private var fired = false
    private var lastAction = -Double.infinity
    public init(startThreshold: Double = 50, actionThreshold: Double = 250, pause: Double = 0.4) {
        self.startThreshold = startThreshold; self.actionThreshold = actionThreshold; self.pause = pause
    }
    public mutating func press(at time: Double) { cancel(); pressed = true }
    /// Returns a direction when an action fires during the hold.
    public mutating func move(dx: Double, dy: Double, at time: Double) -> Direction? {
        guard pressed, dx.isFinite, dy.isFinite else { return nil }
        // Options+ snaps each raw movement sample to one axis when that axis is at
        // least twice the other. Near-diagonal movement is ignored rather than
        // arbitrarily becoming horizontal or vertical at the action threshold.
        let horizontal = abs(dx) >= 2 * abs(dy)
        let vertical = abs(dy) >= 2 * abs(dx)
        let snappedX = horizontal ? dx : 0
        let snappedY = !horizontal && vertical ? dy : 0
        x = max(-10000, min(10000, x + snappedX)); y = max(-10000, min(10000, y + snappedY))
        if !started && hypot(x, y) >= startThreshold { started = true }
        guard started, max(abs(x), abs(y)) >= actionThreshold, time - lastAction >= pause else { return nil }
        let direction: Direction = abs(x) >= abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .down : .up)
        x = 0; y = 0; fired = true; lastAction = time
        return direction
    }
    /// Returns `.click` only when the press never turned into a gesture.
    public mutating func release(at time: Double) -> Direction? {
        defer { cancel() }
        return pressed && !started && !fired ? .click : nil
    }
    public mutating func cancel() { pressed = false; x = 0; y = 0; started = false; fired = false; lastAction = -Double.infinity }
}
public struct ButtonTransitions: Sendable {
    private var pressed: Set<UInt16> = []
    public init() {}
    public mutating func update(_ payload: [UInt8]) throws -> (down: Set<UInt16>, up: Set<UInt16>) {
        guard payload.count >= 8 else { throw HIDError.malformed }
        var next = Set<UInt16>()
        for i in stride(from:0,to:8,by:2) { let id = UInt16(payload[i]) << 8 | UInt16(payload[i+1]); if id != 0 { next.insert(id) } }
        let result = (next.subtracting(pressed),pressed.subtracting(next)); pressed = next; return result
    }
    public mutating func cancel() { pressed.removeAll() }
}
public struct ProfileRevision: Sendable {
    private var generation: UInt64 = 0
    public init() {}
    public mutating func next() -> UInt64 { generation &+= 1; return generation }
    public func isCurrent(_ value: UInt64) -> Bool { generation == value }
}
public enum ConflictDetector {
    public static func matches(_ bundle: String) -> Bool {
        let b = bundle.lowercased()
        return b.hasPrefix("com.logi.") || b.hasPrefix("com.logitech.") || b == "com.mxcontrol.app" || b.contains("openlogi") || b.hasPrefix("com.better-mouse.")
    }
}
public enum PermissionGate: Equatable, Sendable {
    case ready, inputMonitoring, accessibility, secureInput, conflict
    public static func evaluate(input: Bool, accessibility: Bool, secure: Bool, conflicts: Bool) -> PermissionGate {
        if !input { return .inputMonitoring }
        if !accessibility { return .accessibility }
        if secure { return .secureInput }
        if conflicts { return .conflict }
        return .ready
    }
}
