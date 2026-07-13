import Foundation
import UsageCore

/// The display seam — the primary seam. Frozen clock, fixture states, and
/// assertions on the fully-described view model. No AppKit, no real clock,
/// no real home directory.
func runDisplayTests(_ t: Harness) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // Fri 2027-01-15, 08:00 UTC
    let settings = AppSettings()  // warn 75 → critical 87.5

    // Pinned, so the wall-clock reset times below are the same on any machine.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")

    func render(
        accounts: [AccountState], settings: AppSettings = settings, now: Date = now
    ) -> ViewModel {
        UsageCore.render(accounts: accounts, settings: settings, now: now, calendar: calendar)
    }

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

    // MARK: Healthy account, both windows — one row each, under the default template

    do {
        let vm = render(
            accounts: [state("john",
                             five: window(23.5, resetsIn: 9_000),      // 10:30am, today
                             seven: window(41.4, resetsIn: 104_400))], // 1:00pm, tomorrow
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2], StyledText("john 24%", .normal), "menu bar: 5-hour only, rounded")
        let w = vm.accounts[0].windows
        t.checkEqual(w.count, 2, "both windows in dropdown")
        t.checkEqual(
            w[0].text, "5h  ▓▓░░░░░░░░   24%  ·  reset 10:30am",
            "5-hour row: name, bar, percent (rounded up, column-aligned), reset clock"
        )
        t.checkEqual(
            w[1].text, "7d  ▓▓▓▓░░░░░░   41%  ·  reset Sat 1:00pm",
            "7-day row: second, and a reset that is not today carries its weekday"
        )
        t.checkEqual(vm.accounts[0].note, nil, "healthy + tap installed: no note")
    }

    // MARK: Overshoot — the server reports past 100; the display does not

    do {
        let vm = render(
            accounts: [state("sam", five: window(121, resetsIn: 5_100),    // 9:25am, today
                             seven: window(62, resetsIn: 158_400))],       // 4:00am, Sunday
            settings: settings, now: now
        )
        t.checkEqual(vm.menuBar[2], StyledText("sam 100%", .critical), "menu bar: overshoot clamps to 100%")
        let w = vm.accounts[0].windows
        t.checkEqual(
            w[0].text, "5h  ▓▓▓▓▓▓▓▓▓▓  100%  ·  reset 9:25am",
            "121% displays as 100%, and the bar stays full rather than wider"
        )
        t.checkEqual(w[0].tone, .critical, "overshoot is still critical")
        t.checkEqual(
            w[1].text, "7d  ▓▓▓▓▓▓░░░░   62%  ·  reset Sun 4:00am",
            "the other window is untouched"
        )
    }

    // MARK: The row template

    do {
        func row(_ template: String, used: Double = 50, resetsIn: TimeInterval = 5_100) -> String {
            render(
                accounts: [state("a", five: window(used, resetsIn: resetsIn))],
                settings: AppSettings(rowTemplate: template), now: now
            ).accounts[0].windows[0].text
        }
        t.checkEqual(
            row("{name}: {bar} {pct} · {reset_in} left"),
            "5h: ▓▓▓▓▓░░░░░  50% · 1h 25m left",
            "every token substitutes; the surrounding text is kept verbatim"
        )
        t.checkEqual(row("{pct}"), " 50%", "percent is right-aligned in a 4-wide column")
        t.checkEqual(row("{pct}", used: 100), "100%", "…which a three-digit percent fills exactly")
        t.checkEqual(row("{pct}", used: 0), "  0%", "…and a one-digit percent is padded, not shifted")
        t.checkEqual(
            row("{name} {reset_at} {reset_in}"), "5h 9:25am 1h 25m",
            "both reset forms are available at once"
        )
        t.checkEqual(
            row("{name} {nope} {bar"), "5h {nope} {bar",
            "an unknown token and an unclosed brace stand as literal text — never an error"
        )
        t.checkEqual(row("no tokens at all"), "no tokens at all", "a template may have no tokens")
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

        let after = render(accounts: [state("john", five: window(80, resetsIn: -3_600))],
                           settings: settings, now: now)
        let w = after.accounts[0].windows[0]
        t.checkEqual(
            w.text, "5h  ░░░░░░░░░░    0%  ·  reset passed — empty until a session confirms",
            "after reset: empty, and the inference is stated plainly in place of a reset time"
        )
        t.checkEqual(w.tone, .normal, "after reset: no stale alarm")

        // The template describes a live window; the inferred row is not its to shape.
        t.checkEqual(
            render(accounts: [state("john", five: window(80, resetsIn: -3_600))],
                   settings: AppSettings(rowTemplate: "{pct} · {reset_at}"), now: now)
                .accounts[0].windows[0].text,
            w.text,
            "a custom template does not get to render a reset time that does not exist"
        )
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
                   settings: AppSettings(rowTemplate: "{bar}"), now: now)
                .accounts[0].windows[0].text
        }
        t.checkEqual(bar(0), "░░░░░░░░░░", "0%: empty bar")
        t.checkEqual(bar(100), "▓▓▓▓▓▓▓▓▓▓", "100%: full bar")
        t.checkEqual(bar(4.9), "░░░░░░░░░░", "4.9%: rounds to no glyph")
        t.checkEqual(bar(5), "▓░░░░░░░░░", "5%: rounds to one glyph")
        t.checkEqual(bar(99.4), "▓▓▓▓▓▓▓▓▓▓", "99.4%: rounds to full")
        t.checkEqual(bar(121), "▓▓▓▓▓▓▓▓▓▓", "121%: full, not overflowing")
    }

    // MARK: The two reset forms across unit and day boundaries

    do {
        func resetIn(_ resetsIn: TimeInterval) -> String {
            render(accounts: [state("a", five: window(10, resetsIn: resetsIn))],
                   settings: AppSettings(rowTemplate: "{reset_in}"), now: now)
                .accounts[0].windows[0].text
        }
        t.checkEqual(resetIn(59), "1m", "sub-minute floors at 1m")
        t.checkEqual(resetIn(3_540), "59m", "minutes up to the hour")
        t.checkEqual(resetIn(3_600), "1h 0m", "exactly one hour")
        t.checkEqual(resetIn(86_400), "1d 0h", "exactly one day")

        func resetAt(_ resetsIn: TimeInterval) -> String {
            render(accounts: [state("a", five: window(10, resetsIn: resetsIn))],
                   settings: AppSettings(rowTemplate: "{reset_at}"), now: now)
                .accounts[0].windows[0].text
        }
        // now is Fri 2027-01-15, 08:00 UTC.
        t.checkEqual(resetAt(60), "8:01am", "later today: bare time, no space before the meridiem")
        t.checkEqual(resetAt(14_400), "12:00pm", "noon is 12pm, not 0pm")
        t.checkEqual(resetAt(57_540), "11:59pm", "tonight, one minute before midnight: still today")
        t.checkEqual(resetAt(57_600), "Sat 12:00am", "midnight is 12am — and it is already tomorrow")
        t.checkEqual(resetAt(86_400), "Sat 8:00am", "not today: the weekday comes along")
        t.checkEqual(resetAt(604_800), "Fri 8:00am", "a full 7-day window out: same weekday, still qualified")
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
        t.checkEqual(vm.accounts[1].windows.count, 1,
                     "partial snapshot: only the present window renders")
        t.check(vm.accounts[1].windows[0].text.hasPrefix("7d"),
                "…and it is the 7-day one")
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
