import Foundation

/// An account is a (label, config directory) pair, and the config directory is
/// its identity: it holds the auth session that defines the subscription, and
/// that account's snapshot lives inside it. The shell alias that selects the
/// account is incidental and unknown to this app.
public struct Account: Equatable {
    public let label: String
    public let configDir: URL

    public init(label: String, configDir: URL) {
        self.label = label
        self.configDir = configDir
    }
}

/// One rate-limit window: the used percentage as reported (may be fractional)
/// and the moment it resets. Whether the window is *effectively* empty is a
/// question about "now", answered at render time — never stored.
public struct LimitWindow: Equatable {
    public let usedPercentage: Double
    public let resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

/// The rate-limit block plus the time it was captured. Either window may be
/// independently absent; both are absent for accounts not on a subscription
/// plan or before a session's first API response.
public struct Snapshot: Equatable {
    public let fiveHour: LimitWindow?
    public let sevenDay: LimitWindow?
    public let updatedAt: Date

    public init(fiveHour: LimitWindow?, sevenDay: LimitWindow?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }
}

/// App settings. The user sets exactly one threshold; critical is derived — the
/// midpoint between warn and 100 — so the pair can never be mis-ordered.
public struct AppSettings: Equatable {
    /// At or above this percentage a figure renders as `.warn`.
    public var warnThreshold: Double

    /// The dropdown's window row, as a template over these tokens:
    ///
    ///     {name}      5h | 7d
    ///     {bar}       ▓▓▓▓▓▓░░░░
    ///     {pct}       100% (right-aligned to 4, so the columns line up)
    ///     {reset_at}  8:00pm — with a weekday when it is not today
    ///     {reset_in}  1h 24m
    ///
    /// Anything else in the string is literal, unrecognised braces included: a
    /// typo'd token shows up as itself rather than as an error or an empty gap.
    public var rowTemplate: String

    public static let defaultRowTemplate = "{name}  {bar}  {pct}  ·  reset {reset_at}"

    /// Whether the status item shows the "◐" glyph. Not absolute: `render` shows
    /// it anyway when there would otherwise be nothing to click — see `menuBar`.
    public var showMenuBarIcon: Bool

    /// One account's segment of the status item, as a template over the same
    /// tokens as `rowTemplate` (`{bar}`/`{reset_at}`/`{reset_in}` all work, though
    /// the bar is an odd fit for one inline line). `{pct}` is not column-padded
    /// here — that alignment exists for a vertical list, and this isn't one.
    public var menuBarTemplate: String

    public static let defaultMenuBarTemplate = "{name} {pct}"

    /// An account with no snapshot yet has no bar, percentage, or reset to show,
    /// so it gets its own template — one where only `{name}` is meaningful.
    public var menuBarNoDataTemplate: String

    public static let defaultMenuBarNoDataTemplate = "{name} —"

    /// Between account segments in the status item.
    public var menuBarSeparator: String

    public static let defaultMenuBarSeparator = " · "

    /// Caps how many registered accounts appear in the status item; `0` means no
    /// cap. The dropdown is unaffected — every account still has a section there.
    public var menuBarMaxAccounts: Int

    /// At or above this a figure renders as `.critical`. Derived, not settable.
    public var criticalThreshold: Double { warnThreshold + (100 - warnThreshold) / 2 }

    public init(
        warnThreshold: Double = 75,
        rowTemplate: String = AppSettings.defaultRowTemplate,
        showMenuBarIcon: Bool = true,
        menuBarTemplate: String = AppSettings.defaultMenuBarTemplate,
        menuBarNoDataTemplate: String = AppSettings.defaultMenuBarNoDataTemplate,
        menuBarSeparator: String = AppSettings.defaultMenuBarSeparator,
        menuBarMaxAccounts: Int = 0
    ) {
        self.warnThreshold = warnThreshold
        self.rowTemplate = rowTemplate
        self.showMenuBarIcon = showMenuBarIcon
        self.menuBarTemplate = menuBarTemplate
        self.menuBarNoDataTemplate = menuBarNoDataTemplate
        self.menuBarSeparator = menuBarSeparator
        self.menuBarMaxAccounts = menuBarMaxAccounts
    }
}

/// Everything the composition root gathered about one account — the input to
/// the pure render function. `snapshot == nil` means never reported (or an
/// unreadable snapshot, which the user is shown the same way: as no data).
public struct AccountState: Equatable {
    public let account: Account
    public let snapshot: Snapshot?
    public let tapStatus: TapStatus

    public init(account: Account, snapshot: Snapshot?, tapStatus: TapStatus) {
        self.account = account
        self.snapshot = snapshot
        self.tapStatus = tapStatus
    }

    /// Impure gatherer for the composition root: reads the snapshot and detects
    /// the tap in one pass over the account's config directory.
    public static func gather(account: Account, tapCommand: String) -> AccountState {
        AccountState(
            account: account,
            snapshot: SnapshotReader.read(configDir: account.configDir),
            tapStatus: TapInstaller.detect(configDir: account.configDir, tapCommand: tapCommand)
        )
    }
}
