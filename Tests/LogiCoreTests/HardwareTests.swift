import Foundation
import Testing
@testable import LogiCore

@Test func unifiedBatteryChargeStatus() {
    #expect(BatteryStatus.parse([30, 2, 0]) == .discharging)
    #expect(BatteryStatus.parse([30, 2, 1])?.isCharging == true)
    #expect(BatteryStatus.parse([30, 2, 2])?.isCharging == true)
    #expect(BatteryStatus.parse([100, 8, 3]) == .full)
    #expect(BatteryStatus.parse([30, 2]) == nil)
    #expect(BatteryStatus.parse([30, 2, 255]) == nil)
}

actor MockTransport: ReportTransport {
    var dpi = 1600
    var wheel: [UInt8] = [2,50,30]
    var fn: UInt8 = 0
    var reporting: [UInt16:UInt8] = [:]
    var writes: [(Model,UInt8,UInt8,[UInt8])] = []
    var failReadback = false
    var readbackArmed = false
    var disconnected = false
    var backlight: [UInt8] = [1,0x0C,0x28,0x7F,0,3,6,0,12,0,18,0,24,0,0,0]
    var effect: UInt8 = 4
    var zeroBrightnessWhenOff = false
    let ids: [UInt16] = [0x1004,0x2201,0x2111,0x1B04,0x1982,0x40A3,0x1814,0x1815]
    func setFailure(_ v: Bool) { failReadback = v }
    func disconnect(_ v: Bool) { disconnected = v }
    func writeCount() -> Int { writes.count }
    func currentDPI() -> Int { dpi }
    func diverted() -> Bool { reporting.values.contains { $0 & 1 != 0 } }
    func seed(_ id: UInt16, _ value: UInt8) { reporting[id] = value }
    func configureOffBrightnessReadback() {
        zeroBrightnessWhenOff = true
        backlight[0] = 0
        backlight[5] = 0
    }
    func state(_ id: UInt16) -> UInt8 { reporting[id] ?? 0 }
    func request(_ model: Model, feature: UInt8, function: UInt8, parameters: [UInt8]) async throws -> Packet {
        if disconnected { throw HIDError.disconnected }
        var p: [UInt8] = []
        if feature == 0 && function == 1 { p = [2,0,parameters[2]] }
        else if feature == 0 && function == 0 { p = [10,0,0] }
        else if feature == 10 && function == 0 {p = [UInt8(ids.count)]}
        else if feature == 10 && function == 1 {
            let id = ids[Int(parameters[0])-1]; p = [UInt8(id>>8),UInt8(id&255),0,id == 0x1982 ? 3 : id == 0x1815 ? 2 : 0]
        } else {
            guard feature > 0, Int(feature) <= ids.count else { throw HIDError.malformed }
            switch ids[Int(feature)-1] {
            case 0x1004: p = function == 0 ? [15,3] : [78,4,0]
            case 0x1814: p = [3,0,0]
            case 0x1815:
                let names = ["First Mac", "This Mac", "Work PC"]
                switch function {
                case 0: p = [1,8,3,0]
                case 1:
                    let index = Int(parameters[0]); p = [UInt8(index),1,4,1,UInt8(names[index].utf8.count),64]
                case 3:
                    let index = Int(parameters[0]); let offset = Int(parameters[1])
                    p = [UInt8(index),UInt8(offset)] + Array(names[index].utf8.dropFirst(offset).prefix(14))
                default: throw HIDError.malformed
                }
            case 0x2201:
                switch function {
                case 0:p = [1]
                case 1:p = [0,0,100,0xE0,50,0x1F,0x40]
                case 2:
                    if readbackArmed { readbackArmed = false; if failReadback { p = [0,3,32,3,32]; break } }
                    p = [0,UInt8(dpi>>8),UInt8(dpi&255),3,32]
                case 3:dpi = Int(parameters[1]) << 8 | Int(parameters[2]); writes.append((model,feature,function,parameters)); readbackArmed = true
                default:throw HIDError.malformed
                }
            case 0x2111:
                if function == 1 {p = wheel}
                else if function == 2 {writes.append((model,feature,function,parameters)); wheel[0] = parameters[0]; wheel[1] = parameters[1]; p = wheel}
            case 0x40A3:
                if function == 1 {writes.append((model,feature,function,parameters)); fn=parameters[1]}
                p = [0,fn,0,1]
            case 0x1982:
                switch function {
                case 0:p = backlight
                case 1:
                    writes.append((model,feature,function,parameters))
                    backlight[0] = parameters[0]; backlight[1] = parameters[1]; backlight[5] = parameters[3]
                    backlight.replaceSubrange(6...13,with:parameters[4...11])
                    if zeroBrightnessWhenOff && backlight[0] == 0 { backlight[5] = 0 }
                case 2:p = [8,backlight[5],2,effect] + Array(repeating:0,count:12)
                case 3:effect=parameters[0];writes.append((model,feature,function,parameters))
                default:throw HIDError.malformed
                }
            case 0x1B04:
                let id: UInt16 = parameters.count >= 2 ? UInt16(parameters[0]) << 8 | UInt16(parameters[1]) : 0
                switch function {
                case 0:p = [2]
                case 1:p = parameters[0] == 0 ? [0,82,0,56,0x30,0,0,0,0] : [0,195,0,0,0x30,0,0,0,1]
                case 2:p = [UInt8(id>>8),UInt8(id&255),reporting[id] ?? 0,0,0,0]
                case 3:
                    writes.append((model,feature,function,parameters))
                    let flags = parameters[2]; var r = reporting[id] ?? 0
                    if flags & 2 != 0 {r = (r & ~1) | (flags & 1)}
                    if flags & 8 != 0 {r = (r & ~4) | (flags & 4)}
                    if flags & 0x20 != 0 {r = (r & ~0x10) | (flags & 0x10)}
                    reporting[id]=r; p=parameters
                default:throw HIDError.malformed
                }
            default:throw HIDError.malformed
            }
        }
        return try Packet(bytes:Packet(feature:feature,function:function,parameters:p).bytes)
    }
}
@Test func probeAndDPIReadbackIdempotence() async throws {
    let transport = MockTransport(); let hardware = Hardware(transport:transport)
    let state = try await hardware.probe(.mouse)
    #expect(state.dpi == 1600); #expect(state.battery == 78); #expect(state.batteryStatus == .discharging)
    #expect(state.hostCount == 3); #expect(state.currentHost == 1); #expect(state.controls.count == 2)
    #expect(state.hosts.map(\.name) == ["First Mac", "This Mac", "Work PC"])
    #expect(state.dpiRange?.supports(1650) == true)
    #expect(try await hardware.setDPI(1600) == 1600)
    #expect(await transport.writeCount() == 0)
    #expect(try await hardware.setDPI(1650) == 1650)
    #expect(await transport.writeCount() == 1)
    await #expect(throws:HIDError.self) {try await hardware.setDPI(1651)}
    #expect(await transport.writeCount() == 1)
}
@Test func failedDPIReadbackRestoresPriorValue() async throws {
    let transport = MockTransport(); let hardware = Hardware(transport:transport)
    _ = try await hardware.probe(.mouse); await transport.setFailure(true)
    await #expect(throws:HIDError.self) {try await hardware.setDPI(1700)}
    #expect(await transport.currentDPI() == 1600)
    #expect(await transport.writeCount() == 2)
}
@Test func temporaryDiversionRestorationAndUnknownControl() async throws {
    let transport = MockTransport(); let hardware = Hardware(transport:transport)
    _ = try await hardware.probe(.mouse)
    await #expect(throws:HIDError.self) {try await hardware.divert(.mouse,ids:[1])}
    #expect(await transport.writeCount() == 0)
    try await hardware.divert(.mouse,ids:[82,195]); #expect(await transport.diverted())
    #expect(await hardware.restore()); #expect(!(await transport.diverted()))
}
@Test func disconnectReconnectDropsCapabilityCache() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    _ = try await h.probe(.mouse); await t.disconnect(true)
    await #expect(throws:HIDError.self) {try await h.setDPI(1800)}
    await h.forget(.mouse); await t.disconnect(false)
    await #expect(throws:HIDError.self) {try await h.setDPI(1800)}
    _ = try await h.probe(.mouse)
    #expect(try await h.setDPI(1800) == 1800)
}
@Test func keyboardFieldsReadbackAndPreservation() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    let initial = try await h.probe(.keyboard)
    #expect(initial.fnInverted == false)
    #expect(initial.backlight?.duration == 30)
    #expect(try await h.setFn(true))
    let b = try await h.setBacklight(mode:3,level:5,seconds:45,effect:4)
    #expect(b.mode == 3); #expect(b.level == 5); #expect(b.duration == 45); #expect(b.config[12] == 24)
    let off = try await h.setBacklight(mode:0,level:nil,seconds:nil,effect:nil)
    #expect(!off.enabled && off.mode == 3)
    let timedOff = try await h.setBacklight(mode:nil,level:nil,seconds:50,effect:nil)
    #expect(!timedOff.enabled && timedOff.mode == 3 && timedOff.duration == 50)
    let on = try await h.setBacklight(mode:3,level:nil,seconds:nil,effect:nil)
    #expect(on.enabled && on.mode == 3 && on.level == 5)
    await #expect(throws:HIDError.self) {try await h.setBacklight(mode:nil,level:99,seconds:nil,effect:nil)}
}
@Test func savedOffModeIgnoresBrightnessThatHardwareCannotReport() async throws {
    let transport = MockTransport(); await transport.configureOffBrightnessReadback()
    let hardware = Hardware(transport:transport)
    let initial = try await hardware.probe(.keyboard)
    #expect(initial.backlight?.enabled == false)
    #expect(initial.backlight?.level == 0)
    let off = try await hardware.setBacklight(mode:0,level:7,seconds:30,effect:4)
    #expect(!off.enabled)
    #expect(await transport.writeCount() == 0)
    let on = try await hardware.setBacklight(mode:3,level:7,seconds:30,effect:4)
    #expect(on.enabled && on.level == 7)
    let offAgain = try await hardware.setBacklight(mode:0,level:7,seconds:30,effect:4)
    #expect(!offAgain.enabled && offAgain.level == 0)
}
@Test func wheelReadbackAndSerializedWrites() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    _ = try await h.probe(.mouse)
    let wheel = try await h.setWheel(mode:1,threshold:255)
    #expect(wheel.0 == 1 && wheel.1 == 255)
    async let a = h.setDPI(1800)
    async let b = h.setDPI(2000)
    let values = try await [a,b]
    #expect(Set(values) == [1800,2000])
    #expect([1800,2000].contains(await t.currentDPI()))
}
@Test func backlightRejectsShortOrMalformedPayload() {
    #expect(throws:HIDError.self) {try BacklightState.parse(config:[1,0,0],info:[8,3,2,4])}
    #expect(throws:HIDError.self) {try BacklightState.parse(config:Array(repeating:0,count:16),info:Array(repeating:255,count:16))}
}
actor BusyTransport: ReportTransport {
    var attempts = 0
    let forever: Bool
    init(forever: Bool) { self.forever=forever }
    func count() -> Int { attempts }
    func request(_ model: Model, feature: UInt8, function: UInt8, parameters: [UInt8]) async throws -> Packet {
        if feature == 0 && function == 1 {
            attempts += 1
            if forever || attempts < 3 {throw HIDError.protocolError(8)}
            return try Packet(feature:0,function:1,parameters:[2,0,parameters[2]])
        }
        return try Packet(feature:feature,function:function,parameters:feature == 0 ? [1,0,0] : [0])
    }
}
@Test func busyRetriesAreBounded() async throws {
    let fail = BusyTransport(forever:true); let h = Hardware(transport:fail)
    await #expect(throws:HIDError.self) {try await h.probe(.mouse)}
    #expect(await fail.count() == 3)
    let recover = BusyTransport(forever:false)
    _ = try await Hardware(transport:recover).probe(.mouse)
    #expect(await recover.count() == 3)
}
@Test func preCancelledTransactionNeverWrites() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    _ = try await h.probe(.mouse)
    let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await h.setDPI(1800) }
    task.cancel()
    _ = try? await task.value
    #expect(await t.writeCount() == 0)
}
@Test func repeatedGestureAndReconnectSimulation() async throws {
    var g = GestureMachine(); var buttons = ButtonTransitions()
    for i in 0..<10000 {
        let now = Double(i)
        g.press(at:now); #expect(g.move(dx:300,dy:0,at:now+0.1) == .right)
        #expect(g.release(at:now+0.2) == nil)
        _ = try buttons.update([0,82,0,0,0,0,0,0]); buttons.cancel()
    }
    let t = MockTransport(); let h = Hardware(transport:t)
    for _ in 0..<25 { _ = try await h.probe(.mouse); try await h.divert(.mouse,ids:[82]); #expect(await h.restore()); await h.forget(.mouse) }
    #expect(!(await t.diverted()))
}
@Test func staleDiversionIsTakenOverAndLeftNative() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    await t.seed(82,0x05); await t.seed(195,0x11)
    let snap = try await h.probe(.mouse)
    #expect(snap.controls.first { $0.id == 82 }?.divertedByOther == true)
    try await h.divert(.mouse,ids:[82,195]); #expect(await t.diverted())
    #expect(await t.state(82) & 4 == 0)
    #expect(await h.restore())
    #expect(await t.state(82) == 0); #expect(await t.state(195) == 0)
}
@Test func clearStaleReleasesOnlyUnownedDiversion() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    await t.seed(82,0x01); await t.seed(195,0x11)
    _ = try await h.probe(.mouse)
    try await h.divert(.mouse,ids:[195])
    let cleared = await h.clearStale(.mouse)
    #expect(cleared == [82]); #expect(await t.state(82) == 0)
    #expect(await t.state(195) & 1 == 1)
}
@Test func setDiversionOnlyChangesTheDifference() async throws {
    let t = MockTransport(); let h = Hardware(transport:t)
    _ = try await h.probe(.mouse)
    try await h.setDiversion(.mouse,ids:[82,195]); let first = await t.writeCount()
    try await h.setDiversion(.mouse,ids:[82,195]); #expect(await t.writeCount() == first)
    try await h.setDiversion(.mouse,ids:[195]); #expect(await t.state(82) & 1 == 0); #expect(await t.state(195) & 1 == 1)
    #expect(await h.diverted(.mouse) == [195])
    try await h.setDiversion(.mouse,ids:[]); #expect(!(await t.diverted()))
}
