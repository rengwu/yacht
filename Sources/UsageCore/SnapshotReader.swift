import Foundation

/// Parses the snapshot file the tap writes:
/// `{rate_limits: {five_hour?, seven_day?}, updated_at}`.
/// Anything that cannot be read honestly — malformed JSON, a non-object, a
/// missing capture time — is `nil`, and displays as "no data", never as 0%.
public enum SnapshotReader {

    public static func parse(_ data: Data) -> Snapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let updated = root["updated_at"] as? Double
        else { return nil }

        let limits = root["rate_limits"] as? [String: Any] ?? [:]

        func window(_ key: String) -> LimitWindow? {
            guard let raw = limits[key] as? [String: Any],
                  let used = raw["used_percentage"] as? Double,
                  let resets = raw["resets_at"] as? Double
            else { return nil }
            return LimitWindow(
                usedPercentage: used,
                resetsAt: Date(timeIntervalSince1970: resets)
            )
        }

        return Snapshot(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    public static func read(configDir: URL) -> Snapshot? {
        let file = configDir.appendingPathComponent("usage-snapshot.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data)
    }
}
