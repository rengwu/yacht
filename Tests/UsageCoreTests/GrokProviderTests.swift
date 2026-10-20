import Foundation
import UsageCore

/// Grok's complete offline seam: a captured billing payload, synthetic
/// credentials, synthetic HTTP outcomes, and a pure cadence state machine.
/// No test creates a URLSession task or touches the network.
func runGrokProviderTests(_ t: Harness) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let reset = "2026-08-30T15:35:34.483090+00:00"
    let resetParser = ISO8601DateFormatter()
    resetParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    func capturedBody(percent: Double = 68) -> Data {
        Data("""
        {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-08-23T15:35:34.483090+00:00","end":"\(reset)"},"creditUsagePercent":\(percent),"onDemandCap":{"val":0},"onDemandUsed":{"val":0},"productUsage":[{"product":"GrokBuild","usagePercent":\(percent)}],"isUnifiedBillingUser":true,"prepaidBalance":{"val":0}}}
        """.utf8)
    }

    // MARK: Credential read — access token + expiry only

    do {
        let home = root.appendingPathComponent("grok-home")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("""
        {
          "https://auth.x.ai::aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa": {
            "key": "bearer-123",
            "expires_at": "2027-01-15T08:15:00Z",
            "refresh_token": "must-never-be-decoded-or-retained",
            "email": "hidden@example.com"
          }
        }
        """.utf8).write(to: home.appendingPathComponent("auth.json"))

        let loaded = GrokCredentialStore.read(grokHome: home)
        t.checkEqual(loaded?.accessToken, "bearer-123", "credential: reads session key")
        t.checkEqual(
            loaded?.isLive(at: capturedAt), true,
            "credential: liveness is exactly expires_at > now"
        )
        t.checkEqual(
            loaded?.isLive(at: capturedAt.addingTimeInterval(15 * 60)), false,
            "credential: equality is expired"
        )

        let before = try Data(contentsOf: home.appendingPathComponent("auth.json"))
        _ = GrokCredentialStore.read(grokHome: home)
        let after = try Data(contentsOf: home.appendingPathComponent("auth.json"))
        t.checkEqual(after, before, "credential: reading leaves the file byte-identical")
    } catch {
        t.check(false, "credential fixture setup threw \(error)")
    }

    t.checkEqual(
        GrokCredentialStore.read(grokHome: root.appendingPathComponent("missing")),
        nil,
        "credential: missing file is unavailable"
    )

    // MARK: Parser — captured billing body

    do {
        let snapshot = try GrokUsageParser.parse(capturedBody(), capturedAt: capturedAt)
        t.checkEqual(snapshot.updatedAt, capturedAt, "fixture: capture time is injected")
        t.checkEqual(snapshot.rows.count, 1, "fixture: the weekly pool is one row")
        t.checkEqual(snapshot.primary, .weekly, "fixture: Grok declares the weekly window primary")
        t.checkEqual(snapshot.rows.map(\.window), [.weekly], "fixture: weekly")
        t.checkEqual(snapshot.rows.map(\.label), ["7d"], "fixture: label derives from the window")
        t.checkEqual(snapshot.rows.map(\.used), [68], "fixture: creditUsagePercent is the used count")
        t.checkEqual(snapshot.rows.map(\.limit), [100], "fixture: percentages are counts out of 100")
        t.checkEqual(
            snapshot.rows[0].resetsAt,
            resetParser.date(from: reset) ?? Date.distantPast,
            "fixture: currentPeriod.end is the reset"
        )
        t.checkEqual(
            snapshot.rows[0].percentage, 68,
            "fixture: the derived share is the TUI's bar"
        )
    } catch {
        t.check(false, "full Grok fixture failed to parse: \(error)")
    }

    do {
        let monthly = Data("""
        {"config":{"creditUsagePercent":12,"currentPeriod":{"type":"USAGE_PERIOD_TYPE_MONTHLY","end":"2026-09-30T15:35:34Z"}}}
        """.utf8)
        let snapshot = try GrokUsageParser.parse(monthly, capturedAt: capturedAt)
        t.checkEqual(snapshot.primary, .other(minutes: 30 * 1440), "parser: a monthly pool is its own window")
        t.checkEqual(snapshot.rows.map(\.label), ["30d"], "parser: 30-day label derives from duration")
    } catch {
        t.check(false, "monthly Grok payload failed to parse: \(error)")
    }

    t.checkThrows(
        GrokUsageParseError.malformedPayload,
        "parser: malformed body is rejected"
    ) {
        _ = try GrokUsageParser.parse(Data("not json".utf8), capturedAt: capturedAt)
    }
    t.checkThrows(
        GrokUsageParseError.malformedPayload,
        "parser: missing percent is rejected"
    ) {
        _ = try GrokUsageParser.parse(
            Data("{\"config\":{\"currentPeriod\":{\"type\":\"USAGE_PERIOD_TYPE_WEEKLY\",\"end\":\"2026-08-30T15:35:34Z\"}}}".utf8),
            capturedAt: capturedAt
        )
    }

    // MARK: Response state machine

    t.checkEqual(
        GrokResponseStateMachine.reduce(
            .response(statusCode: 200, body: capturedBody()), capturedAt: capturedAt
        ).mapPrimaryUsed,
        68,
        "state: 200 publishes a snapshot"
    )
    t.checkEqual(
        GrokResponseStateMachine.reduce(
            .response(statusCode: 401, body: Data()), capturedAt: capturedAt
        ),
        .tokenExpired,
        "state: 401 is an expired token"
    )
    t.checkEqual(
        GrokResponseStateMachine.reduce(
            .response(statusCode: 500, body: Data()), capturedAt: capturedAt
        ),
        .unreachable,
        "state: a non-200 is unreachable"
    )
    t.checkEqual(
        GrokResponseStateMachine.reduce(.timeout, capturedAt: capturedAt),
        .unreachable,
        "state: a timeout is unreachable"
    )
    t.checkEqual(
        GrokResponseStateMachine.reduce(
            .response(statusCode: 200, body: Data("{}".utf8)), capturedAt: capturedAt
        ),
        .unreachable,
        "state: 200 with an unreadable body is unreachable, not a zero bar"
    )

    let known: Snapshot
    do {
        known = try GrokUsageParser.parse(capturedBody(), capturedAt: capturedAt)
    } catch {
        t.check(false, "known snapshot fixture threw \(error)")
        return
    }

    t.checkEqual(
        GrokResponseStateMachine.carryForward(.tokenExpired, lastKnown: known),
        .stale(known, reason: .tokenExpired),
        "state: an expired token carries the last figure forward"
    )
    t.checkEqual(
        GrokResponseStateMachine.carryForward(.unreachable, lastKnown: nil),
        .unreachable,
        "state: unreachable with no prior figure stays figure-less"
    )

    // MARK: Cadence

    do {
        var schedule = GrokPollSchedule()
        let live = GrokCredential(
            accessToken: "tok",
            expiresAt: capturedAt.addingTimeInterval(3_600)
        )
        let first = schedule.plan(credential: live, now: capturedAt, trigger: .startup)
        t.checkEqual(first.shouldRequest, true, "cadence: startup polls immediately")
        let timer = schedule.plan(
            credential: live, now: capturedAt.addingTimeInterval(10), trigger: .timer
        )
        t.checkEqual(timer.shouldRequest, false, "cadence: a timer inside the live interval waits")
        let due = schedule.plan(
            credential: live, now: capturedAt.addingTimeInterval(61), trigger: .timer
        )
        t.checkEqual(due.shouldRequest, true, "cadence: a timer past the live interval polls")
        let open = schedule.plan(
            credential: live, now: capturedAt.addingTimeInterval(5), trigger: .dropdownOpened
        )
        t.checkEqual(open.shouldRequest, true, "cadence: opening the dropdown always polls")

        let expired = GrokCredential(accessToken: "tok", expiresAt: capturedAt)
        var idle = GrokPollSchedule()
        let skipped = idle.plan(credential: expired, now: capturedAt, trigger: .timer)
        t.checkEqual(skipped.bearerToken, nil, "cadence: an expired token does not go on the wire")
        t.checkEqual(skipped.networkInterval, GrokPollSchedule.idleInterval, "cadence: idle backs off")
    }

    // MARK: Request construction and provider-neutral rendering

    do {
        let request = URLSessionGrokUsageTransport.request(bearerToken: "secret")
        t.checkEqual(
            request.url, URLSessionGrokUsageTransport.endpoint,
            "transport: calls only the billing credits endpoint"
        )
        t.checkEqual(request.httpMethod, "GET", "transport: GET")
        t.checkEqual(request.timeoutInterval, 8, "transport: 8-second timeout")
        t.checkEqual(
            request.value(forHTTPHeaderField: "Authorization"), "Bearer secret",
            "transport: bearer authorization"
        )
        t.checkEqual(
            request.value(forHTTPHeaderField: "Accept"), "application/json",
            "transport: JSON accept header"
        )
        t.checkEqual(
            request.value(forHTTPHeaderField: "x-grok-client-mode"), "cli",
            "transport: identifies as the grok CLI, not a browser"
        )
    }

    do {
        let account = Account(
            provider: .grok,
            label: "grok",
            configDir: URL(fileURLWithPath: "/fixtures/grok")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let expired = render(
            accounts: [AccountState(account: account, grok: .tokenExpired)],
            settings: AppSettings(),
            now: capturedAt,
            calendar: calendar
        )
        t.checkEqual(
            expired.menuBar[2], StyledText("grok —", .dimmed),
            "render: expired token uses existing dimmed no-data bar"
        )
        t.checkEqual(
            expired.accounts[0].note, "token expired — run grok to refresh",
            "render: expired token explains the routine recovery"
        )
        t.checkEqual(expired.accounts[0].noteTone, .dimmed, "render: expiry is not a warning")

        let live = render(
            accounts: [AccountState(account: account, grok: .snapshot(known))],
            settings: AppSettings(showMenuBarIcon: false),
            now: known.rows[0].resetsAt.addingTimeInterval(-3_600),
            calendar: calendar
        )
        t.checkEqual(
            live.menuBar[0], StyledText("grok 68%", .normal),
            "render: the weekly pool is the bar's figure"
        )
        t.checkEqual(live.accounts[0].note, nil, "render: a live snapshot has no note")
        t.checkEqual(live.accounts[0].windows.count, 1, "render: one window, the weekly")
        t.check(live.accounts[0].windows[0].text.hasPrefix("7d"), "render: dropdown names the week")

        let claude = AccountState(
            account: Account(label: "claude", configDir: URL(fileURLWithPath: "/fixtures/claude")),
            snapshot: Snapshot(
                rows: [UsageRow(
                    window: .fiveHour, used: 20, limit: 100,
                    resetsAt: capturedAt.addingTimeInterval(3_600)
                )],
                updatedAt: capturedAt
            ),
            tapStatus: .installed
        )
        let mixed = render(
            accounts: [claude, AccountState(account: account, grok: .unreachable)],
            settings: AppSettings(),
            now: capturedAt,
            calendar: calendar
        )
        t.checkEqual(
            mixed.menuBar[2], StyledText("claude 20%", .normal),
            "isolation: a Grok failure leaves Claude's bar figure untouched"
        )
    }

    // MARK: Cache — Yacht-owned, never next to auth.json

    do {
        let grokHome = root.appendingPathComponent("cache-home")
        try fm.createDirectory(at: grokHome, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: grokHome.appendingPathComponent("auth.json"))
        let beforeHome = ((try? fm.subpathsOfDirectory(atPath: grokHome.path)) ?? []).sorted()
        let cacheURL = root.appendingPathComponent("yacht-support/grok-cache.json")
        try GrokSnapshotCache.store(known, grokHome: grokHome, at: cacheURL)
        t.checkEqual(
            GrokSnapshotCache.snapshot(
                grokHome: grokHome, in: GrokSnapshotCache.load(from: cacheURL)
            ),
            known,
            "cache: a successful snapshot round-trips outside GROK_HOME"
        )
        t.checkEqual(
            ((try? fm.subpathsOfDirectory(atPath: grokHome.path)) ?? []).sorted(),
            beforeHome,
            "cache: storing writes only to Yacht support, never the Grok home"
        )
    } catch {
        t.check(false, "cache fixture threw \(error)")
    }
}

private extension GrokProviderState {
    var mapPrimaryUsed: Double? {
        if case .snapshot(let snapshot) = self { return snapshot.primaryRow?.used }
        return nil
    }
}
