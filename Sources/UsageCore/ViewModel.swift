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

/// One fully-composed row, e.g. `5h  ▓▓░░░░░░░░   24%  ·  reset 10:30am`. The
/// template decided its shape; the UI only paints it in the tone.
public struct WindowView: Equatable {
    public let text: String
    public let tone: Tone

    public init(text: String, tone: Tone) {
        self.text = text
        self.tone = tone
    }
}

public struct AccountView: Equatable {
    public let label: String
    public let windows: [WindowView]  // 0–2, in 5-hour / 7-day order
    public let note: String?          // why data is absent/frozen, when it is

    public init(label: String, windows: [WindowView], note: String?) {
        self.label = label
        self.windows = windows
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

/// The calendar carries the time zone and locale a wall-clock reset time is read
/// in — injected for the same reason `now` is, so the seam stays pure.
public func render(
    accounts: [AccountState], settings: AppSettings, now: Date, calendar: Calendar = .current
) -> ViewModel {
    var segments = [StyledText("◐", .normal)]
    for (i, state) in accounts.enumerated() {
        segments.append(StyledText(i == 0 ? " " : " · ", .dimmed))
        segments.append(menuBarSegment(state, settings: settings, now: now))
    }
    return ViewModel(
        menuBar: segments,
        accounts: accounts.map {
            accountView($0, settings: settings, now: now, calendar: calendar)
        },
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

/// No "updated Nm ago" line, deliberately. A figure that renders at all belongs
/// to the window that is live *now* — `resets_at` travels inside the snapshot, so
/// anything past its own reset renders empty below — and usage only accrues while
/// a session runs, which is exactly when the tap rewrites the snapshot. An age
/// therefore casts doubt on a number that is still exactly true, and the one case
/// where it *is* a lower bound (the account spent tokens somewhere the tap cannot
/// see — the web app, another machine, a broken tap) is invisible to a clock. What
/// can be known about the pipeline is stated instead, as a note.
private func accountView(
    _ state: AccountState, settings: AppSettings, now: Date, calendar: Calendar
) -> AccountView {
    guard let snapshot = state.snapshot else {
        return AccountView(
            label: state.account.label, windows: [], note: absenceNote(state.tapStatus)
        )
    }
    var windows: [WindowView] = []
    if let five = snapshot.fiveHour {
        windows.append(windowView("5h", five, settings: settings, now: now, calendar: calendar))
    }
    if let seven = snapshot.sevenDay {
        windows.append(windowView("7d", seven, settings: settings, now: now, calendar: calendar))
    }
    return AccountView(
        label: state.account.label,
        windows: windows,
        note: state.tapStatus == .installed ? nil : absenceNote(state.tapStatus)
    )
}

private func windowView(
    _ name: String, _ window: LimitWindow, settings: AppSettings, now: Date, calendar: Calendar
) -> WindowView {
    // Past the reset there is no reset time to render and no session has confirmed
    // the window is empty, so this row states the inference instead of obeying the
    // template: the template describes a live window, and this wording is a claim
    // about what is known, not a preference.
    guard now < window.resetsAt else {
        return WindowView(
            text: "\(name)  \(Format.bar(0))  \(Format.column(Format.percent(0)))"
                + "  ·  reset passed — empty until a session confirms",
            tone: .normal
        )
    }
    let p = window.usedPercentage
    return WindowView(
        text: Format.row(
            settings.rowTemplate, name: name, percentage: p,
            resetsAt: window.resetsAt, now: now, calendar: calendar
        ),
        tone: tone(p, settings)
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
    /// Substitutes the known tokens and leaves everything else — including any
    /// token it does not know — standing as literal text.
    static func row(
        _ template: String, name: String, percentage: Double,
        resetsAt: Date, now: Date, calendar: Calendar
    ) -> String {
        var out = template
        for (token, value) in [
            ("{name}", name),
            ("{bar}", bar(percentage)),
            ("{pct}", column(percent(percentage))),
            ("{reset_at}", clock(resetsAt, now: now, calendar: calendar)),
            ("{reset_in}", countdown(from: now, to: resetsAt)),
        ] {
            out = out.replacingOccurrences(of: token, with: value)
        }
        return out
    }

    /// Right-aligned in a 4-wide column ("100%", " 62%", "  0%") so that in the
    /// menu's monospaced rows the percentages form a column instead of drifting
    /// with the width of the number.
    static func column(_ text: String, width: Int = 4) -> String {
        String(repeating: " ", count: max(0, width - text.count)) + text
    }

    /// The reset as a wall clock — "8:00pm", or "Sat 1:00pm" when it is not today,
    /// because a bare time on a 7-day window would name a moment days away as if
    /// it were this evening. 12- or 24-hour per the locale; the space macOS puts
    /// before AM/PM is squeezed out to keep the row narrow.
    static func clock(_ date: Date, now: Date, calendar: Calendar) -> String {
        func formatter(_ template: String) -> DateFormatter {
            let f = DateFormatter()
            f.calendar = calendar
            f.locale = calendar.locale ?? .current
            f.timeZone = calendar.timeZone
            f.setLocalizedDateFormatFromTemplate(template)
            return f
        }
        let time = formatter("jmm").string(from: date)
            .filter { !$0.isWhitespace }  // also catches the narrow no-break space
            .lowercased()
        guard !calendar.isDate(date, inSameDayAs: now) else { return time }
        return "\(formatter("E").string(from: date)) \(time)"
    }

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
}
