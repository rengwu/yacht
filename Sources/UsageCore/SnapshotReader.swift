import Foundation

/// The Claude adapter: parses the snapshot file the tap writes:
/// `{rate_limits: {five_hour?, seven_day?}, updated_at}`.
/// Anything that cannot be read honestly — malformed JSON, a non-object, a
/// missing capture time — is `nil`, and displays as "no data", never as 0%.
public enum SnapshotReader {

    /// Claude's `rate_limits` reports a percentage and no denominator at all, so
    /// this adapter supplies the only denominator a percentage has: **a
    /// percentage is a count out of 100**. `used` is the reported figure
    /// verbatim, fraction and overshoot included (the server does report past
    /// 100 — see `Format.percent`), and `limit` is this constant. It is not a
    /// request count and must never be shown as one.
    ///
    /// Kimi's real `limit` is also 100 for the same underlying reason — its
    /// console renders both windows as bare percentages — so the two providers
    /// coincide on a 0–100 scale rather than one being translated into the
    /// other's units.
    static let percentageScale: Double = 100

    public static func parse(_ data: Data) -> Snapshot? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let updated = root["updated_at"] as? Double
        else { return nil }

        let limits = root["rate_limits"] as? [String: Any] ?? [:]

        func row(_ key: String, _ window: UsageWindow) -> UsageRow? {
            guard let raw = limits[key] as? [String: Any],
                  let used = raw["used_percentage"] as? Double,
                  let resets = raw["resets_at"] as? Double
            else { return nil }
            return UsageRow(
                window: window,
                used: used,
                limit: percentageScale,
                resetsAt: Date(timeIntervalSince1970: resets)
            )
        }

        // 5-hour first, weekly second: the order the dropdown lists them in.
        return Snapshot(
            rows: [row("five_hour", .fiveHour), row("seven_day", .weekly)].compactMap { $0 },
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    public static func read(configDir: URL) -> Snapshot? {
        let file = configDir.appendingPathComponent("usage-snapshot.json")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return parse(data)
    }
}
