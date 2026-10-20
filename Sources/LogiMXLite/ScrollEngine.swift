import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import LogiCore
import os

/// Applies per-profile wheel speed, direction and smoothing with a session event tap. Nothing is diverted on the device,
/// so macOS owns scrolling again the moment the tap goes away (quit, crash, permission loss). Trackpad events are untouched.
final class ScrollEngine: @unchecked Sendable {
    static let marker: Int64 = 0x4C4D5343
    /// WebKit and Chromium scroll about 40 px per wheel line, so smooth pixel output uses the same base.
    static let pixelsPerLine = 40.0
    private struct State {
        var transform = ScrollTransform()
        var scroller = SmoothScroller()
        var vLine = ResidualScaler(), vPoint = ResidualScaler(), hLine = ResidualScaler(), hPoint = ResidualScaler()
        var flags: CGEventFlags = []
        var lastTick = DispatchTime.now()
        /// nil keeps native horizontal scrolling; `.none` swallows it; a thumb mode turns steps into actions.
        var thumbMode: ActionKind?
        var thumbInverted = false
        var thumbAccumulator = 0.0
        var lastThumbStep = DispatchTime(uptimeNanoseconds: 0)
    }
    /// Called on the main queue for each thumb-wheel step in a two-way mode.
    var onThumbStep: (@MainActor (ActionKind, Bool) -> Void)?
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let lifecycle = NSLock()
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "LogiMXLite.scroll", qos: .userInteractive)
    private(set) var running = false

    static var systemNatural: Bool {
        (CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication) as? Bool) ?? true
    }
    /// nil settings and nil thumb mode restore plain macOS behavior and remove the tap.
    func configure(_ settings: ScrollSettings?, thumbMode: ActionKind?) {
        let transform = settings.map { ScrollTransform(settings: $0, systemNatural: Self.systemNatural) } ?? ScrollTransform()
        state.withLock { s in
            s.transform = transform; if !transform.smooth { s.scroller.cancel() }
            if s.thumbMode != thumbMode { s.thumbAccumulator = 0 }
            s.thumbMode = thumbMode; s.thumbInverted = settings?.horizontalInverted ?? false
        }
        if transform.isIdentity && thumbMode == nil { stop() } else { start() }
    }
    @discardableResult func start() -> Bool {
        lifecycle.lock(); defer { lifecycle.unlock() }
        guard !running else { return true }
        guard AXIsProcessTrusted() else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue), callback: scrollTapCallback, userInfo: refcon) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.port = port; self.source = source; running = true
        let thread = Thread { [weak self] in
            guard let self, let source = self.source else { return }
            self.lifecycle.lock(); self.runLoop = CFRunLoopGetCurrent(); let activePort = self.port; self.lifecycle.unlock()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            if let activePort { CGEvent.tapEnable(tap: activePort, enable: true) }
            CFRunLoopRun()
        }
        thread.name = "LogiMXLite.scrollTap"; thread.qualityOfService = .userInteractive; thread.start(); self.thread = thread
        return true
    }
    func stop() {
        lifecycle.lock()
        guard running else { lifecycle.unlock(); return }
        running = false
        let port = self.port, source = self.source, loop = self.runLoop
        self.port = nil; self.source = nil; self.runLoop = nil; self.thread = nil
        lifecycle.unlock()
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopSourceInvalidate(source) }
        if let loop { CFRunLoopStop(loop) }
        stopTimer(); state.withLock { $0.scroller.cancel() }
    }
    func reenable() { lifecycle.lock(); let p = port; lifecycle.unlock(); if let p { CGEvent.tapEnable(tap: p, enable: true) } }

    fileprivate func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker { return Unmanaged.passUnretained(event) }
        // Trackpads and Magic Mouse always report gesture phases; they stay untouched.
        if event.getIntegerValueField(.scrollWheelEventScrollPhase) != 0 || event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return Unmanaged.passUnretained(event) }
        // A high-resolution wheel already arrives smooth (continuous, no phase), so only speed and direction are applied.
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        let rawY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)), rawX = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let pointY = rawY == 0 ? lineY * 10 : rawY, pointX = rawX == 0 ? lineX * 10 : rawX
        if lineY == 0 && lineX == 0 && pointY == 0 && pointX == 0 { return Unmanaged.passUnretained(event) }
        let fixedY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), fixedX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        if lineY == 0 && rawY == 0 && fixedY == 0, let step = thumbStep(continuous ? pointX / 10 : (fixedX != 0 ? fixedX : lineX)) {
            if let (mode, forward) = step { Task { @MainActor [weak self] in self?.onThumbStep?(mode, forward) } }
            return nil
        }
        let flags = event.flags
        let smooth: Bool = state.withLock { s in
            s.flags = flags
            if s.transform.smooth && !continuous {
                // The fixed-point delta carries macOS wheel acceleration.
                let ly = fixedY != 0 ? fixedY : lineY, lx = fixedX != 0 ? fixedX : lineX
                s.scroller.add(x: lx * Self.pixelsPerLine * s.transform.horizontalFactor, y: ly * Self.pixelsPerLine * s.transform.verticalFactor)
                return true
            }
            return false
        }
        if smooth { startTimer(); return nil }
        let out: (Int, Int, Int, Int, Double, Double) = state.withLock { s in
            let t = s.transform
            return (s.vLine.scale(lineY, by: t.verticalFactor), s.hLine.scale(lineX, by: t.horizontalFactor),
                    s.vPoint.scale(pointY, by: t.verticalFactor), s.hPoint.scale(pointX, by: t.horizontalFactor),
                    fixedY * t.verticalFactor, fixedX * t.horizontalFactor)
        }
        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(out.0))
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(out.1))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(out.2))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(out.3))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: out.4)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: out.5)
        return Unmanaged.passUnretained(event)
    }
    /// Thumb wheel = horizontal-only wheel input. Returns nil to pass the event through, .some(nil) to swallow it,
    /// and .some(step) when a full notch completed in a two-way mode.
    private func thumbStep(_ lines: Double) -> (ActionKind, Bool)?? {
        state.withLock { s -> (ActionKind, Bool)?? in
            guard let mode = s.thumbMode else { return nil }
            guard mode.isThumbMode else { return .some(nil) }
            s.thumbAccumulator += s.thumbInverted ? -lines : lines
            guard abs(s.thumbAccumulator) >= 1 else { return .some(nil) }
            let forward = s.thumbAccumulator < 0
            s.thumbAccumulator = 0
            // Desktop and app switching animate; one switch per 350 ms keeps a fast flick from skipping several.
            let now = DispatchTime.now()
            if [.thumbDesktops, .thumbApps].contains(mode), now.uptimeNanoseconds &- s.lastThumbStep.uptimeNanoseconds < 350_000_000 { return .some(nil) }
            s.lastThumbStep = now
            return .some((mode, forward))
        }
    }
    private func startTimer() {
        queue.async { [self] in
            guard timer == nil else { return }
            state.withLock { $0.lastTick = .now() }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t; t.resume()
        }
    }
    private func stopTimer() { queue.async { [self] in timer?.cancel(); timer = nil } }
    private func tick() {
        let now = DispatchTime.now()
        let (dx, dy, flags, idle): (Int, Int, CGEventFlags, Bool) = state.withLock { s in
            let dt = Double(now.uptimeNanoseconds &- s.lastTick.uptimeNanoseconds) / 1e9
            s.lastTick = now
            let out = s.scroller.step(dt: dt)
            return (out.x, out.y, s.flags, s.scroller.isIdle)
        }
        if dx != 0 || dy != 0, let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0) {
            event.setIntegerValueField(.eventSourceUserData, value: Self.marker); event.flags = flags
            event.post(tap: .cgSessionEventTap)
        }
        if idle { timer?.cancel(); timer = nil }
    }
}

private func scrollTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<ScrollEngine>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { engine.reenable(); return Unmanaged.passUnretained(event) }
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
    return engine.handle(event)
}
