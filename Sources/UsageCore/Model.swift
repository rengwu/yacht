import Foundation

/// A source Yacht knows how to register. Provider selection is explicit: the
/// presence of either provider's files on disk never creates an account.
public enum Provider: String, CaseIterable, Codable {
    case claude
    case kimi

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .kimi: return "Kimi"
        }
    }

    /// The noun the folder picker uses. `KIMI_CODE_HOME` is a home directory,
    /// while Claude calls the same account boundary its config directory.
    public var configDirectoryLabel: String {
        switch self {
        case .claude: return "Claude config folder"
        case .kimi: return "Kimi Code home folder"
        }
    }

    /// Tap installation belongs only to Claude's push adapter. Keeping that
    /// fact here lets Settings project the provider instead of rediscovering
    /// provider behaviour in AppKit.
    public var usesTap: Bool { self == .claude }
}

/// An account is a (provider, label, config directory) tuple, and the config
/// directory is its identity: it holds the auth session that defines the
/// subscription, and that account's snapshot lives inside it. The shell alias
/// that selects the account is incidental and unknown to this app.
public struct Account: Equatable {
    public let provider: Provider
    public let label: String
    public let configDir: URL

    public init(provider: Provider = .claude, label: String, configDir: URL) {
        self.provider = provider
        self.label = label
        self.configDir = configDir
    }
}

/// Which quota period a row measures — a row's *identity*, and the one thing
/// about it the display rule is allowed to key on. Neither provider sends a
/// label: Claude names its windows with the JSON keys `five_hour`/`seven_day`,
/// Kimi identifies one by `window: {duration: 300, timeUnit: TIME_UNIT_MINUTE}`
/// and the other by being the top-level `usage` object with no window at all.
/// Each adapter therefore maps its own shape onto these cases, and the label is
/// derived from there — never read off the wire.
///
/// The raw value exists only so a cached snapshot can name its rows on disk; it
/// is never read off either provider's wire, and it is never the display label.
public enum UsageWindow: String, Equatable, Codable {
    case fiveHour = "five_hour"
    case weekly

    /// The dropdown's `{name}`, shared so providers agree by default.
    public var defaultLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        }
    }
}

/// One usage window as **absolute counts** — `used` of `limit` — plus the moment
/// it resets. Counts rather than a percentage because Kimi reports counts and
/// Claude reports percentages, and `{used, limit}` holds both without a
/// per-provider special case: a percentage-only source is simply a count out of
/// 100 (see `SnapshotReader`). The percentage is derived, at render time, where
/// the "past its own reset" rule already lives — whether a window is
/// *effectively* empty is a question about "now" and is never stored.
public struct UsageRow: Equatable {
    /// Identity: what the display rule keys on.
    public let window: UsageWindow
    /// Display only: what `{name}` renders as. Defaults to the window's shared
    /// label; an adapter overrides it when its own window genuinely reads
    /// differently, never to re-identify the row.
    public let label: String
    public let used: Double
    public let limit: Double
    public let resetsAt: Date

    public init(window: UsageWindow, label: String? = nil, used: Double, limit: Double, resetsAt: Date) {
        self.window = window
        self.label = label ?? window.defaultLabel
        self.used = used
        self.limit = limit
        self.resetsAt = resetsAt
    }

    /// `used` as a share of `limit`, unclamped: the display rounds an overshoot
    /// off (see `Format.percent`) but the tone is decided on the true figure.
    /// A non-positive `limit` cannot express a share of anything, so it reads as
    /// 0 rather than dividing by zero — a NaN would reach `Int(_:)` in the
    /// formatter and trap. No adapter can produce one; this is a floor, not a
    /// state the UI is meant to distinguish.
    public var percentage: Double {
        limit > 0 ? used / limit * 100 : 0
    }
}

/// One provider's usage for one account: N rows plus the time they were
/// captured. Both of Claude's windows are independently absent for an account
/// not on a subscription plan, or before a session's first API response, so
/// `rows` may be empty — which the UI shows as no data, never as 0%.
///
/// `rows` is in the adapter's own significance order (5-hour, then weekly), and
/// that is the order the dropdown lists them in. It is *not* how the menu bar
/// picks its figure: that rule keys on `UsageWindow`, so a snapshot carrying
/// only a weekly row still reads as "no 5-hour data" rather than promoting it.
public struct Snapshot: Equatable {
    public let rows: [UsageRow]
    public let updatedAt: Date

    public init(rows: [UsageRow], updatedAt: Date) {
        self.rows = rows
        self.updatedAt = updatedAt
    }

    /// The row for one window, or `nil` when this provider did not report it.
    public func row(_ window: UsageWindow) -> UsageRow? {
        rows.first { $0.window == window }
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

    /// Whether the status item shows `menuBarIcon`. Not absolute: `render` shows
    /// it anyway when there would otherwise be nothing to click — see `menuBar`.
    public var showMenuBarIcon: Bool

    /// The glyph itself — any single character, emoji included: the status item
    /// is rendered as attributed text, never an `NSImage`, so nothing forces it
    /// to a monochrome "template" icon the way a real image asset would.
    public var menuBarIcon: String

    public static let defaultMenuBarIcon = "⛵️"

    /// One account's segment of the status item, as a template over the same
    /// tokens as `rowTemplate` (`{bar}`/`{reset_at}`/`{reset_in}` all work, though
    /// the bar is an odd fit for one inline line). `{pct}` is not column-padded
    /// here — that alignment exists for a vertical list, and this isn't one.
    /// `{pct_7d}` adds the 7-day window's percentage alongside the 5-hour one —
    /// "—" if that window has no data of its own.
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
        menuBarIcon: String = AppSettings.defaultMenuBarIcon,
        menuBarTemplate: String = AppSettings.defaultMenuBarTemplate,
        menuBarNoDataTemplate: String = AppSettings.defaultMenuBarNoDataTemplate,
        menuBarSeparator: String = AppSettings.defaultMenuBarSeparator,
        menuBarMaxAccounts: Int = 0
    ) {
        self.warnThreshold = warnThreshold
        self.rowTemplate = rowTemplate
        self.showMenuBarIcon = showMenuBarIcon
        self.menuBarIcon = menuBarIcon
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
    public let sourceState: AccountSourceState

    public init(account: Account, snapshot: Snapshot?, tapStatus: TapStatus) {
        self.account = account
        self.snapshot = snapshot
        self.sourceState = .claude(tapStatus)
    }

    /// The Kimi adapter owns both the snapshot and its standing, so a stale
    /// figure can never reach the display without the mark that says so — the
    /// two travel together or not at all.
    public init(account: Account, kimi state: KimiProviderState) {
        self.account = account
        switch state {
        case .snapshot(let snapshot):
            self.snapshot = snapshot
            self.sourceState = .kimi(.available)
        case .stale(let snapshot, let reason):
            self.snapshot = snapshot
            self.sourceState = .kimi(.stale(reason))
        case .tokenExpired:
            self.snapshot = nil
            self.sourceState = .kimi(.tokenExpired)
        case .unreachable:
            self.snapshot = nil
            self.sourceState = .kimi(.unreachable)
        }
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

/// Runtime state for an account's provider adapter. This is deliberately not
/// the persisted provider selection — account registration owns that concern.
/// It is only what the pure renderer needs to explain absent data.
public enum AccountSourceState: Equatable {
    case claude(TapStatus)
    case kimi(KimiAvailability)
}

/// `tokenExpired` and `unreachable` mean *no figure at all* — no poll has ever
/// succeeded for this account. Once one has, the same two conditions read as
/// `.stale` instead, carrying the reason so the note can distinguish "kimi
/// simply hasn't run" from "the last attempt failed".
public enum KimiAvailability: Equatable {
    case available
    case stale(KimiStaleReason)
    case tokenExpired
    case unreachable
}
