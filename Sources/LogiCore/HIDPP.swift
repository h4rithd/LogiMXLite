import Foundation

public enum HIDError: Error, LocalizedError, Equatable {
    case malformed, unavailable(String), timeout, disconnected, protocolError(UInt8), verification
    public var errorDescription: String? {
        switch self {
        case .malformed: "Malformed HID++ packet"
        case .unavailable(let s): s
        case .timeout: "HID++ response timed out; feature state unknown"
        case .disconnected: "Device disconnected"
        case .protocolError(let c): "HID++ error \(c)"
        case .verification: "Hardware readback did not confirm the requested value"
        }
    }
}
public struct Packet: Equatable, Sendable {
    public let device: UInt8
    public let feature: UInt8
    public let function: UInt8
    public let software: UInt8
    public let parameters: [UInt8]
    public init(device: UInt8 = 1, feature: UInt8, function: UInt8, software: UInt8 = 10, parameters: [UInt8] = []) throws {
        guard device == 1, function < 16, software < 16, parameters.count <= 16 else { throw HIDError.malformed }
        self.device = device; self.feature = feature; self.function = function; self.software = software; self.parameters = parameters
    }
    public var bytes: [UInt8] { [0x11, device, feature, function << 4 | software] + parameters + Array(repeating:0, count:16-parameters.count) }
    public init(bytes: [UInt8]) throws {
        guard (bytes.count == 20 && bytes.first == 0x11) || (bytes.count == 7 && bytes.first == 0x10), bytes[1] == 1 else { throw HIDError.malformed }
        try self.init(device:bytes[1], feature:bytes[2], function:bytes[3] >> 4, software:bytes[3] & 15, parameters:Array(bytes.dropFirst(4)))
    }
    public func matches(_ request: Packet) -> Bool {
        device == request.device && feature == request.feature && function == request.function && software == request.software
    }
    public func error(for request: Packet) -> UInt8? {
        guard device == request.device, feature == 0xFF, parameters.count >= 2,
              function << 4 | software == request.feature,
              parameters[0] == request.function << 4 | request.software else { return nil }
        return parameters[1]
    }
}
public struct DPIRange: Equatable, Sendable {
    public let values: [Int]
    public func supports(_ value: Int) -> Bool { values.contains(value) }
    public static func parse(_ p: [UInt8]) throws -> DPIRange {
        // HID++ 0x2201 response starts with the sensor index, then BE 16-bit entries.
        guard p.count >= 3, p[0] == 0 else { throw HIDError.malformed }
        var values: [Int] = []
        var offset = 1
        while offset + 1 < p.count {
            let word = Int(p[offset]) << 8 | Int(p[offset+1])
            if word == 0 { break }
            if word & 0xE000 == 0xE000 {
                let step = word & 0x1FFF
                guard step > 0, let start = values.last, offset + 3 < p.count else { throw HIDError.malformed }
                let end = Int(p[offset+2]) << 8 | Int(p[offset+3])
                guard end >= start, end <= 30000, (end-start)/step <= 1000 else { throw HIDError.malformed }
                values.append(contentsOf:stride(from:start+step,to:end,by:step))
                values.append(end); offset += 4
            } else {
                guard (50...30000).contains(word) else { throw HIDError.malformed }
                values.append(word); offset += 2
            }
            guard values.count <= 1000 else { throw HIDError.malformed }
        }
        guard !values.isEmpty else { throw HIDError.malformed }
        return DPIRange(values:Array(Set(values)).sorted())
    }
}
public protocol ReportTransport: Sendable {
    func request(_ model: Model, feature: UInt8, function: UInt8, parameters: [UInt8]) async throws -> Packet
}
public struct ControlInfo: Sendable, Equatable, Identifiable {
    public let id: UInt16
    public let task: UInt16
    public let flags: UInt16
    /// Reporting byte from getCtrlIdReporting: bit0 temporary divert, bit2 persistent divert, bit4 raw XY.
    public var reporting: UInt8 = 0
    public var remap: UInt16 = 0
    public var divertedByOther: Bool { reporting & 0x05 != 0 }
    public var divertible: Bool { flags & 0x20 != 0 }
    public var rawXY: Bool { flags & 0x100 != 0 }
    public static func parse(_ p: [UInt8]) throws -> ControlInfo {
        guard p.count >= 9 else { throw HIDError.malformed }
        return ControlInfo(id:UInt16(p[0]) << 8 | UInt16(p[1]), task:UInt16(p[2]) << 8 | UInt16(p[3]), flags:UInt16(p[4]) | UInt16(p[8]) << 8)
    }
}
public struct FeatureInfo: Sendable, Equatable, Identifiable {
    public let id: UInt16
    public let index: UInt8
    public let version: UInt8
    public let flags: UInt8
    public init(id: UInt16, index: UInt8, version: UInt8, flags: UInt8 = 0) { self.id=id; self.index=index; self.version=version; self.flags=flags }
}
