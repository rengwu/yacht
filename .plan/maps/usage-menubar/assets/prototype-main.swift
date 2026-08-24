import Cocoa

// MARK: - Model

struct LimitWindow {
    let reportedPercentage: Double
    let resetsAt: Date

    /// Past the reset boundary the window is empty again, even though the snapshot
    /// still holds the pre-reset number from whenever a session last reported.
    var hasReset: Bool { Date() >= resetsAt }

    var percentage: Double { hasReset ? 0 : reportedPercentage }
}

struct Snapshot {
    let fiveHour: LimitWindow?
    let sevenDay: LimitWindow?
    let updatedAt: Date

    var isEmpty: Bool { fiveHour == nil && sevenDay == nil }
}

enum SnapshotReader {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".claude/usage-snapshot.json")

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let limits = root["rate_limits"] as? [String: Any] ?? [:]

        func window(_ key: String) -> LimitWindow? {
            guard let raw = limits[key] as? [String: Any],
                  let used = raw["used_percentage"] as? Double,
                  let resets = raw["resets_at"] as? Double
            else { return nil }
            return LimitWindow(
                reportedPercentage: used,
                resetsAt: Date(timeIntervalSince1970: resets)
            )
        }

        return Snapshot(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            updatedAt: Date(timeIntervalSince1970: root["updated_at"] as? Double ?? 0)
        )
    }
}

// MARK: - Formatting

enum Format {
    static func bar(_ percentage: Double, width: Int = 10) -> String {
        let filled = min(width, max(0, Int((percentage / 100 * Double(width)).rounded())))
        return String(repeating: "▓", count: filled)
            + String(repeating: "░", count: width - filled)
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func countdown(to date: Date) -> String {
        let total = Int(date.timeIntervalSinceNow)
        guard total > 0 else { return "now" }
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    static func ago(_ date: Date) -> String {
        let total = Int(Date().timeIntervalSince(date))
        guard total >= 60 else { return "just now" }
        let minutes = total / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return "\(days)d ago" }
        if hours > 0 { return "\(hours)h ago" }
        return "\(minutes)m ago"
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    private let monospaced = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    func applicationDidFinishLaunching(_ notification: Notification) {
        refresh()
        // The snapshot only changes while Claude Code runs, but the countdowns and
        // the "updated Nm ago" line are relative to now, so redraw on a timer anyway.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let snapshot = SnapshotReader.read()
        updateTitle(snapshot)
        updateMenu(snapshot)
    }

    // MARK: Title

    private func updateTitle(_ snapshot: Snapshot?) {
        guard let button = statusItem.button else { return }

        guard let snapshot, !snapshot.isEmpty else {
            button.attributedTitle = styled("◐ —", color: .secondaryLabelColor)
            return
        }

        var parts: [String] = []
        if let five = snapshot.fiveHour { parts.append(Format.percent(five.percentage)) }
        if let seven = snapshot.sevenDay { parts.append(Format.percent(seven.percentage)) }

        let peak = max(snapshot.fiveHour?.percentage ?? 0, snapshot.sevenDay?.percentage ?? 0)
        let color: NSColor = peak >= 90 ? .systemRed : peak >= 75 ? .systemOrange : .labelColor

        button.attributedTitle = styled("◐ " + parts.joined(separator: " · "), color: color)
    }

    private func styled(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: color,
        ])
    }

    // MARK: Menu

    private func updateMenu(_ snapshot: Snapshot?) {
        let menu = NSMenu()

        guard let snapshot, !snapshot.isEmpty else {
            menu.addItem(label("No usage data yet"))
            menu.addItem(label("Run a Claude Code session to populate it.", secondary: true))
            addFooter(to: menu)
            statusItem.menu = menu
            return
        }

        if let five = snapshot.fiveHour {
            addWindow(to: menu, name: "5-hour", window: five)
        }
        if let seven = snapshot.sevenDay {
            addWindow(to: menu, name: "7-day", window: seven)
        }

        menu.addItem(.separator())
        menu.addItem(label("Updated \(Format.ago(snapshot.updatedAt))", secondary: true))
        addFooter(to: menu)

        statusItem.menu = menu
    }

    private func addWindow(to menu: NSMenu, name: String, window: LimitWindow) {
        let padded = name.padding(toLength: 8, withPad: " ", startingAt: 0)
        let row = "\(padded) \(Format.bar(window.percentage))  \(Format.percent(window.percentage))"
        menu.addItem(label(row, monospace: true))

        let detail = window.hasReset
            ? "window reset — open Claude Code to refresh"
            : "resets in \(Format.countdown(to: window.resetsAt))"
        menu.addItem(label("    " + detail, secondary: true))
    }

    private func addFooter(to menu: NSMenu) {
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)
    }

    private func label(_ text: String, secondary: Bool = false, monospace: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: monospace ? monospaced : NSFont.systemFont(ofSize: 12),
            .foregroundColor: secondary ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ])
        return item
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
