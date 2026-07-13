import Foundation

/// What a config directory's settings.json says about the tap.
public enum TapStatus: Equatable {
    /// The status line is our tap.
    case installed
    /// No status line configured at all.
    case notInstalled
    /// A status line exists but is not ours — surfaced, never silently replaced.
    case foreign(command: String)
}

public enum TapInstallerError: Error, Equatable {
    /// settings.json exists but is not a JSON object. The file is hand-maintained;
    /// a file we cannot parse is a file we refuse to touch.
    case unreadableSettings
}

/// Installs and detects the tap in a Claude Code settings.json, preserving every
/// unrelated key. Pure Data → Data at its core — the installer seam — with thin
/// file wrappers. Writing happens only when the caller explicitly asks.
public enum TapInstaller {

    /// The statusLine value the tap installs.
    static func statusLineValue(tapCommand: String) -> [String: Any] {
        ["type": "command", "command": tapCommand]
    }

    // MARK: - Pure core (the installer seam)

    public static func detect(settings: Data?, tapCommand: String) -> TapStatus {
        guard let settings,
              let root = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any],
              let statusLine = root["statusLine"]
        else { return .notInstalled }

        guard let line = statusLine as? [String: Any] else {
            return .foreign(command: String(describing: statusLine))
        }
        let command = line["command"] as? String ?? ""
        if line["type"] as? String == "command", command == tapCommand {
            return .installed
        }
        return .foreign(command: command)
    }

    /// Returns new settings JSON with statusLine set to the tap and every other
    /// key preserved. `nil` means no settings file exists yet.
    public static func install(settings: Data?, tapCommand: String) throws -> Data {
        var root: [String: Any] = [:]
        if let settings {
            guard let parsed = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any]
            else { throw TapInstallerError.unreadableSettings }
            root = parsed
        }
        root["statusLine"] = statusLineValue(tapCommand: tapCommand)
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    // MARK: - File wrappers

    public static func detect(configDir: URL, tapCommand: String) -> TapStatus {
        let file = configDir.appendingPathComponent("settings.json")
        return detect(settings: try? Data(contentsOf: file), tapCommand: tapCommand)
    }

    /// Rewrites configDir/settings.json with the tap installed. Atomic; throws
    /// rather than touching a file it cannot parse.
    public static func install(configDir: URL, tapCommand: String) throws {
        let file = configDir.appendingPathComponent("settings.json")
        let existing = try? Data(contentsOf: file)
        let updated = try install(settings: existing, tapCommand: tapCommand)
        try updated.write(to: file, options: .atomic)
    }
}
