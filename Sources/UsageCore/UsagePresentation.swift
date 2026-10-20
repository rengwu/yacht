import Foundation

public enum AccountDisplay: String, Codable, CaseIterable { case icons, labels }
public enum PercentageDisplay: String, Codable, CaseIterable { case remaining, used }
public enum ResetDisplay: String, Codable, CaseIterable { case countdown, exactTime }

public struct DisplayPreferences: Equatable, Codable {
    public var accounts: AccountDisplay
    public var percentages: PercentageDisplay
    public var resets: ResetDisplay

    public init(
        accounts: AccountDisplay = .labels,
        percentages: PercentageDisplay = .used,
        resets: ResetDisplay = .countdown
    ) {
        self.accounts = accounts
        self.percentages = percentages
        self.resets = resets
    }
}

/// Semantic values for native views. nil is an unknown figure, never zero.
public struct UsageWindowPresentation: Equatable {
    public let window: UsageWindow
    public let label: String
    public let percentage: Double?
    public let resetPassed: Bool
    public let reset: String
    public let tone: Tone

    public var value: String {
        percentage.map { Format.percent($0) } ?? "—"
    }
}

public struct UsageAccountPresentation: Equatable {
    public let account: Account
    public let windows: [UsageWindowPresentation]
    public let selectedWindow: UsageWindow
    public let staleAge: String?
    public let explanation: String?
    public let percentages: PercentageDisplay

    public var menuBarFigure: UsageWindowPresentation? {
        windows.first { $0.window == selectedWindow }
    }
}

/// Does not read files or the clock. The legacy template renderer remains available
/// for existing configurations; the native views consume these structured values.
public func presentUsage(
    accounts: [AccountState], config: AppConfig, now: Date, calendar: Calendar = .current
) -> [UsageAccountPresentation] {
    accounts.map { state in
        let stale = isStale(state.sourceState)
            || (state.account.provider == .claude && state.sourceState != .claude(.installed))
        let windows = (state.snapshot?.rows ?? []).map { row -> UsageWindowPresentation in
            let passed = now >= row.resetsAt
            let used = max(0, min(100, row.percentage))
            let percentage = config.display.percentages == .used ? used : 100 - used
            let liveTone = tone(row.percentage, config.settings)
            let color: Tone = passed ? .dimmed : (stale && liveTone == .normal ? .dimmed : liveTone)
            return UsageWindowPresentation(
                window: row.window,
                label: row.window == .weekly && row.label == "7d" ? "Weekly" : row.label,
                percentage: passed ? nil : percentage,
                resetPassed: passed,
                reset: passed ? "" : (config.display.resets == .countdown
                    ? Format.countdown(from: now, to: row.resetsAt)
                    : Format.clock(row.resetsAt, now: now, calendar: calendar)),
                tone: color
            )
        }
        let note = providerNote(
            state.sourceState, hasSnapshot: state.snapshot != nil, snapshot: state.snapshot, now: now
        )?.text
        return UsageAccountPresentation(
            account: state.account, windows: windows,
            selectedWindow: state.account.menuBarWindow
                ?? state.snapshot?.primary ?? state.account.provider.defaultPrimaryWindow,
            staleAge: stale ? state.snapshot.map { compactAge($0.updatedAt, now: now) } : nil,
            explanation: note, percentages: config.display.percentages
        )
    }
}

public extension Provider {
    var defaultPrimaryWindow: UsageWindow {
        switch self {
        case .claude, .kimi: return .fiveHour
        case .codex, .grok: return .weekly
        }
    }
}

private func compactAge(_ date: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
    if minutes >= 1440 { return "\(minutes / 1440)d" }
    if minutes >= 60 { return "\(minutes / 60)h" }
    return "\(minutes)m"
}
