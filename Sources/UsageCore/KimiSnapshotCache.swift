import Foundation

// Persistence for Kimi's last-known figures, and the only reason the domain
// types are Codable at all. It lives apart from `Model.swift` so the encoding
// of a cache file stays a storage concern rather than something the display or
// the adapters have an opinion about.
//
// This writes to Yacht's own Application Support directory and nowhere else.
// The credential file under KIMI_CODE_HOME is read-only to this app — a
// safety boundary, because a write-back there can log the user out of Kimi —
// and nothing in this file goes near it.

// Spelled out rather than synthesised. A cache file outlives the build that
// wrote it, so its keys are a format and must not drift with a property rename;
// and `label` is persisted alongside `window` because an adapter is allowed to
// override it, so re-deriving it on read would quietly relabel those rows.

extension UsageRow: Codable {
    enum CodingKeys: String, CodingKey {
        case window, label, used, limit
        case resetsAt = "resets_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            window: try c.decode(UsageWindow.self, forKey: .window),
            label: try c.decodeIfPresent(String.self, forKey: .label),
            used: try c.decode(Double.self, forKey: .used),
            limit: try c.decode(Double.self, forKey: .limit),
            resetsAt: Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .resetsAt))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(window, forKey: .window)
        try c.encode(label, forKey: .label)
        try c.encode(used, forKey: .used)
        try c.encode(limit, forKey: .limit)
        try c.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
    }
}

extension Snapshot: Codable {
    enum CodingKeys: String, CodingKey {
        case rows
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            rows: try c.decode([UsageRow].self, forKey: .rows),
            updatedAt: Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .updatedAt))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rows, forKey: .rows)
        try c.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
    }
}

/// One cached snapshot per Kimi account, keyed by the account's config
/// directory — the same identity `AppConfig` addresses accounts by, so a
/// re-registered or renamed account keeps its figure and a removed one's entry
/// is simply never read again.
///
/// The cache exists so a relaunch shows the number the bar was showing when it
/// quit. Without it, every reboot or app update blanks Kimi until the user next
/// runs kimi, which is the behaviour carrying figures forward set out to fix —
/// merely on a longer interval.
public enum KimiSnapshotCache {

    /// A read failure of any kind is "no cached figure", never an error: the
    /// cache is an optimisation over the poller's own state, and an unreadable
    /// one costs the user a dash until the next successful poll. It must never
    /// cost them the app.
    public static func load(from url: URL) -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? decoder.decode([String: Snapshot].self, from: data)
        else { return [:] }
        return entries
    }

    public static func snapshot(configDir: URL, in cache: [String: Snapshot]) -> Snapshot? {
        cache[key(configDir)]
    }

    /// Rewrites the whole file with `snapshot` recorded against `configDir`.
    /// Atomic, so a crash mid-write leaves the previous cache intact rather than
    /// a truncated file that reads as no figure at all.
    public static func store(
        _ snapshot: Snapshot, configDir: URL, at url: URL
    ) throws {
        var cache = load(from: url)
        cache[key(configDir)] = snapshot
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoder.encode(cache).write(to: url, options: .atomic)
    }

    private static func key(_ configDir: URL) -> String {
        configDir.standardizedFileURL.path
    }

    private static let decoder = JSONDecoder()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
