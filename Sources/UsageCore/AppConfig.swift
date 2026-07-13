import Foundation

/// What the app persists: the registered accounts, the one threshold, the row
/// template.
public struct AppConfig: Equatable, Codable {
    public var accounts: [Account]
    public var warnThreshold: Double
    public var rowTemplate: String

    public init(
        accounts: [Account] = [],
        warnThreshold: Double = 75,
        rowTemplate: String = AppSettings.defaultRowTemplate
    ) {
        self.accounts = accounts
        self.warnThreshold = warnThreshold
        self.rowTemplate = rowTemplate
    }

    /// Every field is optional on the way in, falling back to its default. A
    /// config written by an older build is missing the keys added since, and a
    /// strict decode would throw — which `load` turns into "no accounts", quietly
    /// unregistering everything the user set up. A settings file must only ever
    /// lose the setting it is actually missing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            accounts: try c.decodeIfPresent([Account].self, forKey: .accounts) ?? [],
            warnThreshold: try c.decodeIfPresent(Double.self, forKey: .warnThreshold) ?? 75,
            rowTemplate: try c.decodeIfPresent(String.self, forKey: .rowTemplate)
                ?? AppSettings.defaultRowTemplate
        )
    }

    public var settings: AppSettings {
        AppSettings(warnThreshold: warnThreshold, rowTemplate: rowTemplate)
    }
}

extension Account: Codable {
    enum CodingKeys: String, CodingKey { case label, configDir }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            label: try c.decode(String.self, forKey: .label),
            configDir: URL(fileURLWithPath: try c.decode(String.self, forKey: .configDir))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(configDir.path, forKey: .configDir)
    }
}

public enum ConfigStore {
    /// Missing or unreadable config yields the default (no accounts): the app
    /// starts over rather than crashing, and registering again is cheap.
    public static func load(from url: URL) -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public static func save(_ config: AppConfig, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url, options: .atomic)
    }
}

/// Auto-discovery: config directories adjacent to the default one — hidden
/// directories in the home whose name starts with ".claude". A convenience;
/// the manual folder picker is what makes it non-binding.
public enum Discovery {
    public static func claudeConfigDirs(home: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter {
                $0.lastPathComponent.hasPrefix(".claude")
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
