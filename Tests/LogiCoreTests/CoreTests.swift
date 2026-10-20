import Testing
import Foundation
import Darwin
@testable import LogiCore

@Test func migrationAndInheritance() throws {
    var c = try ReferenceMigration.defaults()
    #expect(c.profiles.count == 1)
    #expect(c.desktop.mouse["c82"]?.kind == .middleClick)
    #expect(c.desktop.mouse["c86"]?.kind == .forward)
    #expect(c.desktop.mouse["c83"]?.kind == .back)
    #expect(c.desktop.keyboard.isEmpty && c.desktop.gestures.isEmpty)
    var app = Profile(name: "Example App", bundleID: "com.example.app")
    app.mouse["c86"] = Action(.nextTrack)
    c.profiles.append(app)
    let resolved = c.resolved(app.id)
    #expect(resolved.mouse["c82"]?.kind == .middleClick)
    #expect(resolved.mouse["c86"]?.kind == .nextTrack)
    #expect(c.dpiPresets.isEmpty)
    #expect(c.desktop.observations.isEmpty)
    #expect(try ConfigCodec.decode(ConfigCodec.encode(c)) == c)
}
@Test func hostileImports() throws {
    let c = try ReferenceMigration.defaults()
    let valid = try ConfigCodec.encode(c)
    #expect(throws:(any Error).self) { try ConfigCodec.decode(Data(repeating:32,count:ConfigCodec.limit+1)) }
    for junk in ["{}", "[]", "null", "{", "{\"schemaVersion\":999}"] { #expect(throws:(any Error).self) { try ConfigCodec.decode(Data(junk.utf8)) } }
    var bad = c; bad.schemaVersion = 2
    #expect(throws:(any Error).self) { try ConfigCodec.validate(bad) }
    bad = c; bad.profiles[0].mouse["c82"] = Action(.downloads,note:"../../private/etc/passwd")
    #expect(throws:(any Error).self) { try ConfigCodec.validate(bad) }
    bad = c; bad.profiles[0].mouse["c82"] = Action(.shortcut,usage:999)
    #expect(throws:(any Error).self) { try ConfigCodec.validate(bad) }
    bad = c; bad.profiles.append(Profile(name: "Example App", bundleID: "file:///tmp/app"))
    #expect(throws:(any Error).self) { try ConfigCodec.validate(bad) }
    let injected = String(decoding:valid,as:UTF8.self).replacingOccurrences(of:"\"middleClick\"",with:"\"shell\"")
    #expect(throws:(any Error).self) { try ConfigCodec.decode(Data(injected.utf8)) }
    for i in stride(from:0,to:valid.count,by:max(1,valid.count/100)) { #expect(throws:(any Error).self) { try ConfigCodec.decode(valid.prefix(i)) } }
}
@Test func safeDeviceIdentity() {
    #expect(Model.match(vendor:1133,product:0xB034,transport:"Bluetooth Low Energy",name:"MX Master 3S M") == .mouse)
    #expect(Model.match(vendor:1133,product:0xB36D,transport:"Bluetooth Low Energy",name:"MX MCHNCL M") == .keyboard)
    #expect(Model.match(vendor:1133,product:0xB034,transport:"USB",name:"MX Master 3S M") == nil)
    #expect(Model.match(vendor:1133,product:0xB999,transport:"Bluetooth Low Energy",name:"MX Master 3S M") == nil)
}
@Test func packetValidation() throws {
    let p = try Packet(feature:7,function:2,software:10,parameters:[1,2])
    #expect(p.bytes.count == 20)
    #expect(try Packet(bytes:p.bytes).matches(p))
    #expect(!(try Packet(feature:8,function:2)).matches(p))
    for n in 0...100 where n != 20 && n != 7 { #expect(throws:HIDError.self) { try Packet(bytes:Array(repeating:0,count:n)) } }
    var wrong = p.bytes; wrong[1] = 255
    #expect(throws:HIDError.self) { try Packet(bytes:wrong) }
    #expect(throws:HIDError.self) { try Packet(feature:0,function:16) }
    let error = try Packet(bytes:[0x11,1,0xFF,7,0x2A,6] + Array(repeating:0,count:14))
    #expect(error.error(for:p) == 6)
}
@Test func dpiRangeAndKeyTranslation() throws {
    let r = try DPIRange.parse([0,0,100,0xE0,50,0x1F,0x40,0,0])
    #expect(r.supports(1650)); #expect(!r.supports(1651))
    #expect(throws:HIDError.self) { try DPIRange.parse([0,0,100,0xE0,0,0x1F,0x40]) }
    #expect(HIDKeyMap.virtualKey[56] == 44)
    #expect(HIDKeyMap.virtualKey[52] == 39)
    #expect(HIDKeyMap.virtualKey[82] == 126)
}
@Test func gestureMatchesOptionsPlusThresholds() {
    var g = GestureMachine()
    // Small wobble during a click stays a click (below the 50-unit start threshold).
    g.press(at:0); #expect(g.move(dx:20,dy:15,at:0.05) == nil); #expect(g.release(at:0.1) == .click)
    // Started but never reached 250: no click and no action.
    g.press(at:1); #expect(g.move(dx:120,dy:10,at:1.1) == nil); #expect(g.release(at:1.2) == nil)
    // Action fires during the hold as soon as 250 is reached, not on release.
    g.press(at:2); #expect(g.move(dx:200,dy:5,at:2.05) == nil); #expect(g.move(dx:60,dy:0,at:2.1) == .right)
    // A further 250 inside the 400 ms pause does not repeat; after the pause it does.
    #expect(g.move(dx:260,dy:0,at:2.3) == nil); #expect(g.move(dx:10,dy:0,at:2.6) == .right)
    #expect(g.release(at:2.7) == nil)
    g.press(at:3); #expect(g.move(dx:0,dy:-300,at:3.1) == .up); _ = g.release(at:3.2)
    g.press(at:4); #expect(g.move(dx:-300,dy:20,at:4.1) == .left); _ = g.release(at:4.2)
    g.press(at:5); #expect(g.move(dx:.nan,dy:0,at:5.1) == nil); g.cancel(); #expect(g.release(at:5.2) == nil)
    // The official four-way recognizer drops samples near a diagonal; they must
    // not accidentally select a horizontal direction as the old max-axis rule did.
    g.press(at:6)
    #expect(g.move(dx:190,dy:170,at:6.1) == nil)
    #expect(g.move(dx:180,dy:160,at:6.2) == nil)
    #expect(g.release(at:6.3) == .click)
    g.press(at:7)
    #expect(g.move(dx:120,dy:35,at:7.1) == nil)
    #expect(g.move(dx:135,dy:40,at:7.2) == .right)
    g.press(at:8)
    #expect(g.move(dx:80,dy:-160,at:8.1) == nil)
    #expect(g.move(dx:40,dy:-100,at:8.2) == .up)
}
@Test func transitionsAndScrollerBounded() throws {
    var b = ButtonTransitions()
    let first = try b.update([0,82,0,0,0,0,0,0]); #expect(first.down == [82])
    #expect(try b.update([0,82,0,0,0,0,0,0]).down.isEmpty)
    #expect(try b.update(Array(repeating:0,count:8)).up == [82])
    var s = SmoothScroller(); s.add(x:.infinity,y:.nan); #expect(s.isIdle)
}
@Test func transactionalStore() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:url) }
    let store = SettingsStore(directory:url)
    let old = try await store.load(); var new = old; new.theme = "dark"
    let directoryMode = (try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber)?.intValue
    let settingsMode = (try FileManager.default.attributesOfItem(atPath:url.appendingPathComponent("settings.json").path)[.posixPermissions] as? NSNumber)?.intValue
    #expect(directoryMode == 0o700 && settingsMode == 0o600)
    let preview = ImportPreview(configuration:new,changes:ConfigCodec.diff(old,new),baseline:old)
    let applied = try await store.commit(preview,current:old)
    #expect(applied == new); #expect(try await store.load() == new)
    let backup = try await store.restorePreview(current:new)
    #expect(backup.configuration == old)
    let backupMode = (try FileManager.default.attributesOfItem(atPath:url.appendingPathComponent("backup.json").path)[.posixPermissions] as? NSNumber)?.intValue
    #expect(backupMode == 0o600)
    let export = url.appendingPathComponent("export.json")
    try await store.export(new,to:export)
    let exportMode = (try FileManager.default.attributesOfItem(atPath:export.path)[.posixPermissions] as? NSNumber)?.intValue
    #expect(exportMode == 0o600)
    await #expect(throws:(any Error).self) { try await store.commit(preview,current:new) }
    #expect(try await store.load() == new)
}
@Test func rapidSwitchUsesLastRevision() {
    var r = ProfileRevision(); let a = r.next(); let b = r.next()
    #expect(!r.isCurrent(a)); #expect(r.isCurrent(b))
}
@Test func conflictFalsePositives() {
    #expect(!ConflictDetector.matches("com.apple.loginwindow"))
    #expect(!ConflictDetector.matches("com.h4rithd.LogiMXLite"))
    #expect(ConflictDetector.matches("com.logi.optionsplus"))
}
@Test func permissionsFailClosed() {
    #expect(PermissionGate.evaluate(input:false,accessibility:true,secure:false,conflicts:false) == .inputMonitoring)
    #expect(PermissionGate.evaluate(input:true,accessibility:false,secure:false,conflicts:false) == .accessibility)
    #expect(PermissionGate.evaluate(input:true,accessibility:true,secure:true,conflicts:false) == .secureInput)
    #expect(PermissionGate.evaluate(input:true,accessibility:true,secure:false,conflicts:true) == .conflict)
    #expect(PermissionGate.evaluate(input:true,accessibility:true,secure:false,conflicts:false) == .ready)
}
@Test func mixedDPIListAndOffGridEndpoint() throws {
    #expect(try DPIRange.parse([0,1,144,0xE1,144,5,220]).values == [400,800,1200,1500])
    #expect(try DPIRange.parse([0,6,64,3,32,3,32,0,0]).values == [800,1600])
    #expect(throws:HIDError.self) { try DPIRange.parse([0,0xE0,50,0,100]) }
}
@Test func atomicFailureKeepsExistingSettings() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:dir) }
    let store = SettingsStore(directory:dir); let old = try await store.load()
    // Block backup creation with a directory at the backup destination.
    try FileManager.default.createDirectory(at:dir.appendingPathComponent("backup.json"),withIntermediateDirectories:false)
    var next = old; next.theme = "dark"
    let p = ImportPreview(configuration:next,changes:[],baseline:old)
    await #expect(throws:(any Error).self) { try await store.commit(p,current:old) }
    #expect(try await store.load() == old)
}
@Test func portableExportDropsUnknownFieldsAndRejectsSymlinks() async throws {
    let c = try ReferenceMigration.defaults()
    var object = try JSONSerialization.jsonObject(with:ConfigCodec.encode(c)) as! [String:Any]
    object["optionalFutureExtension"] = ["privatePath":"/Users/secret", "token":"secret"]
    let decoded = try ConfigCodec.decode(JSONSerialization.data(withJSONObject:object))
    let exported = String(decoding:try ConfigCodec.encode(decoded),as:UTF8.self)
    #expect(!exported.contains("/Users/secret")); #expect(!exported.contains("token"))
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:path)}
    try FileManager.default.createSymbolicLink(at:path,withDestinationURL:URL(fileURLWithPath:"/etc/hosts"))
    #expect(throws:(any Error).self) {try SettingsStore.readBounded(path)}
    #expect(throws:(any Error).self) {try OptionsPlusImport.readRoot(path)}
    let pipe = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:pipe)}
    #expect(mkfifo(pipe.path, 0o600) == 0)
    #expect(throws:(any Error).self) {try SettingsStore.readBounded(pipe)}
    let oversized = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {try? FileManager.default.removeItem(at:oversized)}
    #expect(FileManager.default.createFile(atPath:oversized.path,contents:nil))
    let handle = try FileHandle(forWritingTo:oversized)
    try handle.truncate(atOffset:65 * 1024 * 1024)
    try handle.close()
    #expect(throws:ConfigError.self) {try OptionsPlusImport.readRoot(oversized)}
}
@Test func generatedHostilePacketsNeverTrap() {
    var seed: UInt64 = 0x123456
    for length in 0...80 {
        for _ in 0..<30 {
            let bytes = (0..<length).map { _ -> UInt8 in seed = seed &* 6364136223846793005 &+ 1; return UInt8(truncatingIfNeeded:seed >> 32) }
            _ = try? Packet(bytes:bytes)
            _ = try? DPIRange.parse(bytes)
            _ = try? ControlInfo.parse(bytes)
        }
    }
}
