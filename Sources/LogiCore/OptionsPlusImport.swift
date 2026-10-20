import Foundation
import Darwin
import SQLite3

/// Reads a Logi Options+ `settings.db` (read-only, immutable open) and converts it into a native Configuration.
/// Only mappings and wheel settings are read. Accounts, tokens, analytics and device identifiers are ignored.
public enum OptionsPlusImport {
    public struct Result: Sendable {
        public var configuration: Configuration
        public var notes: [String]
    }
    private static let mousePrefix = "mx-master-3s-2b034_"
    private static let keyboardPrefix = "mx-mechanical-mini-mac-2b36d_"
    private static let knownBundles = [
        "application_id_microsoft_excel": "com.microsoft.Excel",
        "application_id_microsoft_powerpoint": "com.microsoft.Powerpoint",
        "application_id_microsoft_word": "com.microsoft.Word",
        "application_id_apple_safari": "com.apple.Safari",
    ]
    private static let maxBlob = 16 * 1024 * 1024
    private static let maxDatabase = 64 * 1024 * 1024

    public static func load(databaseAt url: URL, existing: Configuration?) throws -> Result {
        let root = try readRoot(url)
        return try convert(root: root, existing: existing) { path in
            Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
        }
    }

    static func readRoot(_ url: URL) throws -> [String: Any] {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
              metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              metadata.st_size >= 0, metadata.st_size <= maxDatabase else {
            throw ConfigError.invalid("Select a regular Options+ database no larger than 64 MiB")
        }
        var components = URLComponents(); components.scheme = "file"; components.path = url.path
        components.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        guard let uri = components.string else { throw ConfigError.invalid("Invalid database path") }
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK, let db else {
            sqlite3_close(db); throw ConfigError.invalid("Cannot open the Options+ database")
        }
        defer { sqlite3_close(db) }
        sqlite3_limit(db, SQLITE_LIMIT_LENGTH, Int32(maxBlob))
        guard sqlite3_exec(db, "PRAGMA trusted_schema=OFF", nil, nil, nil) == SQLITE_OK else {
            throw ConfigError.invalid("Cannot safely inspect the Options+ database")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT file FROM data ORDER BY _id DESC LIMIT 1", -1, &statement, nil) == SQLITE_OK, let statement else {
            throw ConfigError.invalid("This is not an Options+ settings database")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ConfigError.invalid("The database holds no settings") }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, count <= maxBlob, let bytes = sqlite3_column_blob(statement, 0) else { throw ConfigError.invalid("Settings blob is empty or too large") }
        let data = Data(bytes: bytes, count: count)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ConfigError.invalid("Settings blob is not JSON") }
        return root
    }

    public static func convert(root: [String: Any], existing: Configuration?, bundleFromPath: (String) -> String?) throws -> Result {
        guard let keys = root["profile_keys"] as? [String], !keys.isEmpty else { throw ConfigError.invalid("No profiles found in the database") }
        let apps = ((root["applications"] as? [String: Any])?["applications"] as? [[String: Any]] ?? [])
        var notes: [String] = []
        var profiles: [Profile] = []
        for (index, key) in keys.enumerated() {
            guard let raw = root[key] as? [String: Any], let appID = raw["applicationId"] as? String else { continue }
            let isDefault = raw["activeForApplication"] as? Bool == true || raw["name"] as? String == "PROFILE_NAME_DEFAULT"
            let entry = apps.first { $0["applicationId"] as? String == appID }
            var name = isDefault ? "Desktop" : (entry?["name"] as? String ?? appID)
            if name.lowercased() == "davinci resolve" { name = "DaVinci Resolve" }
            var bundle: String? = nil
            if !isDefault {
                bundle = entry?["bundleId"] as? String
                if bundle == nil, let path = entry?["applicationPath"] as? String { bundle = bundleFromPath(path) }
                if bundle == nil { bundle = knownBundle(appID) }
                if bundle == nil { notes.append("\(name): bundle ID unknown, associate the app manually") }
            }
            var p = Profile(name: name, bundleID: bundle, isDefault: isDefault,
                            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!)
            for assignment in raw["assignments"] as? [[String: Any]] ?? [] {
                guard let slot = assignment["slotId"] as? String, let card = assignment["card"] as? [String: Any] else { continue }
                apply(slot: slot, card: card, to: &p)
            }
            if isDefault {
                p.observations["keyboardLayout"] = "keepKeyboardInOsLayout from Options+"
            }
            profiles.append(p)
        }
        guard profiles.filter(\.isDefault).count == 1 else { throw ConfigError.invalid("Expected exactly one Desktop profile in the database") }
        var config = Configuration(profiles: inheritDesktop(profiles))
        if let existing {
            config.dpiPresets = existing.dpiPresets; config.theme = existing.theme; config.switchHardwareWithApps = existing.switchHardwareWithApps
            for i in config.profiles.indices {
                if let old = existing.profiles.first(where: { $0.bundleID == config.profiles[i].bundleID && $0.isDefault == config.profiles[i].isDefault }) {
                    config.profiles[i].dpiPreset = old.dpiPreset.flatMap { id in config.dpiPresets.contains { $0.id == id } ? id : nil }
                    if config.profiles[i].keyboardSettings == nil { config.profiles[i].keyboardSettings = old.keyboardSettings }
                }
            }
        }
        try ConfigCodec.validate(config)
        return Result(configuration: config, notes: notes)
    }

    /// macOS equivalents of Options+ system actions, from Logitech's own preset keystrokes (US layout).
    static let systemShortcuts: [String: Action] = [
        "CLOSE": Action(.shortcut, usage: 26, modifiers: [227]), "MINIMIZE": Action(.shortcut, usage: 16, modifiers: [227]),
        "LOCK": Action(.shortcut, usage: 20, modifiers: [224, 227]), "FULLSCREEN": Action(.shortcut, usage: 9, modifiers: [224, 227]),
        "COPY": Action(.shortcut, usage: 6, modifiers: [227]), "PASTE": Action(.shortcut, usage: 25, modifiers: [227]),
        "UNDO": Action(.shortcut, usage: 29, modifiers: [227]), "REDO": Action(.shortcut, usage: 29, modifiers: [225, 227]),
        "ZOOM_IN": Action(.shortcut, usage: 46, modifiers: [227]), "ZOOM_OUT": Action(.shortcut, usage: 45, modifiers: [227]),
        "LOOK_UP": Action(.shortcut, usage: 7, modifiers: [224, 227]),
        "SWITCH_APPS": Action(.shortcut, usage: 43, modifiers: [227]), "SHIFT_SWITCH_APPS": Action(.shortcut, usage: 43, modifiers: [225, 227]),
    ]
    /// Gesture sub-presets that Options+ stores without a macro, keyed by card id fragment.
    static let idShortcuts: [String: Action] = [
        "left_application": Action(.shortcut, usage: 43, modifiers: [225, 227]), "switch_application_left": Action(.shortcut, usage: 43, modifiers: [225, 227]),
        "right_application": Action(.shortcut, usage: 43, modifiers: [227]), "switch_application_right": Action(.shortcut, usage: 43, modifiers: [227]),
        "zr_zoom_in": Action(.shortcut, usage: 46, modifiers: [227]), "zr_zoom_out": Action(.shortcut, usage: 45, modifiers: [227]),
    ]
    /// Thumb-wheel adapter cards. Horizontal scroll stays native; app-specific Office zoom is left native.
    static func thumbAction(_ card: [String: Any]) -> Action {
        let id = card["id"] as? String ?? ""
        let modes: [(String, ActionKind)] = [("horizontal_scroll", .nativeHorizontalScroll), ("thumbwheel_do_nothing", .none), ("osx_zoom", .thumbZoom), ("switch_desktops", .thumbDesktops),
            ("volume_control", .thumbVolume), ("application_navigation", .thumbApps), ("tab_navigation", .thumbTabs), ("swipe_pages", .thumbPages),
            ("forward_back", .thumbPages), ("next_previous_track", .thumbTracks), ("brightness_up_down", .thumbBrightness)]
        // Exact global preset ids only: app-specific cards such as card_word_osx_zoom must not match the generic zoom.
        if let kind = modes.first(where: { ["card_global_presets_" + $0.0, "card_global_presets_osx_" + $0.0].contains(id) })?.1 { return Action(kind) }
        return action(card)
    }
    static func knownBundle(_ applicationID: String?) -> String? { applicationID.flatMap { knownBundles[$0] } }
    /// Desktop first; app profiles keep only values that differ from Desktop so everything else inherits.
    static func inheritDesktop(_ input: [Profile]) -> [Profile] {
        var profiles = input.sorted { $0.isDefault && !$1.isDefault }
        guard let base = profiles.first, base.isDefault else { return profiles }
        for i in profiles.indices.dropFirst() {
            profiles[i].mouse = profiles[i].mouse.filter { base.mouse[$0.key] != $0.value }
            profiles[i].keyboard = profiles[i].keyboard.filter { base.keyboard[$0.key] != $0.value }
            profiles[i].gestures = profiles[i].gestures.filter { base.gestures[$0.key] != $0.value }
            if profiles[i].scroll == base.scroll { profiles[i].scroll = nil }
            if profiles[i].wheelMode == base.wheelMode && profiles[i].smartShiftThreshold == base.smartShiftThreshold { profiles[i].wheelMode = nil; profiles[i].smartShiftThreshold = nil }
        }
        return profiles
    }
    private static func apply(slot: String, card: [String: Any], to p: inout Profile) {
        if slot.hasPrefix(mousePrefix) {
            let rest = String(slot.dropFirst(mousePrefix.count))
            switch rest {
            case "c82", "c83", "c86", "c196": p.mouse[rest] = action(card)
            case "thumb_wheel_adapter": p.mouse["thumbWheel"] = thumbAction(card)
            case "c195":
                if let selected = card["selectedNestedCard"] as? String, let nested = (card["nestedCards"] as? [String: Any])?[selected] as? [String: Any],
                   let directions = nested["nestedCards"] as? [String: Any] {
                    for (direction, value) in directions where ["click", "up", "down", "left", "right"].contains(direction) {
                        if let c = value as? [String: Any] { p.gestures[direction] = action(c) }
                    }
                    p.observations["gesturePreset"] = selected
                }
            case "mouse_scroll_wheel_settings":
                if let s = card["mouseScrollWheelSettings"] as? [String: Any] { applyVertical(s, to: &p) }
            case "mouse_thumb_wheel_settings":
                if let s = card["mouseThumbWheelSettings"] as? [String: Any] { applyThumb(s, to: &p) }
            case "mouse_settings":
                if let speed = (((card["mouseSettings"] as? [String: Any])?["pointerSpeed"] as? [String: Any])?["active"] as? [String: Any])?["value"] as? Double {
                    p.observations["pointerNormalized"] = String(speed)
                }
            default: break
            }
        } else if slot.hasPrefix(keyboardPrefix) {
            let rest = String(slot.dropFirst(keyboardPrefix.count))
            if rest.hasPrefix("c"), Int(rest.dropFirst()) != nil { p.keyboard[rest] = action(card) }
            else if rest == "backlighting_settings", let b = card["backlightingSettings"] as? [String: Any] {
                p.observations["backlight"] = "\(b["backlightEffect"] as? String ?? "unknown") powerSave \(b["powerSave"] as? Bool ?? false)"
            }
        }
    }

    /// Options+ speed runs from -1 to 1 (slider 0 to 100 percent). Zero is native speed; each end is 4x slower or faster.
    static func scale(_ normalized: Double) -> Double { pow(4, max(-1, min(1, normalized))) }
    /// Inverse of our bounded event scaling, for displaying the source slider
    /// position. This is not a claim that the physical acceleration curves match.
    public static func sliderPercent(_ scale: Double) -> Int {
        Int(((log(max(0.25, min(4, scale))) / log(4) + 1) * 50).rounded())
    }

    static func applyVertical(_ s: [String: Any], to p: inout Profile) {
        var scroll = p.scroll ?? ScrollSettings()
        scroll.verticalScale = scale(s["speed"] as? Double ?? 0)
        scroll.natural = (s["dir"] as? String) != "STANDARD"
        scroll.smooth = s["isSmooth"] as? Bool ?? false
        p.scroll = scroll
        if let shift = s["smartshift"] as? [String: Any] {
            let sensitivity = min(50, max(1, shift["sensitivity"] as? Int ?? 50))
            switch shift["mode"] as? String {
            case "FREESPIN": p.wheelMode = 1; p.smartShiftThreshold = sensitivity
            case "RATCHET": p.wheelMode = 2; p.smartShiftThreshold = 255
            case "SMARTSHIFT": p.wheelMode = 2; p.smartShiftThreshold = sensitivity
            default: break
            }
            p.observations["wheel"] = "\(shift["mode"] as? String ?? "unknown") sensitivity \(shift["sensitivity"] as? Int ?? 0)"
        }
    }
    static func applyThumb(_ s: [String: Any], to p: inout Profile) {
        var scroll = p.scroll ?? ScrollSettings()
        scroll.horizontalScale = scale(s["speed"] as? Double ?? 0)
        scroll.horizontalInverted = (s["dir"] as? String) == "NATURAL"
        p.scroll = scroll
    }

    static func action(_ card: [String: Any]) -> Action {
        let macro = card["macro"] as? [String: Any] ?? [:]
        let id = card["id"] as? String ?? ""
        var a: Action
        func pending(_ note: String) -> Action { Action(.requiresConfirmation, note: note) }
        switch macro["type"] as? String ?? "" {
        case "KEYSTROKE":
            let key = macro["keystroke"] as? [String: Any] ?? [:]
            let sourceModifiers = key["modifiers"] as? [Int] ?? []
            // USB HID defines left modifiers at 224...227 and right modifiers at 228...231.
            // macOS event flags do not distinguish sides. Never drop an unknown modifier:
            // doing so would execute a different and potentially dangerous shortcut.
            let supported = sourceModifiers.allSatisfy { (224...231).contains($0) }
            let mods = Set(sourceModifiers.map { $0 >= 228 ? $0 - 4 : $0 }).sorted()
            if supported, let code = key["code"] as? Int, HIDKeyMap.virtualKey[code] != nil { a = Action(.shortcut, usage: code, modifiers: mods) }
            else { a = pending("Key not supported") }
        case "DO_NOTHING": a = Action(.none)
        case "OPEN_FILE_FOLDER":
            let path = ((macro["openFileFolder"] as? [String: Any])?["path"] as? String) ?? ""
            a = path.hasSuffix("/Downloads") ? Action(.downloads) : pending("Open folder not supported")
        case "SCREEN_CAPTURE": a = Action(.screenshot)
        case "QUICK_LAUNCH":
            let op = (macro["quickLaunch"] as? [String: Any])?["action"] as? String ?? ""
            a = ["MISSION_CONTROL": Action(.missionControl), "LAUNCHPAD": Action(.launchpad), "APP_EXPOSE": Action(.appExpose), "CALCULATOR": Action(.calculator), "SYSTEM_PREFERENCES": Action(.systemSettings)][op] ?? pending(op)
        case "MEDIA":
            let usage = (macro["media"] as? [String: Any])?["usage"] as? String ?? ""
            let kinds: [String: ActionKind] = ["NEXT_TRACK": .nextTrack, "PREVIOUS_TRACK": .previousTrack, "PLAY_PAUSE": .playPause, "VOLUME_DOWN": .volumeDown, "VOLUME_UP": .volumeUp, "MUTE": .mute]
            a = kinds[usage].map { Action($0) } ?? pending(usage)
        case "AUDIO": a = Action(.microphoneMute)
        case "MOUSE":
            let mouse = macro["mouse"] as? [String: Any] ?? [:]
            switch mouse["action"] as? String ?? "" {
            case "BUTTON": a = (mouse["hidUsage"] as? Int) == 3 ? Action(.middleClick) : pending("Mouse button not supported")
            case "OSX_GESTURE_BACK": a = Action(.back)
            case "OSX_GESTURE_FORWARD": a = Action(.forward)
            default: a = pending("Mouse action not supported")
            }
        case "SYSTEM":
            let op = (macro["system"] as? [String: Any])?["action"] as? String ?? "UNKNOWN"
            let kinds: [String: ActionKind] = ["MAXIMIZE": .maximize, "SWITCH_BETWEEN_DESKTOPS_LEFT": .desktopLeft, "SWITCH_BETWEEN_DESKTOPS_RIGHT": .desktopRight, "BACKLIGHT_UP": .backlightUp, "BACKLIGHT_DOWN": .backlightDown, "SMART_ZOOM": .smartZoom,
                "SHOW_DESKTOP": .showDesktop, "BRIGHTNESS_UP": .brightnessUp, "BRIGHTNESS_DOWN": .brightnessDown, "SCROLL_LEFT": .scrollLeft, "SCROLL_RIGHT": .scrollRight, "FN_LOCK_TOGGLE": .fnLockToggle, "LAUNCH_SIRI": .siri]
            a = kinds[op].map { Action($0) } ?? systemShortcuts[op] ?? pending(op)
        default:
            if id.contains("mode_shift") { a = Action(.wheelMode) }
            else if id.contains("smart_zoom") { a = Action(.smartZoom) }
            else if let shortcut = idShortcuts.first(where: { id.contains($0.key) })?.value { a = shortcut }
            else if id.contains("change_pointer_speed") { a = pending("Pointer speed toggle needs calibration") }
            else if id.contains("horizontal_scroll") { a = pending("Native horizontal scroll") }
            else if id.contains("zoom") { a = pending("Application zoom") }
            else { a = pending("Unsupported source action") }
        }
        if [.shortcut, .volumeUp, .volumeDown].contains(a.kind) {
            a.repeatDelayMS = (macro["initPeriod"] as? Int).map { min(2000, max(250, $0)) }
            a.repeatIntervalMS = (macro["repeatPeriod"] as? Int).map { min(1000, max(25, $0)) }
        }
        return a
    }
}
