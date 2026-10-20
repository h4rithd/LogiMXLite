import Foundation
import Darwin

/// File I/O is actor isolated, never performed in an event callback or on the UI actor.
public actor SettingsStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public var file: URL { directory.appendingPathComponent("settings.json") }
    public var backupFile: URL { directory.appendingPathComponent("backup.json") }
    private func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw ConfigError.invalid("Settings directory must be a real directory") }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    public static func readBounded(_ url: URL) throws -> Data {
        // Open and inspect the same descriptor. A path check followed by FileHandle
        // can be raced into a symlink or a pipe by another process.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw ConfigError.invalid("Select a regular JSON file no larger than 1 MiB") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var statBuffer = stat()
        guard fstat(fd, &statBuffer) == 0,
              statBuffer.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              statBuffer.st_size >= 0, statBuffer.st_size <= ConfigCodec.limit else {
            throw ConfigError.invalid("Select a regular JSON file no larger than 1 MiB")
        }
        var data = Data()
        while data.count <= ConfigCodec.limit {
            let chunk = try handle.read(upToCount: min(65_536, ConfigCodec.limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= ConfigCodec.limit else { throw ConfigError.invalid("Import exceeds 1 MiB") }
        return data
    }
    private static func writePrivate(_ data: Data, to url: URL) throws {
        var template = Array(url.deletingLastPathComponent().appendingPathComponent(".logimxlite-XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let temporary = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        defer { _ = unlink(temporary) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard fchmod(fd, 0o600) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard rename(temporary, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    public func load() throws -> Configuration {
        try prepare()
        if FileManager.default.fileExists(atPath: file.path) { return try ConfigCodec.decode(Self.readBounded(file)) }
        let initial = try ReferenceMigration.defaults(); try save(initial); return initial
    }
    public func save(_ c: Configuration) throws {
        let data = try ConfigCodec.encode(c); try prepare()
        try Self.writePrivate(data, to:file)
    }
    public func backup(_ c: Configuration) throws {
        try prepare(); try Self.writePrivate(ConfigCodec.encode(c), to:backupFile)
    }
    public func preview(_ url: URL, current: Configuration) throws -> ImportPreview {
        let c = try ConfigCodec.decode(Self.readBounded(url))
        return ImportPreview(configuration:c, changes:ConfigCodec.diff(current,c), baseline:current)
    }
    public func previewOptionsPlus(_ url: URL, current: Configuration) throws -> ImportPreview {
        let result = try OptionsPlusImport.load(databaseAt: url, existing: current)
        return ImportPreview(configuration: result.configuration, changes: result.notes + ConfigCodec.diff(current, result.configuration), baseline: current)
    }
    public func commit(_ preview: ImportPreview, current: Configuration) throws -> Configuration {
        guard preview.baseline == current else { throw ConfigError.invalid("Settings changed during preview. Preview the import again.") }
        try ConfigCodec.validate(preview.configuration)
        try backup(current)
        // Atomic write failure leaves the old file intact. UI adopts only the returned configuration.
        try save(preview.configuration)
        return preview.configuration
    }
    public func restorePreview(current: Configuration) throws -> ImportPreview { try preview(backupFile, current:current) }
    public func export(_ c: Configuration, to url: URL) throws { try Self.writePrivate(ConfigCodec.encode(c), to:url) }
}
public struct ImportPreview: Sendable {
    public let configuration: Configuration
    public let changes: [String]
    public let baseline: Configuration
    public init(configuration: Configuration, changes: [String], baseline: Configuration) { self.configuration = configuration; self.changes = changes; self.baseline = baseline }
}
