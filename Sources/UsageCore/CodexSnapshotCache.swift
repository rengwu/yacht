import Foundation

/// One last-known snapshot per CODEX_HOME. The caller chooses a Yacht-owned
/// cache URL; this type has no path into CODEX_HOME except the standardized
/// directory string used as the account key.
public enum CodexSnapshotCache {
    public static func load(from url: URL) -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? decoder.decode([String: Snapshot].self, from: data)
        else { return [:] }
        return entries
    }

    public static func snapshot(codexHome: URL, in cache: [String: Snapshot]) -> Snapshot? {
        cache[key(codexHome)]
    }

    public static func store(
        _ snapshot: Snapshot, codexHome: URL, at url: URL
    ) throws {
        var cache = load(from: url)
        cache[key(codexHome)] = snapshot
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try encoder.encode(cache).write(to: url, options: .atomic)
    }

    private static func key(_ codexHome: URL) -> String {
        codexHome.standardizedFileURL.path
    }

    private static let decoder = JSONDecoder()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
