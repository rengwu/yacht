import Foundation

/// What the app persists: registered accounts, everything `AppSettings` holds,
/// and machine-wide provider installation choices.
public struct AppConfig: Equatable, Codable {
    public var accounts: [Account]
    public var warnThreshold: Double
    public var rowTemplate: String
    public var showMenuBarIcon: Bool
    public var menuBarIcon: String
    public var menuBarTemplate: String
    public var menuBarNoDataTemplate: String
    public var menuBarSeparator: String
    public var menuBarMaxAccounts: Int
    /// A user-selected codex executable, shared by every Codex account on this
    /// machine. `nil` means discover one from the settled candidate list.
    public var codexBinaryPath: String?
    public var display: DisplayPreferences

    public init(
        accounts: [Account] = [],
        warnThreshold: Double = 75,
        rowTemplate: String = AppSettings.defaultRowTemplate,
        showMenuBarIcon: Bool = true,
        menuBarIcon: String = AppSettings.defaultMenuBarIcon,
        menuBarTemplate: String = AppSettings.defaultMenuBarTemplate,
        menuBarNoDataTemplate: String = AppSettings.defaultMenuBarNoDataTemplate,
        menuBarSeparator: String = AppSettings.defaultMenuBarSeparator,
        menuBarMaxAccounts: Int = 0,
        codexBinaryPath: String? = nil,
        display: DisplayPreferences = DisplayPreferences()
    ) {
        self.accounts = accounts
        self.warnThreshold = warnThreshold
        self.rowTemplate = rowTemplate
        self.showMenuBarIcon = showMenuBarIcon
        self.menuBarIcon = menuBarIcon
        self.menuBarTemplate = menuBarTemplate
        self.menuBarNoDataTemplate = menuBarNoDataTemplate
        self.menuBarSeparator = menuBarSeparator
        self.menuBarMaxAccounts = menuBarMaxAccounts
        self.codexBinaryPath = codexBinaryPath
        self.display = display
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
                ?? AppSettings.defaultRowTemplate,
            showMenuBarIcon: try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true,
            menuBarIcon: try c.decodeIfPresent(String.self, forKey: .menuBarIcon)
                ?? AppSettings.defaultMenuBarIcon,
            menuBarTemplate: try c.decodeIfPresent(String.self, forKey: .menuBarTemplate)
                ?? AppSettings.defaultMenuBarTemplate,
            menuBarNoDataTemplate: try c.decodeIfPresent(String.self, forKey: .menuBarNoDataTemplate)
                ?? AppSettings.defaultMenuBarNoDataTemplate,
            menuBarSeparator: try c.decodeIfPresent(String.self, forKey: .menuBarSeparator)
                ?? AppSettings.defaultMenuBarSeparator,
            menuBarMaxAccounts: try c.decodeIfPresent(Int.self, forKey: .menuBarMaxAccounts) ?? 0,
            codexBinaryPath: try c.decodeIfPresent(String.self, forKey: .codexBinaryPath),
            display: try c.decodeIfPresent(DisplayPreferences.self, forKey: .display)
                ?? DisplayPreferences()
        )
    }

    public var settings: AppSettings {
        AppSettings(
            warnThreshold: warnThreshold,
            rowTemplate: rowTemplate,
            showMenuBarIcon: showMenuBarIcon,
            menuBarIcon: menuBarIcon,
            menuBarTemplate: menuBarTemplate,
            menuBarNoDataTemplate: menuBarNoDataTemplate,
            menuBarSeparator: menuBarSeparator,
            menuBarMaxAccounts: menuBarMaxAccounts
        )
    }

    // Account mutations address an account by its config directory — its identity —
    // never by position. A UI that holds an index holds a claim that the list has
    // not changed since, and it has: AppKit commits a pending field edit *after*
    // the button action that removed the row, so an index-addressed rename lands
    // on whichever account slid into that slot. Addressed by directory, the same
    // stale edit finds nothing and is dropped, which is what it deserves.

    public mutating func remove(configDir: URL) {
        accounts.removeAll { $0.configDir.isSameDirectory(as: configDir) }
    }

    /// Renames the account at `configDir`. An account that is no longer registered
    /// is not an error — the rename simply has no target.
    public mutating func relabel(configDir: URL, to label: String) {
        guard let i = accounts.firstIndex(where: { $0.configDir.isSameDirectory(as: configDir) })
        else { return }
        accounts[i].label = label
    }

    public func account(configDir: URL) -> Account? {
        accounts.first { $0.configDir.isSameDirectory(as: configDir) }
    }

    /// Folder identity is stable across edits and reordering. A duplicate registration
    /// must not start a second poller or make remove/rename affect two rows.
    @discardableResult
    public mutating func register(_ account: Account) -> Bool {
        guard self.account(configDir: account.configDir) == nil else { return false }
        accounts.append(account)
        return true
    }

    public mutating func moveAccount(configDir: URL, before destination: Int) {
        guard let source = accounts.firstIndex(where: { $0.configDir.isSameDirectory(as: configDir) })
        else { return }
        let target = max(0, min(accounts.count, destination))
        let account = accounts.remove(at: source)
        accounts.insert(account, at: target > source ? target - 1 : target)
    }
}

extension URL {
    func isSameDirectory(as other: URL) -> Bool {
        standardizedFileURL.path == other.standardizedFileURL.path
    }
}

extension Account: Codable {
    enum CodingKeys: String, CodingKey {
        case provider, label, configDir, showInMenuBar, menuBarWindow
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            // v0.1.4 and every earlier config predates providers. Those accounts
            // were all Claude accounts, so absence is meaningful compatibility,
            // not a malformed row.
            provider: try c.decodeIfPresent(Provider.self, forKey: .provider) ?? .claude,
            label: try c.decode(String.self, forKey: .label),
            configDir: URL(fileURLWithPath: try c.decode(String.self, forKey: .configDir)),
            showInMenuBar: try c.decodeIfPresent(Bool.self, forKey: .showInMenuBar) ?? true,
            menuBarWindow: try c.decodeIfPresent(UsageWindow.self, forKey: .menuBarWindow)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(label, forKey: .label)
        try c.encode(configDir.path, forKey: .configDir)
        try c.encode(showInMenuBar, forKey: .showInMenuBar)
        try c.encodeIfPresent(menuBarWindow, forKey: .menuBarWindow)
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
/// directories in the home whose name starts with a provider's dot prefix.
/// A convenience; the manual folder picker is what makes it non-binding.
public enum Discovery {
    /// Claude names the convention itself (`~/.claude`, `~/.claude-work`).
    public static func claudeConfigDirs(home: URL) -> [URL] {
        hiddenDirectories(home: home, withPrefix: ".claude")
    }

    /// The default Codex home and sibling profiles such as `~/.codex-work`.
    public static func codexConfigDirs(home: URL) -> [URL] {
        hiddenDirectories(home: home, withPrefix: ".codex")
    }

    /// Current Kimi Code homes first, then legacy `.kimi*` homes with credentials.
    public static func kimiConfigDirs(home: URL) -> [URL] {
        let directories = hiddenDirectories(home: home, withPrefix: ".kimi")
        let current = directories.filter { $0.lastPathComponent.hasPrefix(".kimi-code") }
        let legacy = directories.filter {
            !$0.lastPathComponent.hasPrefix(".kimi-code")
                && FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent(KimiCredentialStore.relativePath).path
                )
        }
        return current + legacy
    }

    /// Grok has one canonical home per account (`~/.grok`; further accounts via
    /// `GROK_HOME`), and its folder follows the same dot convention.
    public static func grokConfigDirs(home: URL) -> [URL] {
        hiddenDirectories(home: home, withPrefix: ".grok")
    }

    private static func hiddenDirectories(home: URL, withPrefix prefix: String) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: home, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter {
                $0.lastPathComponent.hasPrefix(prefix)
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
