import Foundation
@preconcurrency import IOKit
@preconcurrency import IOKit.hid
@preconcurrency import CoreFoundation

public enum DeviceEvent: Sendable {
    case connected(Model, String)
    case removed(Model)
    case diagnosis(Model?, String)
    case notification(Model, Packet)
}
/// All mutable state and device lifetimes are confined to queue. IOHID callbacks
/// only copy bounded reports and enqueue work. No user input is seized or swallowed.
public final class IOHIDTransport: ReportTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label:"com.h4rithd.LogiMXLite.hid")
    private var manager: IOHIDManager?
    private var devices: [Model:IOHIDDevice] = [:]
    private var pointers: [Int:Model] = [:]
    private var ready: Set<Model> = []
    private var pending: [Model:Pending] = [:]
    private var waiting: [Model:[Pending]] = [:]
    private var software: UInt8 = 1
    private var events: (@Sendable (DeviceEvent) -> Void)?
    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func cancel() { lock.lock(); value = true; lock.unlock() }
        var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
    private final class ReportWrite {
        let bytes: UnsafeMutablePointer<UInt8>
        let id: UUID
        let model: Model
        weak var owner: IOHIDTransport?
        init(_ data: [UInt8], id: UUID, model: Model, owner: IOHIDTransport) {
            bytes = .allocate(capacity:data.count)
            bytes.initialize(from:data,count:data.count)
            self.id = id; self.model = model; self.owner = owner
        }
        deinit { bytes.deallocate() }
    }
    private struct Pending {
        let id: UUID
        let packet: Packet
        let continuation: CheckedContinuation<Packet, any Error>
    }
    public init() {}
    private struct DeviceBox: @unchecked Sendable { let device: IOHIDDevice }
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    public func start(events: @escaping @Sendable (DeviceEvent) -> Void) {
        queue.async { [self] in
            guard self.thread == nil else { return }
            self.events = events
            // IOHIDManagerActivate does not deliver input reports to a manager-level callback on this stack, and
            // calling IOHIDManagerOpen after Activate traps inside IOKit. The classic run-loop pattern is verified
            // to deliver HID++ responses from both devices; its callbacks hop onto `queue` immediately.
            let thread = Thread { [weak self] in self?.runManager() }
            thread.name = "com.h4rithd.LogiMXLite.hid.runloop"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            thread.start()
        }
    }
    private func runManager() {
        let m = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matches = Model.allCases.map { [kIOHIDVendorIDKey:0x046D, kIOHIDProductIDKey:$0.pid, kIOHIDTransportKey:"Bluetooth Low Energy"] as [String:Any] }
        IOHIDManagerSetDeviceMatchingMultiple(m, matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { ctx, _, _, d in
            guard let ctx else { return }
            let owner = Unmanaged<IOHIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            let box = DeviceBox(device: d)
            owner.queue.async { owner.matched(box.device) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { ctx, _, _, d in
            guard let ctx else { return }
            let owner = Unmanaged<IOHIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            let box = DeviceBox(device: d)
            owner.queue.async { owner.removed(box.device) }
        }, context)
        IOHIDManagerRegisterInputReportCallback(m, { ctx, result, sender, type, reportID, pointer, length in
            guard let ctx, let sender, result == kIOReturnSuccess, type == kIOHIDReportTypeInput,
                  reportID == 0x11, length == 19 || length == 20 else { return }
            let owner = Unmanaged<IOHIDTransport>.fromOpaque(ctx).takeUnretainedValue()
            var bytes = Array(UnsafeBufferPointer(start:pointer, count:length))
            if length == 19 { bytes.insert(0x11, at:0) }
            let report = bytes
            let senderPointer = Int(bitPattern:sender)
            owner.queue.async { owner.received(pointer:senderPointer, bytes:report) }
        }, context)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(m, 0)
        let loop = CFRunLoopGetCurrent()
        queue.async {
            self.manager = m; self.runLoop = loop
            if result != kIOReturnSuccess { self.events?(.diagnosis(nil, IOHIDTransport.error("IOHIDManagerOpen", result))) }
        }
        CFRunLoopRun()
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }
    private static func error(_ operation: String, _ value: IOReturn) -> String {
        "\(operation): \(String(format:"0x%08X",value)). Check Input Monitoring, quit conflicting HID software, then Retry."
    }
    private func matched(_ device: IOHIDDevice) {
        let prop: (String) -> Any? = { IOHIDDeviceGetProperty(device,$0 as CFString) }
        guard let model = Model.match(vendor:prop(kIOHIDVendorIDKey) as? Int ?? 0, product:prop(kIOHIDProductIDKey) as? Int ?? 0, transport:prop(kIOHIDTransportKey) as? String ?? "", name:prop(kIOHIDProductKey) as? String ?? "") else { return }
        let pairs = prop(kIOHIDDeviceUsagePairsKey) as? [[String:Any]] ?? []
        let vendorPair = pairs.contains { ($0[kIOHIDDeviceUsagePageKey] as? Int) == 0xFF43 && ($0[kIOHIDDeviceUsageKey] as? Int) == 0x0202 }
        guard vendorPair, (prop(kIOHIDMaxOutputReportSizeKey) as? Int ?? 0) >= 20 else {
            // A Logitech product exposes multiple HID collections. Claim only the
            // vendor report collection, regardless of callback ordering.
            return
        }
        let pointer = Int(bitPattern:Unmanaged.passUnretained(device).toOpaque())
        guard devices[model] == nil else { return }
        pointers[pointer] = model
        devices[model] = device
        events?(.connected(model, prop(kIOHIDProductKey) as? String ?? model.name))
        let result = IOHIDDeviceOpen(device,0)
        guard result == kIOReturnSuccess else { events?(.diagnosis(model, IOHIDTransport.error("IOHIDDeviceOpen",result))); return }
        ready.insert(model)
        events?(.diagnosis(model,"Vendor report endpoint open; read-only feature probe available"))
    }
    private func removed(_ device: IOHIDDevice) {
        let pointer = Int(bitPattern:Unmanaged.passUnretained(device).toOpaque())
        guard let model = pointers.removeValue(forKey:pointer), devices[model] == device else { return }
        IOHIDDeviceClose(device,0); devices.removeValue(forKey:model); ready.remove(model)
        fail(model, error:HIDError.disconnected); events?(.removed(model))
    }
    public func request(_ model: Model, feature: UInt8, function: UInt8, parameters: [UInt8] = []) async throws -> Packet {
        try Task.checkCancellation()
        let id = UUID()
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !cancellation.cancelled else { continuation.resume(throwing:CancellationError()); return }
                    guard self.ready.contains(model) else { continuation.resume(throwing:HIDError.unavailable("Read-only: HID++ endpoint could not be opened")); return }
                    guard (self.waiting[model]?.count ?? 0) < 64 else { continuation.resume(throwing:HIDError.unavailable("HID++ request queue full")); return }
                    do {
                        self.software = self.software % 15 + 1
                        let packet = try Packet(feature:feature, function:function, software:self.software, parameters:parameters)
                        let p = Pending(id:id,packet:packet,continuation:continuation)
                        self.waiting[model,default:[]].append(p); self.sendNext(model)
                    } catch { continuation.resume(throwing:error) }
                }
            }
        } onCancel: {
            cancellation.cancel()
            self.queue.async {
                if self.pending[model]?.id == id { return }
                else if let i = self.waiting[model]?.firstIndex(where: { $0.id == id }) {
                    self.waiting[model]?.remove(at:i).continuation.resume(throwing:CancellationError())
                }
            }
        }
    }
    private func sendNext(_ model: Model) {
        guard pending[model] == nil, !(waiting[model] ?? []).isEmpty, let device = devices[model], ready.contains(model) else { return }
        let p = waiting[model]!.removeFirst(); pending[model] = p
        let bytes = p.packet.bytes
        // Output is always 20-byte long BLE report. Only this exact allowlisted device is addressed.
        let write = ReportWrite(bytes,id:p.id,model:model,owner:self)
        let context = Unmanaged.passRetained(write).toOpaque()
        let result = IOHIDDeviceSetReportWithCallback(device,kIOHIDReportTypeOutput,0x11,write.bytes,bytes.count,1000,{ context, result, _, _, _, _, _ in
            guard let context else { return }
            let write = Unmanaged<ReportWrite>.fromOpaque(context).takeRetainedValue()
            guard let owner = write.owner, result != kIOReturnSuccess else { return }
            let id = write.id, model = write.model
            owner.queue.async {
                guard owner.pending[model]?.id == id else { return }
                owner.quarantine(model,error:HIDError.unavailable(IOHIDTransport.error("Asynchronous SetReport",result)),message:IOHIDTransport.error("Asynchronous SetReport",result))
            }
        },context)
        if result != kIOReturnSuccess {
            Unmanaged<ReportWrite>.fromOpaque(context).release()
            quarantine(model,error:HIDError.unavailable(IOHIDTransport.error("SetReport", result)),message:IOHIDTransport.error("SetReport",result)); return
        }
        queue.asyncAfter(deadline:.now() + 1.2) {
            guard self.pending[model]?.id == p.id else { return }
            // Quarantine this endpoint after timeout: a late reply must never satisfy a new request.
            self.quarantine(model,error:HIDError.timeout,message:"HID++ timeout; reopening endpoint")
        }
    }
    /// A quarantined endpoint is reopened after a short pause instead of staying dead until reconnect. The pause lets
    /// any late reply drain, and the ready diagnosis makes the app re-probe and re-arm mappings.
    private func quarantine(_ model: Model, error: any Error, message: String) {
        ready.remove(model); fail(model,error:error); events?(.diagnosis(model,message))
        queue.asyncAfter(deadline:.now() + 1.5) {
            guard self.devices[model] != nil, !self.ready.contains(model), self.pending[model] == nil else { return }
            self.ready.insert(model)
            self.events?(.diagnosis(model,"Vendor report endpoint open; read-only feature probe available"))
        }
    }
    private func received(pointer: Int, bytes: [UInt8]) {
        var bytes = bytes
        // Unsolicited events may carry device index 0xFF or 0. Device identity comes from the HID sender, so the
        // index is normalized for notifications only. Responses still require an exact index and software ID.
        if bytes.count == 20, bytes[0] == 0x11, bytes[1] == 0xFF || bytes[1] == 0, bytes[3] & 15 == 0 { bytes[1] = 1 }
        guard let model = pointers[pointer], let packet = try? Packet(bytes:bytes) else { return }
        if let p = pending[model] {
            if let code = packet.error(for:p.packet) { finish(model,result:.failure(HIDError.protocolError(code))); return }
            if packet.matches(p.packet) { finish(model,result:.success(packet)); return }
        }
        if packet.software == 0 { events?(.notification(model,packet)) }
    }
    private func finish(_ model: Model, result: Result<Packet,any Error>) {
        guard let p = pending.removeValue(forKey:model) else { return }
        p.continuation.resume(with:result); sendNext(model)
    }
    private func fail(_ model: Model, error: any Error) {
        pending.removeValue(forKey:model)?.continuation.resume(throwing:error)
        for p in waiting.removeValue(forKey:model) ?? [] { p.continuation.resume(throwing:error) }
    }
    public func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                for model in Model.allCases { self.fail(model,error:HIDError.disconnected) }
                for d in self.devices.values { IOHIDDeviceClose(d,0) }
                self.devices.removeAll(); self.pointers.removeAll(); self.ready.removeAll()
                if let m = self.manager { IOHIDManagerClose(m,0) }
                if let loop = self.runLoop { CFRunLoopStop(loop) }
                self.manager = nil; self.runLoop = nil; self.thread = nil; continuation.resume()
            }
        }
    }
}
