import Foundation
import UsageCore

/// The bar keying on the row the *provider* calls primary, and a window model
/// that can carry a duration it has no name for. See
/// `.plan/codex-provider/tickets/01-primary-window-rule.md`.
///
/// Asserted at the display seam, the same one `DisplayTests` uses — whose ~130
/// assertions pass untouched, which is the proof that this costs Claude nothing.
/// No Codex adapter exists yet, so these build snapshots directly and declare
/// the primary the way that adapter will: the display rule reads `primary`, and
/// has no opinion about which provider set it.
func runPrimaryWindowTests(_ t: Harness) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // Fri 2027-01-15, 08:00 UTC
    let settings = AppSettings()  // warn 75 → critical 87.5

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")

    func row(_ window: UsageWindow, _ used: Double, resetsIn: TimeInterval = 86_400) -> UsageRow {
        UsageRow(window: window, used: used, limit: 100, resetsAt: now.addingTimeInterval(resetsIn))
    }
    func view(_ rows: [UsageRow], primary: UsageWindow, template: String? = nil) -> ViewModel {
        var settings = settings
        if let template { settings.menuBarTemplate = template }
        return render(
            accounts: [AccountState(
                account: Account(label: "a", configDir: URL(fileURLWithPath: "/fixtures/a")),
                snapshot: Snapshot(rows: rows, updatedAt: now, primary: primary),
                tapStatus: .installed
            )],
            settings: settings, now: now, calendar: calendar
        )
    }

    // MARK: - The bar reads the declared primary, whatever window that is

    // The whole point: a Codex account reports one window, the weekly, and under
    // the old hardcoded 5-hour rule would have rendered as the no-data template
    // forever. It now renders its figure.
    t.checkEqual(
        view([row(.weekly, 62)], primary: .weekly).menuBar[2],
        StyledText("a 62%", .normal),
        "primary: a weekly-only snapshot whose provider calls weekly primary is the bar's figure"
    )
    t.checkEqual(
        view([row(.fiveHour, 24)], primary: .fiveHour).menuBar[2],
        StyledText("a 24%", .normal),
        "primary: a 5-hour-only snapshot still renders, exactly as before"
    )

    // Declared, not inferred from what happened to arrive. A Claude account that
    // reported only its weekly window is still missing the window that binds it,
    // and promoting the other row would show a number under a meaning it does
    // not have. (`DisplayTests` pins the same case from the outside.)
    t.checkEqual(
        view([row(.weekly, 62)], primary: .fiveHour).menuBar[2],
        StyledText("a —", .dimmed),
        "primary: a missing primary row is no data — never the next row along"
    )

    // Decision 3's payoff: if OpenAI restores a 5-hour window it lands in the
    // wire's `primary`, and the bar follows with no code change.
    t.checkEqual(
        view([row(.fiveHour, 30), row(.weekly, 62)], primary: .fiveHour,
             template: "{name} {pct}/{pct_7d}").menuBar[2],
        StyledText("a 30%/62%", .normal),
        "primary: a restored 5-hour window takes the bar, and the weekly becomes {pct_7d}"
    )

    // MARK: - {pct_7d} is "the other window", and "—" when there isn't one

    t.checkEqual(
        view([row(.fiveHour, 24)], primary: .fiveHour, template: "{name} {pct}/{pct_7d}")
            .menuBar[2].text,
        "a 24%/—",
        "{pct_7d}: one window and no second one renders a dash"
    )
    t.checkEqual(
        view([row(.weekly, 62)], primary: .weekly, template: "{name} {pct}/{pct_7d}")
            .menuBar[2].text,
        "a 62%/—",
        "{pct_7d}: the primary is never repeated as the secondary figure"
    )
    t.checkEqual(
        view([row(.weekly, 62), row(.other(minutes: 1440), 8)], primary: .weekly,
             template: "{name} {pct}/{pct_7d}").menuBar[2].text,
        "a 62%/8%",
        "{pct_7d}: the second figure is the next reported row, whatever window it is"
    )

    // MARK: - A window with no name of its own

    t.checkEqual(UsageWindow.other(minutes: 1440).defaultLabel, "24h", "label: a day reads as 24h")
    t.checkEqual(UsageWindow.other(minutes: 43_200).defaultLabel, "30d", "label: a month reads as 30d")
    t.checkEqual(UsageWindow.other(minutes: 2_880).defaultLabel, "2d", "label: whole days beyond one")
    t.checkEqual(UsageWindow.other(minutes: 720).defaultLabel, "12h", "label: whole hours")
    t.checkEqual(UsageWindow.other(minutes: 90).defaultLabel, "90m", "label: no whole unit fits")

    do {
        let vm = view([row(.weekly, 62), row(.other(minutes: 1440), 8, resetsIn: 9_000)],
                      primary: .weekly)
        t.checkEqual(vm.accounts[0].windows.count, 2, "other: an unnamed window is a row, not a drop")
        t.checkEqual(
            vm.accounts[0].windows[1].text, "24h  ▓░░░░░░░░░    8%  ·  reset 10:30am",
            "other: it renders through the same template, labelled from its duration"
        )
    }

    // Nothing stops an unnamed window from being the one that binds, either.
    t.checkEqual(
        view([row(.other(minutes: 1440), 91)], primary: .other(minutes: 1440)).menuBar[2],
        StyledText("a 91%", .critical),
        "other: an unnamed window can be the primary, with tone decided the same way"
    )

    // MARK: - The cache, before and after

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    // A file written by the build that shipped the Kimi cache: `window` as a bare
    // raw value, and no `primary` key at all, because the bar was hardcoded then.
    // Same back-compat discipline as the v0.1.4 fixture in `ConfigTests` — every
    // key that build wrote, verbatim.
    let legacy = """
    {
      "/fixtures/kimi" : {
        "rows" : [
          {
            "label" : "5h",
            "limit" : 100,
            "resets_at" : 1800086400,
            "used" : 12,
            "window" : "five_hour"
          },
          {
            "label" : "7d",
            "limit" : 100,
            "resets_at" : 1800604800,
            "used" : 51,
            "window" : "weekly"
          }
        ],
        "updated_at" : 1800000000
      }
    }
    """
    let legacyURL = root.appendingPathComponent("legacy-cache.json")
    try? Data(legacy.utf8).write(to: legacyURL)

    let restored = KimiSnapshotCache.snapshot(
        configDir: URL(fileURLWithPath: "/fixtures/kimi"),
        in: KimiSnapshotCache.load(from: legacyURL)
    )
    t.checkEqual(
        restored,
        Snapshot(
            rows: [
                UsageRow(window: .fiveHour, used: 12, limit: 100,
                         resetsAt: Date(timeIntervalSince1970: 1_800_086_400)),
                UsageRow(window: .weekly, used: 51, limit: 100,
                         resetsAt: Date(timeIntervalSince1970: 1_800_604_800)),
            ],
            updatedAt: now
        ),
        "cache: a file written before this change still loads, every row intact"
    )
    t.checkEqual(
        restored?.primary, .fiveHour,
        "cache: …and an absent `primary` reads as 5-hour, which is what that file meant"
    )

    // And the new shapes survive a round trip of their own.
    let codexShaped = Snapshot(
        rows: [row(.weekly, 62), row(.other(minutes: 1_440), 8)],
        updatedAt: now,
        primary: .weekly
    )
    let cacheURL = root.appendingPathComponent("cache.json")
    let configDir = URL(fileURLWithPath: "/fixtures/codex")
    try? KimiSnapshotCache.store(codexShaped, configDir: configDir, at: cacheURL)
    t.checkEqual(
        KimiSnapshotCache.snapshot(
            configDir: configDir, in: KimiSnapshotCache.load(from: cacheURL)
        ),
        codexShaped,
        "cache: a declared primary and an unnamed window both round-trip"
    )

    // A window this build cannot name is not guessed at. The cache treats the
    // failure as it treats any unreadable file: no figure, not a wrong one.
    try? Data(legacy.replacingOccurrences(of: "\"five_hour\"", with: "\"fortnightly\"").utf8)
        .write(to: legacyURL)
    t.checkEqual(
        KimiSnapshotCache.load(from: legacyURL), [:],
        "cache: an unrecognisable window fails the decode rather than becoming a default"
    )
}
