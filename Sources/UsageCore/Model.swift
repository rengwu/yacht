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

/// Which quota period a row measures — a row's *identity*. No provider sends a
/// label: Claude names its windows with the JSON keys `five_hour`/`seven_day`,
/// Kimi identifies one by `window: {duration: 300, timeUnit: TIME_UNIT_MINUTE}`
/// and the other by being the top-level `usage` object with no window at all,
/// and Codex identifies both by a bare `windowDurationMins` number. Each adapter
/// therefore maps its own shape onto these cases, and the label is derived from
/// there — never read off the wire.
///
/// `other` exists because two named cases cannot be the whole world: Codex
/// reports a duration, and a plan that gains a 24-hour or 30-day quota must show
/// up as a row of its own rather than being silently dropped for having no name
/// here. It carries the duration precisely so the label can be derived from it.
///
/// Not `RawRepresentable`: an associated value has no raw value. The on-disk
/// spelling a cached snapshot needs lives with the cache, in
/// `KimiSnapshotCache`, where it is a storage format rather than a property of
/// the domain.
public enum UsageWindow: Equatable {
    case fiveHour
    case weekly
    case other(minutes: Int)

    /// The dropdown's `{name}`, shared so providers agree by default.
    ///
    /// An unnamed window is labelled by its own duration, in the largest unit
    /// that divides it evenly — except that a single day reads as `24h` rather
    /// than `1d`, because a lone `1d` next to `5h` and `7d` scans as a count of
    /// something rather than as a duration. So 1440 → `24h`, 43200 → `30d`.
    public var defaultLabel: String {
        switch self {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        case .other(let minutes):
            if minutes >= 2 * 1440 && minutes % 1440 == 0 { return "\(minutes / 1440)d" }
            if minutes >= 60 && minutes % 60 == 0 { return "\(minutes / 60)h" }
            return "\(minutes)m"
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
/// picks its figure: that rule keys on `primary`, so a snapshot that happens to
/// carry only a weekly row still reads as "no data" for a provider whose primary
/// is the 5-hour window, rather than promoting whatever arrived first.
public struct Snapshot: Equatable {
    public let rows: [UsageRow]
    public let updatedAt: Date

    /// Which window the menu bar's figure is, **declared by the adapter**. Claude
    /// and Kimi have no such field on the wire and declare 5-hour; Codex says so
    /// on the wire (its `primary`), so if a 5-hour window is ever restored to
    /// that plan the bar follows it with no code change. Defaulted, so a snapshot
    /// built without an opinion behaves exactly as every snapshot did before this
    /// existed — including one decoded from a cache file written back then.
    public let primary: UsageWindow

    public init(rows: [UsageRow], updatedAt: Date, primary: UsageWindow = .fiveHour) {
        self.rows = rows
        self.updatedAt = updatedAt
        self.primary = primary
    }

    /// The row for one window, or `nil` when this provider did not report it.
    public func row(_ window: UsageWindow) -> UsageRow? {
        rows.first { $0.window == window }
    }

    /// The bar's figure, or `nil` when the provider did not report its own
    /// primary window — which is no data, and never 0%.
    public var primaryRow: UsageRow? { row(primary) }

    /// The bar's `{pct_7d}`: the first reported row that is not the primary one,
    /// in the adapter's significance order. Derived rather than declared, because
    /// "the other one" is all this figure has ever meant — for Claude and Kimi it
    /// resolves to the weekly window exactly as the hardcoded rule did, and a
    /// provider reporting a single window has no second figure to show, so
    /// `{pct_7d}` renders "—" rather than repeating the primary.
    public var secondaryRow: UsageRow? { rows.first { $0.window != primary } }
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
