import Foundation
import LogiCore

/// Deterministic, device-free stress of the same button, gesture, and scroll
/// state machines used by the app. It never opens a HID device or posts input.
enum StressBenchmark {
    static func run() {
        let requested = CommandLine.arguments.firstIndex(of: "--stress-benchmark")
            .flatMap { index in CommandLine.arguments.indices.contains(index + 1) ? Int(CommandLine.arguments[index + 1]) : nil }
        let iterations = min(max(requested ?? 2_000_000, 1), 200_000_000)
        var buttons = ButtonTransitions()
        var gesture = GestureMachine()
        var wheel = ResidualScaler()
        var smoother = SmoothScroller()
        var checksum = 0
        let start = ProcessInfo.processInfo.systemUptime
        for index in 0..<iterations {
            let control: UInt8 = index.isMultiple(of: 2) ? 0x52 : 0x53
            let changes = try! buttons.update([0, control, 0, 0, 0, 0, 0, 0])
            checksum &+= changes.down.count &+ changes.up.count
            gesture.press(at: Double(index))
            if gesture.move(dx: 260, dy: 0, at: Double(index) + 0.01) != nil { checksum &+= 1 }
            if gesture.release(at: Double(index) + 0.02) != nil { checksum &+= 1 }
            let scaled = wheel.scale(Double(index % 7 - 3), by: 0.75)
            smoother.add(x: Double(scaled), y: Double(-scaled))
            let output = smoother.step(dt: 0.016)
            checksum &+= output.x &+ output.y
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "STRESS iterations=%d elapsed=%.3fs checksum=%d", iterations, elapsed, checksum))
    }
}
