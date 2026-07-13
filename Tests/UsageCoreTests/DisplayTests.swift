import Foundation
import UsageCore

/// The display seam — the primary seam. Frozen clock, fixture states, and
/// assertions on the fully-described view model. No AppKit, no real clock,
/// no real home directory.
func runDisplayTests(_ t: Harness) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let settings = AppSettings()  // warn 75 → critical 87.5

    func account(_ label: String) -> Account {
        Account(label: label, configDir: URL(fileURLWithPath: "/fixtures/\(label)"))
    }
    func state(
        _ label: String,
        five: LimitWindow? = nil,
        seven: LimitWindow? = nil,
        updatedAgo: TimeInterval = 180,
        tap: TapStatus = .installed,
        noSnapshot: Bool = false
    ) -> AccountState {
        AccountState(
            account: account(label),
            snapshot: noSnapshot ? nil : Snapshot(
                fiveHour: five, sevenDay: seven,
                updatedAt: now.addingTimeInterval(-updatedAgo)
            ),
            tapStatus: tap
        )
    }
    func window(_ used: Double, resetsIn: TimeInterval) -> LimitWindow {
        LimitWindow(usedPercentage: used, resetsAt: now.addingTimeInterval(resetsIn))
    }

    // MARK: Zero accounts

    do {
        let vm = render(accounts: [], settings: settings, now: now)
        t.checkEqual(vm.menuBar, [StyledText("◐", .normal)], "zero accounts: bare glyph")
        t.checkEqual(vm.accounts, [], "zero accounts: empty dropdown")
        t.checkEqual(vm.emptyState, "No accounts registered — open Settings to add one",
                     "zero accounts: dropdown explains itself")
    }

    // MARK: Never reported — a dash, never 0%, and always explained

    do {
        let vm = render(accounts: [state("john", noSnapshot: true)], settings: settings, now: now)
        t.checkEqual(vm.menuBar[2], StyledText("john —", .dimmed), "no snapshot: dash, dimmed")
        t.checkEqual(vm.accounts[0].windows, [], "no snapshot: no windows")
        t.checkEqual(vm.accounts[0].freshness, "never reported", "no snapshot: freshness")
        t.checkEqual(
            vm.accounts[0].note, "waiting for a session — run Claude Code as this account",
            "no snapshot + tap installed: explains the wait"
        )
    }
    t.checkEqual(
        render(accounts: [state("john", tap: .notInstalled, noSnapshot: true)],
               settings: settings, now: now).accounts[0].note,
        "tap not installed — install it from Settings",
        "no snapshot + no tap: explains the fix"
    )
    t.checkEqual(
        render(accounts: [state("john", tap: .foreign(command: "/x.sh"), noSnapshot: true)],
               settings: settings, now: now).accounts[0].note,
        "another status line is configured — see Settings",
        "no snapshot + foreign line: explained"
    )

    // MARK: Healthy account, both windows

    do {
        let vm = render(
            accounts: [state("john",
                             five: window(23.5, resetsIn: 9_000),      // 2h 30m
                             seven: window(41.4, resetsIn: 104_400))], // 1d 5h
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2], StyledText("john 24%", .normal), "menu bar: 5-hour only, rounded")
        let w = vm.accounts[0].windows
        t.checkEqual(w.count, 2, "both windows in dropdown")
        t.checkEqual(w[0].name, "5-hour", "window order: 5-hour first")
        t.checkEqual(w[0].bar, "▓▓░░░░░░░░", "5-hour bar: 23.5% → 2 of 10")
        t.checkEqual(w[0].percentText, "24%", "5-hour percent rounds 23.5 up")
        t.checkEqual(w[0].detail, "resets in 2h 30m", "5-hour countdown")
        t.checkEqual(w[1].name, "7-day", "window order: 7-day second")
        t.checkEqual(w[1].percentText, "41%", "7-day percent rounds 41.4 down")
        t.checkEqual(w[1].bar, "▓▓▓▓░░░░░░", "7-day bar: 41.4% → 4 of 10")
        t.checkEqual(w[1].detail, "resets in 1d 5h", "7-day countdown crosses a day")
        t.checkEqual(vm.accounts[0].freshness, "updated 3m ago", "freshness in minutes")
        t.checkEqual(vm.accounts[0].note, nil, "healthy + tap installed: no note")
    }

    // MARK: Overshoot — the server reports past 100; the display does not

    do {
        let vm = render(
            accounts: [state("sam", five: window(121, resetsIn: 5_100),   // 1h 25m
                             seven: window(62, resetsIn: 158_400))],
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2], StyledText("sam 100%", .critical), "menu bar: overshoot clamps to 100%")
        let w = vm.accounts[0].windows
        t.checkEqual(w[0].percentText, "100%", "dropdown: 121% displays as 100%")
        t.checkEqual(w[0].bar, "▓▓▓▓▓▓▓▓▓▓", "overshoot bar stays full, never wider")
        t.checkEqual(w[0].tone, .critical, "overshoot is still critical")
        t.checkEqual(w[1].percentText, "62%", "the other window is untouched")
    }

    // MARK: Snapshot present but tap gone: data would be frozen — still noted

    t.checkEqual(
        render(accounts: [state("john", five: window(10, resetsIn: 60), tap: .notInstalled)],
               settings: settings, now: now).accounts[0].note,
        "tap not installed — install it from Settings",
        "snapshot present but no tap: frozen data explained"
    )

    // MARK: The reset boundary — before, exactly at, after

    do {
        let before = render(accounts: [state("john", five: window(80, resetsIn: 1))],
                            settings: settings, now: now)
        t.checkEqual(before.menuBar[2], StyledText("john 80%", .warn), "1s before reset: live number")

        let at = render(accounts: [state("john", five: window(80, resetsIn: 0))],
                        settings: settings, now: now)
        t.checkEqual(at.menuBar[2], StyledText("john 0%", .normal), "exactly at reset: empty, tone reset")
        t.checkEqual(at.accounts[0].windows[0].detail,
                     "reset passed — empty until a session confirms",
                     "at reset: inference stated plainly")

        let after = render(accounts: [state("john", five: window(80, resetsIn: -3_600))],
                           settings: settings, now: now)
        t.checkEqual(after.accounts[0].windows[0].percentText, "0%", "after reset: empty")
        t.checkEqual(after.accounts[0].windows[0].bar, "░░░░░░░░░░", "after reset: bar empty")
        t.checkEqual(after.accounts[0].windows[0].tone, .normal, "after reset: no stale alarm")
    }

    // MARK: Dash and zero are different states

    do {
        let vm = render(
            accounts: [state("john", noSnapshot: true),
                       state("jane", five: window(0, resetsIn: 600))],
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2].text, "john —", "unknown renders as dash")
        t.checkEqual(vm.menuBar[4].text, "jane 0%", "genuinely empty renders as zero")
    }

    // MARK: Thresholds — exactly on each boundary, per account, independently

    do {
        func tone5(_ used: Double) -> Tone {
            render(accounts: [state("a", five: window(used, resetsIn: 600))],
                   settings: settings, now: now).accounts[0].windows[0].tone
        }
        t.checkEqual(tone5(74.9), .normal, "just below warn: normal")
        t.checkEqual(tone5(75), .warn, "exactly at warn: warn")
        t.checkEqual(tone5(87.4), .warn, "just below critical: warn")
        t.checkEqual(tone5(87.5), .critical, "exactly at derived critical: critical")

        let vm = render(
            accounts: [state("hot", five: window(90, resetsIn: 600)),
                       state("cool", five: window(10, resetsIn: 600))],
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2].tone, .critical, "hot account critical…")
        t.checkEqual(vm.menuBar[4].tone, .normal, "…does not alarm the cool one")

        let strict = AppSettings(warnThreshold: 50)  // critical derives to 75
        t.checkEqual(
            render(accounts: [state("a", five: window(75, resetsIn: 600))],
                   settings: strict, now: now).accounts[0].windows[0].tone,
            .critical, "derived critical follows the user's warn threshold"
        )
    }

    // MARK: Bars and rounding at the extremes

    do {
        func bar(_ used: Double) -> String {
            render(accounts: [state("a", five: window(used, resetsIn: 600))],
                   settings: settings, now: now).accounts[0].windows[0].bar
        }
        t.checkEqual(bar(0), "░░░░░░░░░░", "0%: empty bar")
        t.checkEqual(bar(100), "▓▓▓▓▓▓▓▓▓▓", "100%: full bar")
        t.checkEqual(bar(4.9), "░░░░░░░░░░", "4.9%: rounds to no glyph")
        t.checkEqual(bar(5), "▓░░░░░░░░░", "5%: rounds to one glyph")
        t.checkEqual(bar(99.4), "▓▓▓▓▓▓▓▓▓▓", "99.4%: rounds to full")
    }

    // MARK: Countdown and staleness across unit boundaries

    do {
        func detail(_ resetsIn: TimeInterval) -> String {
            render(accounts: [state("a", five: window(10, resetsIn: resetsIn))],
                   settings: settings, now: now).accounts[0].windows[0].detail
        }
        t.checkEqual(detail(59), "resets in 1m", "sub-minute floors at 1m")
        t.checkEqual(detail(3_540), "resets in 59m", "minutes up to the hour")
        t.checkEqual(detail(3_600), "resets in 1h 0m", "exactly one hour")
        t.checkEqual(detail(86_400), "resets in 1d 0h", "exactly one day")

        func fresh(_ ago: TimeInterval) -> String {
            render(accounts: [state("a", five: window(10, resetsIn: 600), updatedAgo: ago)],
                   settings: settings, now: now).accounts[0].freshness
        }
        t.checkEqual(fresh(59), "updated just now", "under a minute: just now")
        t.checkEqual(fresh(60), "updated 1m ago", "exactly a minute")
        t.checkEqual(fresh(3_600), "updated 1h ago", "exactly an hour")
        t.checkEqual(fresh(172_800), "updated 2d ago", "days")
    }

    // MARK: Ordering and partial snapshots

    do {
        let vm = render(
            accounts: [state("jane", five: window(10, resetsIn: 600)),
                       state("john", seven: window(20, resetsIn: 600))],
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar.map(\.text), ["◐", " ", "jane 10%", " · ", "john —"],
                     "registration order preserved; 7-day never enters the bar")
        t.checkEqual(vm.accounts.map(\.label), ["jane", "john"], "dropdown order matches")
        t.checkEqual(vm.accounts[1].windows.map(\.name), ["7-day"],
                     "partial snapshot: only the present window renders")
    }

    // MARK: The snapshot reader (malformed input never becomes data)

    do {
        let real = """
        {"rate_limits": {"five_hour": {"used_percentage": 9, "resets_at": 1783924200},
                         "seven_day": {"used_percentage": 40.5, "resets_at": 1784098800}},
         "updated_at": 1783909816.39}
        """.data(using: .utf8)!
        let snap = SnapshotReader.parse(real)
        t.checkEqual(snap?.fiveHour?.usedPercentage, 9, "reader: integer percentage")
        t.checkEqual(snap?.sevenDay?.usedPercentage, 40.5, "reader: fractional percentage")
        t.checkEqual(snap?.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_783_924_200),
                     "reader: reset epoch")

        let partial = """
        {"rate_limits": {"five_hour": {"used_percentage": 1, "resets_at": 2}}, "updated_at": 3}
        """.data(using: .utf8)!
        t.checkEqual(SnapshotReader.parse(partial)?.sevenDay, nil, "reader: absent window is nil")

        t.checkEqual(SnapshotReader.parse("garbage {{{".data(using: .utf8)!), nil,
                     "reader: garbage is nil, never 0%")
        t.checkEqual(SnapshotReader.parse("[1,2]".data(using: .utf8)!), nil,
                     "reader: non-object is nil")
        t.checkEqual(SnapshotReader.parse("{\"rate_limits\": {}}".data(using: .utf8)!), nil,
                     "reader: missing capture time is nil — staleness must stay honest")
    }
}
