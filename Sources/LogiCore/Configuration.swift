import Foundation

public enum Model: String, Codable, CaseIterable, Sendable, Identifiable {
    case mouse, keyboard
    public var id: String { rawValue }
    public var name: String { self == .mouse ? "MX Master 3S" : "MX Mechanical Mini for Mac" }
    public var pid: Int { self == .mouse ? 0xB034 : 0xB36D }
    public static func match(vendor: Int, product: Int, transport: String, name: String) -> Model? {
        guard vendor == 0x046D, transport == "Bluetooth Low Energy" else { return nil }
        return allCases.first { $0.pid == product && ($0 == .mouse ? ["MX Master 3S", "MX Master 3S M"].contains(name) : ["MX MCHNCL M", "MX Mechanical Mini for Mac"].contains(name)) }
    }
}
public enum ActionKind: String, Codable, CaseIterable, Sendable {
    case none, shortcut, downloads, maximize, missionControl, middleClick, back, forward
    case nextTrack, previousTrack, playPause, volumeUp, volumeDown, mute, microphoneMute
    case screenshot, emoji, cycleDPI, wheelMode, requiresConfirmation
    case launchpad, appExpose, desktopLeft, desktopRight, backlightUp, backlightDown, smartZoom
    case showDesktop, brightnessUp, brightnessDown, scrollLeft, scrollRight, fnLockToggle, calculator, systemSettings, siri
    case nativeHorizontalScroll
    // Thumb-wheel modes: each wheel step runs the left or right half of the pair.
    case thumbZoom, thumbDesktops, thumbVolume, thumbApps, thumbTabs, thumbPages, thumbTracks, thumbBrightness
    public static let thumbModes: [ActionKind] = [.thumbZoom, .thumbDesktops, .thumbVolume, .thumbApps, .thumbTabs, .thumbPages, .thumbTracks, .thumbBrightness]
    public var isThumbMode: Bool { Self.thumbModes.contains(self) }
}
public struct Action: Codable, Equatable, Sendable {
    public var kind: ActionKind
    public var usage: Int?
    public var modifiers: [Int]?
    public var note: String?
    public var repeatDelayMS: Int?
    public var repeatIntervalMS: Int?
    public init(_ kind: ActionKind, usage: Int? = nil, modifiers: [Int]? = nil, note: String? = nil, repeatDelayMS: Int? = nil, repeatIntervalMS: Int? = nil) {
        self.kind = kind; self.usage = usage; self.modifiers = modifiers; self.note = note
        self.repeatDelayMS = repeatDelayMS; self.repeatIntervalMS = repeatIntervalMS
    }
    public var label: String {
        if kind == .requiresConfirmation { return "Requires confirmation: \(note ?? "source action")" }
        if kind == .shortcut { return HIDKeyMap.describe(usage: usage ?? 0, modifiers: modifiers ?? []) }
        return [ActionKind.maximize:"Maximize window", .missionControl:"Mission Control", .downloads:"Open Downloads", .middleClick:"Middle click", .cycleDPI:"Cycle DPI preset", .wheelMode:"Toggle wheel mode", .microphoneMute:"Toggle microphone mute", .screenshot:"Capture region", .none:"Do nothing", .back:"Back", .forward:"Forward", .nextTrack:"Next track", .previousTrack:"Previous track", .playPause:"Play / Pause", .volumeUp:"Volume up", .volumeDown:"Volume down", .mute:"Mute", .emoji:"Emoji picker", .launchpad:"Launchpad", .appExpose:"App Exposé", .desktopLeft:"Desktop to the left", .desktopRight:"Desktop to the right", .backlightUp:"Backlight up", .backlightDown:"Backlight down", .smartZoom:"Smart zoom", .showDesktop:"Show desktop", .brightnessUp:"Brightness up", .brightnessDown:"Brightness down", .scrollLeft:"Scroll left", .scrollRight:"Scroll right", .fnLockToggle:"Toggle Fn lock", .calculator:"Calculator", .systemSettings:"System Settings", .siri:"Siri", .nativeHorizontalScroll:"Horizontal scroll (native)", .thumbZoom:"Zoom in/out", .thumbDesktops:"Switch desktops", .thumbVolume:"Volume", .thumbApps:"Switch apps", .thumbTabs:"Switch tabs", .thumbPages:"Back / forward", .thumbTracks:"Previous / next track", .thumbBrightness:"Brightness"][kind] ?? kind.rawValue
    }
}
public struct DPIPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var dpi: Int
    public init(name: String, dpi: Int, id: UUID = UUID()) { self.id = id; self.name = name; self.dpi = dpi }
}
public struct ScrollSettings: Codable, Equatable, Sendable {
    public var verticalScale: Double = 1
    public var horizontalScale: Double = 1
    public var natural: Bool = true
    public var horizontalInverted: Bool = false
    public var smooth: Bool = false
    public init() {}
}
public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var fnInverted: Bool?
    public var backlightMode: Int?
    public var brightness: Int?
    public var durationSeconds: Int?
    public var effect: Int?
    public init() {}
}
public struct Profile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var bundleID: String?
    public var isDefault: Bool
    public var mouse: [String: Action]
    public var keyboard: [String: Action]
    public var gestures: [String: Action]
    public var dpiPreset: UUID?
    public var scroll: ScrollSettings?
    public var keyboardSettings: KeyboardSettings?
    public var wheelMode: Int?
    public var smartShiftThreshold: Int?
    // Read-only provenance, never interpreted as executable code or calibrated hardware values.
    public var observations: [String: String]
    public init(name: String, bundleID: String? = nil, isDefault: Bool = false, id: UUID = UUID()) {
        self.id = id; self.name = name; self.bundleID = bundleID; self.isDefault = isDefault
        mouse = [:]; keyboard = [:]; gestures = [:]; observations = [:]
    }
}
public struct Configuration: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var profiles: [Profile]
    public var dpiPresets: [DPIPreset] = []
    public var switchHardwareWithApps: Bool = false
    public var theme: String = "light"
    public init(profiles: [Profile]) { self.profiles = profiles }
    public var desktop: Profile { profiles.first(where: \.isDefault)! } // validated at all boundaries
    public func selected(bundleID: String?) -> Profile {
        profiles.first { !$0.isDefault && $0.bundleID != nil && $0.bundleID == bundleID } ?? desktop
    }
    public func resolved(_ id: UUID) -> Profile {
        let base = desktop
        guard var p = profiles.first(where: { $0.id == id }), !p.isDefault else { return base }
        p.mouse = base.mouse.merging(p.mouse) { _, b in b }
        p.keyboard = base.keyboard.merging(p.keyboard) { _, b in b }
        p.gestures = base.gestures.merging(p.gestures) { _, b in b }
        p.scroll = p.scroll ?? base.scroll; p.dpiPreset = p.dpiPreset ?? base.dpiPreset
        p.wheelMode = p.wheelMode ?? base.wheelMode
        p.smartShiftThreshold = p.smartShiftThreshold ?? base.smartShiftThreshold
        let own = p.keyboardSettings
        var keys = base.keyboardSettings ?? KeyboardSettings()
        keys.fnInverted = own?.fnInverted ?? keys.fnInverted
        keys.backlightMode = own?.backlightMode ?? keys.backlightMode
        keys.brightness = own?.brightness ?? keys.brightness
        keys.durationSeconds = own?.durationSeconds ?? keys.durationSeconds
        keys.effect = own?.effect ?? keys.effect
        p.keyboardSettings = keys
        return p
    }
}
public enum ConfigError: Error, LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let s) = self { s } else { "Invalid configuration" } }
}
public enum ConfigCodec {
    public static let limit = 1_048_576
    public static func decode(_ data: Data) throws -> Configuration {
        guard data.count <= limit else { throw ConfigError.invalid("Import exceeds 1 MiB") }
        let result = try JSONDecoder().decode(Configuration.self, from: data)
        try validate(result)
        return result
    }
    public static func encode(_ config: Configuration) throws -> Data {
        try validate(config)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(config)
        guard data.count <= limit else { throw ConfigError.invalid("Configuration exceeds 1 MiB") }
        return data
    }
    public static func validate(_ c: Configuration) throws {
        func require(_ ok: Bool, _ why: String) throws { if !ok { throw ConfigError.invalid(why) } }
        func safe(_ s: String, max: Int = 120) -> Bool {
            !s.isEmpty && s.utf8.count <= max && !s.unicodeScalars.contains { $0.value < 32 } && !s.contains("/") && !s.contains("\\")
        }
        try require(c.schemaVersion == 1, "Unsupported schema version")
        try require((1...64).contains(c.profiles.count) && c.profiles.filter(\.isDefault).count == 1, "Exactly one Desktop profile required; maximum 64 profiles")
        try require(Set(c.profiles.map(\.id)).count == c.profiles.count, "Duplicate profile ID")
        try require(c.desktop.bundleID == nil, "Desktop cannot have an app association")
        let bundles = c.profiles.compactMap(\.bundleID)
        try require(Set(bundles).count == bundles.count, "Duplicate app association")
        try require(["system", "light", "dark"].contains(c.theme), "Invalid theme")
        try require(c.dpiPresets.count <= 32 && Set(c.dpiPresets.map(\.id)).count == c.dpiPresets.count, "Invalid preset count or duplicate ID")
        for preset in c.dpiPresets { try require(safe(preset.name) && (50...30000).contains(preset.dpi), "Invalid DPI preset; live range validation also required") }
        let mouseKeys: Set<String> = ["c82", "c83", "c86", "c195", "c196", "thumbWheel"]
        let keyboardKeys = Set([212,226,227,231,232,233,259,264,266,280,281,282,283,284,285,321].map { "c\($0)" })
        for p in c.profiles {
            try require(safe(p.name), "Invalid profile name")
            if let b = p.bundleID { try require(b.utf8.count <= 200 && b.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil, "Invalid bundle ID") }
            try require(Set(p.mouse.keys).isSubset(of: mouseKeys) && Set(p.keyboard.keys).isSubset(of: keyboardKeys) && Set(p.gestures.keys).isSubset(of: ["click", "up", "down", "left", "right"]), "Unknown control")
            for a in Array(p.mouse.values) + Array(p.keyboard.values) + Array(p.gestures.values) {
                if a.kind == .shortcut { try require(a.usage.flatMap { HIDKeyMap.virtualKey[$0] } != nil, "Unsupported USB key usage") }
                else { try require(a.usage == nil && a.modifiers == nil, "Key payload on non-shortcut action") }
                try require((a.modifiers ?? []).count <= 4 && Set(a.modifiers ?? []).isSubset(of: [224,225,226,227]), "Invalid modifiers")
                if let note = a.note { try require(safe(note, max: 240), "Unsafe action note") }
                if let d = a.repeatDelayMS { try require((250...2000).contains(d), "Invalid repeat delay") }
                if let i = a.repeatIntervalMS { try require((25...1000).contains(i), "Invalid repeat interval") }
            }
            if let id = p.dpiPreset { try require(c.dpiPresets.contains { $0.id == id }, "Dangling DPI preset") }
            if let s = p.scroll { try require(s.verticalScale.isFinite && s.horizontalScale.isFinite && (0.1...4).contains(s.verticalScale) && (0.1...4).contains(s.horizontalScale), "Invalid scroll scale") }
            if let w = p.wheelMode { try require((1...2).contains(w), "Invalid wheel mode") }
            if let t = p.smartShiftThreshold { try require((1...50).contains(t) || t == 255, "Invalid SmartShift threshold") }
            if let k = p.keyboardSettings {
                if let v = k.backlightMode { try require((0...3).contains(v), "Invalid backlight mode") }
                if let v = k.brightness { try require((0...100).contains(v), "Invalid brightness") }
                if let v = k.durationSeconds { try require((5...600).contains(v) && v % 5 == 0, "Invalid duration") }
                if let v = k.effect { try require((0...15).contains(v), "Invalid effect") }
            }
            try require(p.observations.count <= 20, "Too many observations")
            for (k,v) in p.observations { try require(safe(k) && safe(v, max: 500), "Unsafe provenance") }
        }
    }
    public static func diff(_ old: Configuration, _ new: Configuration) -> [String] {
        var lines = ["Schema \(new.schemaVersion); \(new.profiles.count) profiles; \(new.dpiPresets.count) DPI presets", "Devices: MX Master 3S + MX Mechanical Mini for Mac"]
        for p in new.profiles {
            guard let prior = old.profiles.first(where: { $0.id == p.id }) else { lines.append("Add profile: \(p.name)"); continue }
            if p.name != prior.name { lines.append("Rename \(prior.name) to \(p.name)") }
            if p.bundleID != prior.bundleID { lines.append("\(p.name): app association → \(p.bundleID ?? "unresolved")") }
            for (label,a,b) in [("mouse",prior.mouse,p.mouse),("keyboard",prior.keyboard,p.keyboard),("gestures",prior.gestures,p.gestures)] {
                for key in Set(a.keys).union(b.keys).sorted() where a[key] != b[key] { lines.append("\(p.name) · \(label) · \(key): \(a[key]?.label ?? "inherit") → \(b[key]?.label ?? "inherit")") }
            }
            if p.dpiPreset != prior.dpiPreset { lines.append("\(p.name): DPI preset association changed") }
            if p.scroll != prior.scroll { lines.append("\(p.name): scroll \(String(describing: prior.scroll)) → \(String(describing: p.scroll))") }
            if p.keyboardSettings != prior.keyboardSettings { lines.append("\(p.name): keyboard \(String(describing: prior.keyboardSettings)) → \(String(describing: p.keyboardSettings))") }
            if p.wheelMode != prior.wheelMode || p.smartShiftThreshold != prior.smartShiftThreshold { lines.append("\(p.name): wheel mode \(String(describing: prior.wheelMode)) → \(String(describing: p.wheelMode)); threshold \(String(describing: prior.smartShiftThreshold)) → \(String(describing: p.smartShiftThreshold))") }
            if p.observations != prior.observations { lines.append("\(p.name): source observations changed (not executed)") }
        }
        for p in old.profiles where !new.profiles.contains(where: { $0.id == p.id }) { lines.append("Remove profile: \(p.name)") }
        if old.dpiPresets != new.dpiPresets { lines.append("DPI presets: \(old.dpiPresets.map { "\($0.name)=\($0.dpi)" }) → \(new.dpiPresets.map { "\($0.name)=\($0.dpi)" })") }
        if old.switchHardwareWithApps != new.switchHardwareWithApps { lines.append("Switch hardware with apps: \(new.switchHardwareWithApps)") }
        if old.theme != new.theme { lines.append("Theme: \(new.theme)") }
        return lines
    }
}
public enum HIDKeyMap {
    // USB keyboard usages -> macOS ANSI virtual keycodes, never source cNNN slots.
    public static let virtualKey: [Int: UInt16] = [4:0,5:11,6:8,7:2,8:14,9:3,10:5,11:4,12:34,13:38,14:40,15:37,16:46,17:45,18:31,19:35,20:12,21:15,22:1,23:17,24:32,25:9,26:13,27:7,28:16,29:6,30:18,31:19,32:20,33:21,34:23,35:22,36:26,37:28,38:25,39:29,40:36,41:53,42:51,43:48,44:49,45:27,46:24,47:33,48:30,49:42,51:41,52:39,53:50,54:43,55:47,56:44,58:122,59:120,60:99,61:118,62:96,63:97,64:98,65:100,66:101,67:109,68:103,69:111,73:114,74:115,75:116,76:117,77:119,78:121,79:124,80:123,81:125,82:126,
        84:75,85:67,86:78,87:69,88:76,89:83,90:84,91:85,92:86,93:87,94:88,95:89,96:91,97:92,98:82,99:65,103:81,104:105,105:107,106:113,107:106,108:64,109:79,110:80,111:90]
    private static let reverse: [UInt16: Int] = Dictionary(uniqueKeysWithValues: virtualKey.map { ($0.value, $0.key) })
    /// Reverse lookup used by the shortcut recorder.
    public static func usage(forVirtualKey code: UInt16) -> Int? { reverse[code] }
    private static let names: [UInt16: String] = [0:"A",11:"B",8:"C",2:"D",14:"E",3:"F",5:"G",4:"H",34:"I",38:"J",40:"K",37:"L",46:"M",45:"N",31:"O",35:"P",12:"Q",15:"R",1:"S",17:"T",32:"U",9:"V",13:"W",7:"X",16:"Y",6:"Z",18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9",29:"0",36:"Return",53:"Esc",51:"Delete",48:"Tab",49:"Space",27:"-",24:"=",33:"[",30:"]",42:"\\",41:";",39:"'",50:"`",43:",",47:".",44:"/",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15",106:"F16",64:"F17",79:"F18",80:"F19",90:"F20",114:"Help",115:"Home",116:"Page Up",117:"Forward Delete",119:"End",121:"Page Down",124:"Right",123:"Left",125:"Down",126:"Up",75:"Keypad /",67:"Keypad *",78:"Keypad -",69:"Keypad +",76:"Keypad Enter",83:"Keypad 1",84:"Keypad 2",85:"Keypad 3",86:"Keypad 4",87:"Keypad 5",88:"Keypad 6",89:"Keypad 7",91:"Keypad 8",92:"Keypad 9",82:"Keypad 0",65:"Keypad .",81:"Keypad ="]
    /// Human label such as "⌃⌥⇧⌘ /" in the macOS modifier order.
    public static func describe(usage: Int, modifiers: [Int]) -> String {
        let glyph = [224:"⌃",226:"⌥",225:"⇧",227:"⌘"]
        let mods = [224,226,225,227].filter { modifiers.contains($0) }.compactMap { glyph[$0] }.joined()
        let key = virtualKey[usage].flatMap { names[$0] } ?? "USB \(usage)"
        return mods.isEmpty ? key : mods + " " + key
    }
}
