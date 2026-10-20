import Foundation

public struct HardwareSnapshot: Sendable {
    public var features: [UInt16:FeatureInfo] = [:]
    public var controls: [ControlInfo] = []
    public var dpiRange: DPIRange?
    public var dpi: Int?
    public var battery: Int?
    public var batteryStatus: BatteryStatus?
    public var hostCount: Int?
    /// One-based Easy-Switch channel, read from HID++ CHANGE_HOST when available.
    public var currentHost: Int?
    public var hosts: [HostSlot] = []
    public var wheelMode: Int?
    public var threshold: Int?
    public var fnInverted: Bool?
    public var backlight: BacklightState?
    public var issues: [String] = []
    public var firmware: [String] = []
    public init() {}
}
public struct HostSlot: Sendable, Equatable {
    public let channel: Int
    public let paired: Bool
    public let name: String?
    public init(channel: Int, paired: Bool, name: String?) {
        self.channel = channel; self.paired = paired; self.name = name
    }
}
public enum BatteryStatus: Int, Sendable, Equatable {
    case discharging = 0, charging = 1, chargingSlow = 2, full = 3, error = 4
    public var isCharging: Bool { self == .charging || self == .chargingSlow }
    public static func parse(_ parameters: [UInt8]) -> BatteryStatus? {
        guard parameters.count >= 3 else { return nil }
        return BatteryStatus(rawValue: Int(parameters[2]))
    }
}
public struct BacklightState: Sendable, Equatable {
    public let config: [UInt8]
    public let info: [UInt8]
    public var mode: Int { Int((config[1] >> 3) & 3) }
    public var enabled: Bool { config[0] != 0 }
    public var level: Int { Int(info[1]) }
    public var levels: Int { Int(info[0]) }
    public var effect: Int { Int(info[3]) }
    public var duration: Int { (Int(config[6]) | Int(config[7]) << 8) * 5 }
    public var effects: Int { Int(config[3]) | Int(config[4]) << 8 }
    public var supportsAuto: Bool { config[2] & 8 != 0 }
    public var supportsManual: Bool { config[2] & 32 != 0 }
    public static func parse(config: [UInt8], info: [UInt8]) throws -> BacklightState {
        guard config.count == 16, info.count == 16, info[0] > 0, info[0] <= 101, info[1] < info[0], info[3] <= 6 else { throw HIDError.malformed }
        return BacklightState(config:config,info:info)
    }
    public func payload(mode: Int?, level: Int?, seconds: Int?) throws -> [UInt8] {
        let m = mode ?? self.mode
        guard [0,1,3].contains(m), m != 1 || supportsAuto, m != 3 || supportsManual,
              (0..<levels).contains(level ?? self.level), seconds == nil || ((5...600).contains(seconds!) && seconds! % 5 == 0) else { throw HIDError.unavailable("Unsupported backlight setting") }
        // Off is the independent master-enable bit. Preserve the selected mode
        // so turning the backlight on again restores the prior behavior.
        let writableMode = (m == 0 || mode == nil) && self.mode == 2 ? 1 : (m == 0 ? self.mode : m)
        let writeEnabled = mode == nil ? enabled : m != 0
        var p: [UInt8] = [writeEnabled ? 1 : 0, (config[1] & 7) | UInt8(writableMode << 3), 0xFF, UInt8(level ?? self.level)]
        p += Array(config[6...13]) // preserve all four firmware duration fields
        if let seconds { p[4] = UInt8((seconds / 5) & 255); p[5] = UInt8((seconds / 5) >> 8) }
        return p
    }
}
/// Serializes complete read/write/readback transactions across actor suspension points.
private actor TransactionGate {
    var locked = false
    var queue: [CheckedContinuation<Void,Never>] = []
    func acquire() async { if locked { await withCheckedContinuation { queue.append($0) } } else { locked = true } }
    func release() { if queue.isEmpty { locked = false } else { queue.removeFirst().resume() } }
}
public actor Hardware {
    private let transport: any ReportTransport
    private let gate = TransactionGate()
    private var snapshots: [Model:HardwareSnapshot] = [:]
    private var priorReporting: [Model:[UInt16:UInt8]] = [:]
    private var lastWrite = ContinuousClock.now - .seconds(1)
    public init(transport: any ReportTransport) { self.transport = transport }
    private func transaction<T: Sendable>(_ body: () async throws -> T) async throws -> T {
        await gate.acquire()
        do { try Task.checkCancellation(); let value = try await body(); await gate.release(); return value }
        catch { await gate.release(); throw error }
    }
    private func call(_ model: Model, _ index: UInt8, _ function: UInt8, _ params: [UInt8] = []) async throws -> [UInt8] {
        for attempt in 0..<3 {
            do { return try await transport.request(model,feature:index,function:function,parameters:params).parameters }
            catch HIDError.protocolError(8) where attempt < 2 {
                // BUSY means the device rejected the operation. Retry at most twice.
                try await Task.sleep(for:.milliseconds(50 * (1 << attempt)))
            }
        }
        throw HIDError.protocolError(8)
    }
    private func feature(_ model: Model, _ ids: [UInt16]) throws -> FeatureInfo {
        guard let f = ids.compactMap({ snapshots[model]?.features[$0] }).first, f.index > 0, f.flags & 0xC0 == 0 else { throw HIDError.unavailable("Feature unavailable or obsolete on this device") }; return f
    }
    private func throttle() async throws {
        let elapsed = lastWrite.duration(to:.now)
        if elapsed < .milliseconds(150) { try await Task.sleep(for:.milliseconds(150) - elapsed) }
        try Task.checkCancellation(); lastWrite = .now
    }
    public func forget(_ model: Model) async {
        await gate.acquire(); snapshots.removeValue(forKey:model); priorReporting.removeValue(forKey:model); await gate.release()
    }
    public func probe(_ model: Model) async throws -> HardwareSnapshot {
        try await transaction {
            var state = HardwareSnapshot()
            let ping = try await call(model,0,1,[0,0,0x5A])
            guard ping.count >= 3, ping[0] >= 2, ping[2] == 0x5A else { throw HIDError.unavailable("HID++ 2 protocol ping not verified") }
            let set = try await call(model,0,0,[0,1])
            guard let index = set.first, index > 0 else { throw HIDError.unavailable("HID++ feature table unavailable") }
            let countData = try await call(model,index,0)
            guard let count = countData.first, count <= 128 else { throw HIDError.malformed }
            for n in 1...max(1,Int(count)) where count > 0 {
                let row = try await call(model,index,1,[UInt8(n)])
                guard row.count >= 4 else { throw HIDError.malformed }
                let id = UInt16(row[0]) << 8 | UInt16(row[1])
                guard state.features[id] == nil else { throw HIDError.malformed }
                state.features[id] = FeatureInfo(id:id,index:UInt8(n),version:row[3],flags:row[2])
            }
            snapshots[model] = state
            if let f = state.features[0x0003] {
                do {
                    let info = try await call(model,f.index,0)
                    guard let count = info.first, count <= 8 else { throw HIDError.malformed }
                    // Unit IDs and serial capabilities are discarded. Never request function 2 (serial).
                    for entity in 0..<count {
                        let row = try await call(model,f.index,1,[entity])
                        guard row.count >= 8 else { throw HIDError.malformed }
                        let prefix = String(bytes:row[1...3].map { (32...126).contains($0) ? $0 : 63 },encoding:.ascii) ?? "?"
                        state.firmware.append(String(format:"%@ version bytes %02X.%02X build %02X%02X",prefix,row[4],row[5],row[6],row[7]))
                    }
                } catch { state.issues.append("Firmware metadata: \(error.localizedDescription)") }
            }
            if let f = state.features[0x1004] {
                do {
                    let caps = try await call(model,f.index,0)
                    let b = try await call(model,f.index,1)
                    if caps.count >= 2, b.count >= 3, caps[1] & 2 != 0, b[0] <= 100 {
                        state.battery = Int(b[0])
                        state.batteryStatus = BatteryStatus.parse(b)
                    }
                } catch { state.issues.append("Battery: \(error.localizedDescription)") }
            }
            if let f = state.features[0x1814] {
                do {
                    let hosts = try await call(model, f.index, 0)
                    if hosts.count >= 2, (1...3).contains(hosts[0]), hosts[1] < hosts[0] {
                        state.hostCount = Int(hosts[0])
                        state.currentHost = Int(hosts[1]) + 1
                    } else { throw HIDError.malformed }
                } catch { state.issues.append("Easy-Switch: \(error.localizedDescription)") }
            }
            if let f = state.features[0x1815], f.version >= 2 {
                do {
                    let info = try await call(model, f.index, 0)
                    guard info.count >= 4, (1...3).contains(info[2]) else { throw HIDError.malformed }
                    let count = Int(info[2])
                    if state.hostCount == nil { state.hostCount = count }
                    if state.currentHost == nil, info[3] < info[2] { state.currentHost = Int(info[3]) + 1 }
                    for index in 0..<count {
                        // A slot failure must not hide information for the other slots.
                        guard let slot = try? await readHostSlot(model, feature:f, index:UInt8(index), namesSupported:info[0] & 1 != 0) else { continue }
                        state.hosts.append(slot)
                    }
                } catch { state.issues.append("Host information: \(error.localizedDescription)") }
            }
            if model == .mouse, let f = state.features[0x2201] {
                do {
                    let sensors = try await call(model,f.index,0)
                    guard sensors.first == 1 else { throw HIDError.unavailable("Only one-sensor DPI protocol supported") }
                    state.dpiRange = try DPIRange.parse(await call(model,f.index,1,[0]))
                    let d = try await call(model,f.index,2,[0]); guard d.count >= 5, d[0] == 0 else { throw HIDError.malformed }
                    let value = Int(d[1]) << 8 | Int(d[2]); guard state.dpiRange?.supports(value) == true else { throw HIDError.malformed }; state.dpi = value
                } catch { state.issues.append("DPI: \(error.localizedDescription)"); state.dpiRange = nil }
            }
            if let f = try? feature(model,[0x2111,0x2110]), model == .mouse {
                do { let s = try await call(model,f.index,f.id == 0x2111 ? 1 : 0); guard s.count >= 3, [1,2].contains(s[0]) else { throw HIDError.malformed }; state.wheelMode = Int(s[0]); state.threshold = Int(s[1]) }
                catch { state.issues.append("SmartShift: \(error.localizedDescription)") }
            }
            if let f = try? feature(model,[0x40A3,0x40A2,0x40A0]), model == .keyboard {
                do { let s = try await call(model,f.index,0,f.id == 0x40A3 ? [255] : []); let n = f.id == 0x40A3 ? 1 : 0; guard s.count > n, s[n] <= 1 else { throw HIDError.malformed }; state.fnInverted = s[n] == 1 }
                catch { state.issues.append("Fn inversion: \(error.localizedDescription)") }
            }
            if let f = state.features[0x1982], f.version == 3, model == .keyboard {
                do { state.backlight = try await readBacklight(f) } catch { state.issues.append("Backlight: \(error.localizedDescription)") }
            }
            if let f = state.features[0x1B04] {
                do {
                    let c = try await call(model,f.index,0); guard let n = c.first, n <= 64 else { throw HIDError.malformed }
                    for i in 0..<n {
                        var control = try ControlInfo.parse(await call(model,f.index,1,[i]))
                        if control.divertible, let r = try? await call(model,f.index,2,[UInt8(control.id >> 8),UInt8(control.id & 255)]), r.count >= 5, UInt16(r[0]) << 8 | UInt16(r[1]) == control.id {
                            control.reporting = r[2]; control.remap = UInt16(r[3]) << 8 | UInt16(r[4])
                        }
                        state.controls.append(control)
                    }
                } catch { state.issues.append("Controls: \(error.localizedDescription)"); state.controls = [] }
            }
            snapshots[model] = state
            return state
        }
    }
    private func readHostSlot(_ model: Model, feature: FeatureInfo, index: UInt8, namesSupported: Bool) async throws -> HostSlot {
        let info = try await call(model, feature.index, 1, [index, 0, 0])
        guard info.count >= 6, info[0] == index, info[1] <= 1 else { throw HIDError.malformed }
        let paired = info[1] == 1
        let nameLength = Int(info[4])
        guard nameLength <= 64 else { throw HIDError.malformed }
        guard paired, namesSupported, nameLength > 0 else { return HostSlot(channel:Int(index)+1,paired:paired,name:nil) }
        var bytes: [UInt8] = []
        while bytes.count < nameLength {
            let offset = UInt8(bytes.count)
            let chunk = try await call(model, feature.index, 3, [index, offset, 0])
            guard chunk.count >= 16, chunk[0] == index, chunk[1] == offset else { throw HIDError.malformed }
            bytes += chunk[2..<min(16, 2 + nameLength - bytes.count)]
        }
        let name = String(bytes:bytes,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines)
        return HostSlot(channel:Int(index)+1,paired:true,name:name?.isEmpty == false ? name : nil)
    }
    private func readBacklight(_ f: FeatureInfo) async throws -> BacklightState {
        let config = try await call(.keyboard,f.index,0); let info = try await call(.keyboard,f.index,2)
        return try BacklightState.parse(config:config,info:info)
    }
    public func setDPI(_ dpi: Int) async throws -> Int {
        try await transaction {
            let f = try feature(.mouse,[0x2201])
            guard snapshots[.mouse]?.dpiRange?.supports(dpi) == true else { throw HIDError.unavailable("DPI is outside the live hardware range") }
            let old = try await call(.mouse,f.index,2,[0]); guard old.count >= 5, old[0] == 0 else { throw HIDError.malformed }
            let previous = Int(old[1]) << 8 | Int(old[2]); if previous == dpi { return dpi }
            try await throttle()
            do {
                _ = try await call(.mouse,f.index,3,[0,UInt8(dpi >> 8),UInt8(dpi & 255)])
                let read = try await call(.mouse,f.index,2,[0])
                guard read.count >= 3, read[0] == 0, Int(read[1]) << 8 | Int(read[2]) == dpi else { throw HIDError.verification }
                snapshots[.mouse]?.dpi = dpi; return dpi
            } catch {
                // Restore only a value obtained in this transaction; never replay a persistent source default.
                _ = try? await call(.mouse,f.index,3,[0,old[1],old[2]])
                snapshots[.mouse]?.dpi = nil
                throw error
            }
        }
    }
    public func setWheel(mode: Int, threshold: Int) async throws -> (Int,Int) {
        try await transaction {
            guard [1,2].contains(mode), (1...50).contains(threshold) || threshold == 255 else { throw HIDError.malformed }
            let f = try feature(.mouse,[0x2111,0x2110]); let get: UInt8 = f.id == 0x2111 ? 1 : 0
            let old = try await call(.mouse,f.index,get); guard old.count >= 3, [1,2].contains(old[0]) else { throw HIDError.malformed }
            if old[0] == mode && old[1] == threshold { return (mode,threshold) }
            try await throttle()
            do {
                _ = try await call(.mouse,f.index,get+1,[UInt8(mode),UInt8(threshold),0])
                let read = try await call(.mouse,f.index,get)
                guard read.count >= 2, read[0] == mode, read[1] == threshold else { throw HIDError.verification }
                snapshots[.mouse]?.wheelMode = mode; snapshots[.mouse]?.threshold = threshold; return (mode,threshold)
            } catch { _ = try? await call(.mouse,f.index,get+1,[old[0],old[1],0]); throw error }
        }
    }
    public func setFn(_ inverted: Bool) async throws -> Bool {
        try await transaction {
            let f = try feature(.keyboard,[0x40A3,0x40A2,0x40A0]); let prefix: [UInt8] = f.id == 0x40A3 ? [255] : []
            let old = try await call(.keyboard,f.index,0,prefix); let n = prefix.count
            guard old.count > n, old[n] <= 1 else { throw HIDError.malformed }
            let target: UInt8 = inverted ? 1 : 0; if old[n] == target { return inverted }
            try await throttle()
            do {
                _ = try await call(.keyboard,f.index,1,prefix + [target,0])
                let read = try await call(.keyboard,f.index,0,prefix)
                guard read.count > n, read[n] == target else { throw HIDError.verification }
                snapshots[.keyboard]?.fnInverted = inverted; return inverted
            } catch { _ = try? await call(.keyboard,f.index,1,prefix + [old[n],0]); throw error }
        }
    }
    public func setBacklight(mode: Int?, level: Int?, seconds: Int?, effect: Int?) async throws -> BacklightState {
        try await transaction {
            let f = try feature(.keyboard,[0x1982]); guard f.version == 3 else { throw HIDError.unavailable("Unverified backlight protocol version") }
            let old = try await readBacklight(f)
            if let effect { guard (0...6).contains(effect), old.effects & (1 << effect) != 0 else { throw HIDError.unavailable("Effect not supported by hardware") } }
            // The device reports its live brightness as zero while disabled. A saved
            // brightness is for the next enable, not a value that can be verified Off.
            let activeLevel = mode == 0 ? nil : level
            let configRequested = mode != nil || activeLevel != nil || seconds != nil
            let payload = configRequested ? try old.payload(mode:mode,level:activeLevel,seconds:seconds) : nil
            let modeMatches = mode == nil || (mode == 0 ? !old.enabled : old.enabled && mode == old.mode)
            if modeMatches && (activeLevel == nil || activeLevel == old.level) && (seconds == nil || seconds == old.duration) && (effect == nil || effect == old.effect) { return old }
            try await throttle()
            do {
                if let payload { _ = try await call(.keyboard,f.index,1,payload) }
                if let effect { _ = try await call(.keyboard,f.index,3,[UInt8(effect)]) }
                let read = try await readBacklight(f)
                guard mode == nil || (mode == 0 ? !read.enabled : read.enabled && read.mode == mode), activeLevel == nil || read.level == activeLevel,
                      seconds == nil || read.duration == seconds, effect == nil || read.effect == effect else { throw HIDError.verification }
                snapshots[.keyboard]?.backlight = read; return read
            } catch {
                if configRequested, let restore = try? old.payload(mode:old.enabled ? old.mode : 0,level:Int(old.config[5]),seconds:nil) { _ = try? await call(.keyboard,f.index,1,restore) }
                _ = try? await call(.keyboard,f.index,3,[UInt8(old.effect)]); throw error
            }
        }
    }
    private static func allowedControls(_ model: Model) -> Set<UInt16> {
        model == .mouse ? [82,83,86,195,196] : [212,226,227,231,232,233,259,264,266,280,281,282,283,284,285,321]
    }
    private func cidBytes(_ id: UInt16) -> [UInt8] { [UInt8(id >> 8),UInt8(id & 255)] }
    /// Diversion left behind by another program (Options+, MXControl, a crashed run) is taken over rather than
    /// refused: nothing is listening to it, so the button is dead until it is claimed or cleared.
    public func divert(_ model: Model, ids: Set<UInt16>) async throws {
        try await transaction {
            let f = try feature(model,[0x1B04]); let controls = snapshots[model]?.controls ?? []
            guard ids.isSubset(of:Self.allowedControls(model)), ids.allSatisfy({ id in controls.contains { $0.id == id && $0.divertible } }) else { throw HIDError.unavailable("Control has not been enumerated as divertible") }
            do {
                for id in ids.sorted() {
                    let cid = cidBytes(id)
                    let old = try await call(model,f.index,2,cid)
                    guard old.count >= 6, old[0] == cid[0], old[1] == cid[1] else { throw HIDError.malformed }
                    priorReporting[model,default:[:]][id] = old[2]
                    let raw = id == 195 && controls.contains { $0.id == id && $0.rawXY }
                    // Temporary diversion only; also clear a persistent diversion inherited from another tool.
                    let flags: UInt8 = (raw ? 0x33 : 0x03) | (old[2] & 4 != 0 ? 0x08 : 0)
                    _ = try await call(model,f.index,3,cid + [flags,0,0,0])
                    let read = try await call(model,f.index,2,cid)
                    guard read.count >= 3, read[2] & 1 == 1, !raw || read[2] & 0x10 != 0 else { throw HIDError.verification }
                }
            } catch { await restoreInternal(model); throw error }
        }
    }
    /// Changes only what differs from the current diversion, so switching apps does not re-arm every control.
    public func setDiversion(_ model: Model, ids: Set<UInt16>) async throws {
        let owned: Set<UInt16> = try await transaction {
            let f = try feature(model,[0x1B04])
            let owned = Set((priorReporting[model] ?? [:]).keys)
            for id in owned.subtracting(ids) {
                if await undivert(model,f,id:id,clearPersistent:(priorReporting[model]?[id] ?? 0) & 4 != 0) { priorReporting[model]?.removeValue(forKey:id) }
            }
            return owned
        }
        let add = ids.subtracting(owned)
        if !add.isEmpty { try await divert(model,ids:add) }
    }
    public func diverted(_ model: Model) -> Set<UInt16> { Set((priorReporting[model] ?? [:]).keys) }
    /// Writes a fully native state: no temporary or persistent diversion, no raw XY.
    private func undivert(_ model: Model, _ f: FeatureInfo, id: UInt16, clearPersistent: Bool) async -> Bool {
        let cid = cidBytes(id)
        let flags: UInt8 = 0x22 | (clearPersistent ? 0x08 : 0)
        guard (try? await call(model,f.index,3,cid + [flags,0,0,0])) != nil,
              let read = try? await call(model,f.index,2,cid), read.count >= 3 else { return false }
        return read[2] & (clearPersistent ? 0x15 : 0x11) == 0
    }
    private func restoreInternal(_ model: Model) async {
        guard let f = try? feature(model,[0x1B04]) else { return }
        for (id,old) in priorReporting[model] ?? [:] {
            if await undivert(model,f,id:id,clearPersistent:old & 4 != 0) { priorReporting[model]?.removeValue(forKey:id) }
        }
    }
    /// Releases allowlisted controls that report a diversion nobody here owns, so native Back/Forward/gesture
    /// behavior returns. Callers must only run this when no other Logitech tool is running.
    public func clearStale(_ model: Model) async -> [UInt16] {
        guard let f = try? feature(model,[0x1B04]) else { return [] }
        await gate.acquire(); defer { Task { await gate.release() } }
        var cleared: [UInt16] = []
        for id in Self.allowedControls(model).sorted() where priorReporting[model]?[id] == nil {
            guard let control = snapshots[model]?.controls.first(where: { $0.id == id }), control.divertible,
                  let read = try? await call(model,f.index,2,cidBytes(id)), read.count >= 3, read[2] & 0x15 != 0 else { continue }
            if await undivert(model,f,id:id,clearPersistent:read[2] & 4 != 0) {
                cleared.append(id)
                if let i = snapshots[model]?.controls.firstIndex(where: { $0.id == id }) { snapshots[model]?.controls[i].reporting = 0 }
            }
        }
        return cleared
    }
    public func restore() async -> Bool {
        await gate.acquire()
        for model in Model.allCases { await restoreInternal(model) }
        let ok = priorReporting.values.allSatisfy(\.isEmpty); await gate.release(); return ok
    }
}
