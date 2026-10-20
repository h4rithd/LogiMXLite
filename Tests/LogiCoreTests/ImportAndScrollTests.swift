import Foundation
import Testing
@testable import LogiCore

@Test func keyRecorderReverseLookupRoundTrips() {
    for (usage, code) in HIDKeyMap.virtualKey { #expect(HIDKeyMap.usage(forVirtualKey: code) == usage) }
    #expect(HIDKeyMap.usage(forVirtualKey: 33) == 47)
    #expect(HIDKeyMap.describe(usage: 47, modifiers: [227]) == "⌘ [")
    #expect(HIDKeyMap.describe(usage: 56, modifiers: [225, 226]) == "⌥⇧ /")
    #expect(HIDKeyMap.usage(forVirtualKey: 105) != nil)
}
@Test func scrollTransformFollowsSystemDirection() {
    var s = ScrollSettings(); s.verticalScale = 2; s.natural = true; s.horizontalScale = 0.5; s.horizontalInverted = true
    let same = ScrollTransform(settings: s, systemNatural: true)
    #expect(same.verticalFactor == 2); #expect(same.horizontalFactor == -0.5)
    #expect(ScrollTransform(settings: s, systemNatural: false).verticalFactor == -2)
    #expect(ScrollTransform(settings: ScrollSettings(), systemNatural: true).isIdentity)
}
@Test func residualScalerKeepsSlowTicks() {
    var r = ResidualScaler(); var total = 0
    for _ in 0..<10 { total += r.scale(1, by: 0.5) }
    #expect(total == 5)
    var n = ResidualScaler(); #expect(n.scale(.nan, by: 1) == 0)
}
@Test func smoothScrollerConservesDistance() {
    var s = SmoothScroller(); s.add(x: 37, y: -120)
    var x = 0, y = 0, steps = 0
    while !s.isIdle && steps < 2000 { let o = s.step(dt: 0.008); x += o.x; y += o.y; steps += 1 }
    #expect(abs(x - 37) <= 1); #expect(abs(y + 120) <= 1); #expect(steps < 2000)
}
@Test func optionsPlusActionsAndScrollMapping() throws {
    func card(_ macro: [String: Any], id: String = "x") -> [String: Any] { ["macro": macro, "id": id] }
    #expect(OptionsPlusImport.action(card(["type": "MOUSE", "mouse": ["action": "OSX_GESTURE_BACK"]])).kind == .back)
    #expect(OptionsPlusImport.action(card(["type": "MOUSE", "mouse": ["action": "OSX_GESTURE_FORWARD"]])).kind == .forward)
    #expect(OptionsPlusImport.action(card(["type": "SYSTEM", "system": ["action": "BACKLIGHT_UP"]])).kind == .backlightUp)
    #expect(OptionsPlusImport.action(card(["type": "SYSTEM", "system": ["action": "SMART_ZOOM"]])).kind == .smartZoom)
    #expect(OptionsPlusImport.action(["id": "inner_card_pan_smart_zoom"]).kind == .smartZoom)
    #expect(OptionsPlusImport.action(card(["type": "SYSTEM", "system": ["action": "DO_NOT_DISTURB"]])).kind == .requiresConfirmation)
    let key = OptionsPlusImport.action(card(["type": "KEYSTROKE", "keystroke": ["code": 56, "modifiers": [226, 225, 226]]]))
    #expect(key.kind == .shortcut && key.usage == 56 && key.modifiers == [225, 226])
    let right = OptionsPlusImport.action(card(["type": "KEYSTROKE", "keystroke": ["code": 47, "modifiers": [229, 231]]]))
    #expect(right == Action(.shortcut, usage: 47, modifiers: [225, 227]))
    let unknown = OptionsPlusImport.action(card(["type": "KEYSTROKE", "keystroke": ["code": 47, "modifiers": [232]]]))
    #expect(unknown.kind == .requiresConfirmation)
    #expect(OptionsPlusImport.scale(0) == 1); #expect(OptionsPlusImport.scale(1) == 4); #expect(OptionsPlusImport.scale(-1) == 0.25)
    #expect(OptionsPlusImport.sliderPercent(OptionsPlusImport.scale(0.2)) == 60)
    #expect(OptionsPlusImport.sliderPercent(OptionsPlusImport.scale(0.68)) == 84)
}
@Test func optionsPlusRootConversion() throws {
    func slot(_ id: String, _ card: [String: Any]) -> [String: Any] { ["slotId": id, "card": card] }
    let desktop: [String: Any] = ["applicationId": "d", "name": "PROFILE_NAME_DEFAULT", "activeForApplication": true, "assignments": [
        slot("mx-master-3s-2b034_c83", ["id": "b", "macro": ["type": "MOUSE", "mouse": ["action": "OSX_GESTURE_BACK"]]]),
        slot("mx-master-3s-2b034_mouse_scroll_wheel_settings", ["mouseScrollWheelSettings": ["dir": "NATURAL", "isSmooth": true, "speed": 0.2, "smartshift": ["mode": "FREESPIN", "sensitivity": 50]]]),
        slot("mx-master-3s-2b034_mouse_thumb_wheel_settings", ["mouseThumbWheelSettings": ["dir": "STANDARD", "isSmooth": true, "speed": 0.68]]),
        slot("mx-mechanical-mini-mac-2b36d_c226", ["id": "k", "macro": ["type": "SYSTEM", "system": ["action": "BACKLIGHT_DOWN"]]]),
    ]]
    let app: [String: Any] = ["applicationId": "application_id_microsoft_excel", "assignments": [
        slot("mx-master-3s-2b034_c83", ["id": "b", "macro": ["type": "MOUSE", "mouse": ["action": "OSX_GESTURE_BACK"]]]),
        slot("mx-master-3s-2b034_c86", ["id": "f", "macro": ["type": "MOUSE", "mouse": ["action": "OSX_GESTURE_FORWARD"]]]),
    ]]
    let root: [String: Any] = ["profile_keys": ["profile-d", "profile-x"], "profile-d": desktop, "profile-x": app,
        "applications": ["applications": [["applicationId": "application_id_microsoft_excel", "name": "Microsoft Excel", "applicationPath": "/nonexistent/Excel.app"]]]]
    let result = try OptionsPlusImport.convert(root: root, existing: nil) { _ in nil }
    let c = result.configuration
    #expect(c.desktop.mouse["c83"]?.kind == .back)
    #expect(c.desktop.keyboard["c226"]?.kind == .backlightDown)
    let scroll = try #require(c.desktop.scroll)
    #expect(scroll.natural && scroll.smooth && abs(scroll.verticalScale - pow(4, 0.2)) < 1e-9 && abs(scroll.horizontalScale - pow(4, 0.68)) < 1e-9)
    #expect(c.desktop.wheelMode == 1 && c.desktop.smartShiftThreshold == 50)
    let excel = try #require(c.profiles.first { !$0.isDefault })
    #expect(excel.bundleID == "com.microsoft.Excel")
    #expect(excel.mouse["c83"] == nil && excel.mouse["c86"]?.kind == .forward)
    #expect(excel.scroll == nil)
}
@Test func optionsPlusRejectsRootWithoutProfiles() {
    #expect(throws: ConfigError.self) { try OptionsPlusImport.convert(root: [:], existing: nil) { _ in nil } }
}
@Test func optionsPlusSystemActionsMapToMacShortcuts() {
    func system(_ op: String) -> Action { OptionsPlusImport.action(["macro": ["type": "SYSTEM", "system": ["action": op]]]) }
    #expect(system("CLOSE") == Action(.shortcut, usage: 26, modifiers: [227]))
    #expect(system("MINIMIZE") == Action(.shortcut, usage: 16, modifiers: [227]))
    #expect(system("LOCK") == Action(.shortcut, usage: 20, modifiers: [224, 227]))
    #expect(system("ZOOM_IN") == Action(.shortcut, usage: 46, modifiers: [227]))
    #expect(system("SWITCH_APPS") == Action(.shortcut, usage: 43, modifiers: [227]))
    #expect(system("SHOW_DESKTOP").kind == .showDesktop)
    #expect(system("BRIGHTNESS_UP").kind == .brightnessUp)
    #expect(system("FN_LOCK_TOGGLE").kind == .fnLockToggle)
    #expect(system("SHUT_DOWN").kind == .requiresConfirmation)
    #expect(system("WORD_ZOOM_IN").kind == .requiresConfirmation)
    #expect(OptionsPlusImport.action(["id": "inner_card_an_left_application"]) == Action(.shortcut, usage: 43, modifiers: [225, 227]))
    #expect(OptionsPlusImport.action(["macro": ["type": "QUICK_LAUNCH", "quickLaunch": ["action": "CALCULATOR"]]]).kind == .calculator)
}
@Test func optionsPlusThumbWheelModes() {
    #expect(OptionsPlusImport.thumbAction(["id": "card_global_presets_osx_zoom"]).kind == .thumbZoom)
    #expect(OptionsPlusImport.thumbAction(["id": "card_global_presets_osx_switch_desktops"]).kind == .thumbDesktops)
    #expect(OptionsPlusImport.thumbAction(["id": "card_global_presets_osx_volume_control"]).kind == .thumbVolume)
    #expect(OptionsPlusImport.thumbAction(["id": "card_global_presets_thumbwheel_do_nothing"]).kind == ActionKind.none)
    #expect(OptionsPlusImport.thumbAction(["id": "card_global_presets_osx_horizontal_scroll"]).kind == .nativeHorizontalScroll)
    #expect(OptionsPlusImport.thumbAction(["id": "card_word_osx_zoom"]).kind == .requiresConfirmation)
    #expect(ActionKind.thumbModes.allSatisfy(\.isThumbMode) && !ActionKind.back.isThumbMode)
}
