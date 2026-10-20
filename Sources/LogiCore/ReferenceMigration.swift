import Foundation

/// Privacy-neutral first-run settings. Existing user settings are loaded from
/// Application Support and are never replaced by these defaults.
public enum ReferenceMigration {
    public static func defaults() throws -> Configuration {
        var desktop = Profile(name: "Desktop", isDefault: true,
                              id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!)
        desktop.mouse = [
            "c82": Action(.middleClick),
            "c83": Action(.back),
            "c86": Action(.forward)
        ]
        let config = Configuration(profiles: [desktop])
        try ConfigCodec.validate(config)
        return config
    }
}
