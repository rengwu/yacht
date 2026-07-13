import Foundation

// The pure display seam: render(accounts, settings, now) → a fully-described
// view model. Every string, tone, bar and countdown for both the menu bar and
// the dropdown is decided here; the UI renders it without a decision of its own.
// Time is injected — nothing in this file reads a clock.

/// Semantic colour. The UI maps tones to actual colours.
public enum Tone: Equatable {
    case normal, warn, critical, dimmed
}

public struct StyledText: Equatable {
    public let text: String
    public let tone: Tone

    public init(_ text: String, _ tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

public struct WindowView: Equatable {
    public let name: String         // "5-hour" | "7-day"
    public let bar: String          // e.g. "▓▓░░░░░░░░"
    public let percentText: String  // e.g. "24%"
    public let tone: Tone
    public let detail: String       // "resets in 2h 30m" | reset-passed wording

    public init(name: String, bar: String, percentText: String, tone: Tone, detail: String) {
        self.name = name
        self.bar = bar
        self.percentText = percentText
        self.tone = tone
        self.detail = detail
    }
}

public struct AccountView: Equatable {
    public let label: String
    public let windows: [WindowView]  // 0–2, in 5-hour / 7-day order
    public let freshness: String      // "updated 3m ago" | "never reported"
    public let note: String?          // why data is absent/frozen, when it is

    public init(label: String, windows: [WindowView], freshness: String, note: String?) {
        self.label = label
        self.windows = windows
        self.freshness = freshness
        self.note = note
    }
}

public struct ViewModel: Equatable {
    /// Concatenated by the status item. Separators are their own dimmed segments.
    public let menuBar: [StyledText]
    /// Dropdown sections, in registration order.
    public let accounts: [AccountView]
    /// What the dropdown says when there is nothing to show.
    public let emptyState: String?

    public init(menuBar: [StyledText], accounts: [AccountView], emptyState: String? = nil) {
        self.menuBar = menuBar
        self.accounts = accounts
        self.emptyState = emptyState
    }
}

// MARK: - Render

public func render(accounts: [AccountState], settings: AppSettings, now: Date) -> ViewModel {
    var segments = [StyledText("◐", .normal)]
    for (i, state) in accounts.enumerated() {
        segments.append(StyledText(i == 0 ? " " : " · ", .dimmed))
        segments.append(menuBarSegment(state, settings: settings, now: now))
    }
    return ViewModel(
        menuBar: segments,
        accounts: accounts.map { accountView($0, settings: settings, now: now) },
        emptyState: accounts.isEmpty
            ? "No accounts registered — open Settings to add one" : nil
    )
}

private func menuBarSegment(_ state: AccountState, settings: AppSettings, now: Date) -> StyledText {
    let label = state.account.label
    guard let five = state.snapshot?.fiveHour else {
        return StyledText("\(label) —", .dimmed)
    }
    let p = effectivePercentage(five, now: now)
    return StyledText("\(label) \(Format.percent(p))", tone(p, settings))
}

private func accountView(_ state: AccountState, settings: AppSettings, now: Date) -> AccountView {
    guard let snapshot = state.snapshot else {
        return AccountView(
            label: state.account.label,
            windows: [],
            freshness: "never reported",
            note: absenceNote(state.tapStatus)
        )
    }
    var windows: [WindowView] = []
    if let five = snapshot.fiveHour {
        windows.append(windowView("5-hour", five, settings: settings, now: now))
    }
    if let seven = snapshot.sevenDay {
        windows.append(windowView("7-day", seven, settings: settings, now: now))
    }
    return AccountView(
        label: state.account.label,
        windows: windows,
        freshness: "updated \(Format.ago(since: snapshot.updatedAt, now: now))",
        note: state.tapStatus == .installed ? nil : absenceNote(state.tapStatus)
    )
}

private func windowView(_ name: String, _ window: LimitWindow, settings: AppSettings, now: Date) -> WindowView {
    let p = effectivePercentage(window, now: now)
    let detail = now >= window.resetsAt
        // Correct by inference, not observation — say so plainly.
        ? "reset passed — empty until a session confirms"
        : "resets in \(Format.countdown(from: now, to: window.resetsAt))"
    return WindowView(
        name: name,
        bar: Format.bar(p),
        percentText: Format.percent(p),
        tone: tone(p, settings),
        detail: detail
    )
}

/// Past the reset boundary the window is empty again, whatever the frozen
/// snapshot still says.
private func effectivePercentage(_ window: LimitWindow, now: Date) -> Double {
    now >= window.resetsAt ? 0 : window.usedPercentage
}

private func tone(_ percentage: Double, _ settings: AppSettings) -> Tone {
    if percentage >= settings.criticalThreshold { return .critical }
    if percentage >= settings.warnThreshold { return .warn }
    return .normal
}

/// Why an account shows no (or frozen) data — a dash must never go unexplained.
private func absenceNote(_ status: TapStatus) -> String {
    switch status {
    case .installed:
        return "waiting for a session — run Claude Code as this account"
    case .notInstalled:
        return "tap not installed — install it from Settings"
    case .foreign:
        return "another status line is configured — see Settings"
    }
}

// MARK: - Formatting

enum Format {
    /// Clamped at 100 to match what Claude Code's own `/usage` shows. The server
    /// reports the raw overshoot — enforcement is at request admission, so a
    /// request let through at 95% can run long and land the window at 121% — but
    /// a figure above 100 reads as a rendering bug, and "maxed out" is the whole
    /// of what it means. The snapshot keeps the true number; only the display rounds it off.
    static func percent(_ value: Double) -> String {
        "\(Int(min(100, value).rounded()))%"
    }

    static func bar(_ percentage: Double, width: Int = 10) -> String {
        let filled = min(width, max(0, Int((percentage / 100 * Double(width)).rounded())))
        return String(repeating: "▓", count: filled)
            + String(repeating: "░", count: width - filled)
    }

    static func countdown(from now: Date, to date: Date) -> String {
        let total = Int(date.timeIntervalSince(now))
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    static func ago(since date: Date, now: Date) -> String {
        let total = Int(now.timeIntervalSince(date))
        guard total >= 60 else { return "just now" }
        let minutes = total / 60
        let hours = minutes / 60
        let days = hours / 24
        if days > 0 { return "\(days)d ago" }
        if hours > 0 { return "\(hours)h ago" }
        return "\(minutes)m ago"
    }
}
