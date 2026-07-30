import Foundation
import UsageCore

/// Kimi's complete offline seam: saved live payloads, synthetic credentials,
/// synthetic HTTP outcomes, and a pure cadence state machine. No test creates a
/// URLSession task or touches the network.
func runKimiProviderTests(_ t: Harness) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let assets = repo.appendingPathComponent(".plan/multi-provider/assets")

    func fixture(_ name: String) -> Data {
        (try? Data(contentsOf: assets.appendingPathComponent(name))) ?? Data()
    }

    let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Credential read — access token + epoch expiry only

    do {
        let home = root.appendingPathComponent("kimi-home")
        let credentials = home.appendingPathComponent("credentials")
        try fm.createDirectory(at: credentials, withIntermediateDirectories: true)
        try Data("""
        {
          "access_token": "bearer-123",
          "expires_at": 1800000900,
          "refresh_token": "must-never-be-decoded-or-retained",
          "expires_in": 900
        }
        """.utf8).write(to: credentials.appendingPathComponent("kimi-code.json"))

        let loaded = KimiCredentialStore.read(kimiCodeHome: home)
        t.checkEqual(loaded?.accessToken, "bearer-123", "credential: reads bearer token")
        t.checkEqual(
            loaded?.expiresAt, Date(timeIntervalSince1970: 1_800_000_900),
            "credential: reads expires_at as epoch seconds"
        )
        t.checkEqual(
            loaded?.isLive(at: capturedAt), true,
            "credential: liveness is exactly expires_at > now"
        )
        t.checkEqual(
            loaded?.isLive(at: Date(timeIntervalSince1970: 1_800_000_900)), false,
            "credential: equality is expired"
        )

        let before = try Data(contentsOf: credentials.appendingPathComponent("kimi-code.json"))
        _ = KimiCredentialStore.read(kimiCodeHome: home)
        let after = try Data(contentsOf: credentials.appendingPathComponent("kimi-code.json"))
        t.checkEqual(after, before, "credential: reading leaves the file byte-identical")
    } catch {
        t.check(false, "credential fixture setup threw \(error)")
    }

    t.checkEqual(
        KimiCredentialStore.defaultHome(userHome: URL(fileURLWithPath: "/Users/test")).path,
        "/Users/test/.kimi-code",
        "credential: default KIMI_CODE_HOME is ~/.kimi-code"
    )
    t.checkEqual(
        KimiCredentialStore.read(kimiCodeHome: root.appendingPathComponent("missing")),
        nil,
        "credential: missing file is unavailable"
    )

    // MARK: Parser — real full and partial captures

    do {
        let snapshot = try KimiUsageParser.parse(
            fixture("kimi-usages-fixture.json"),
            capturedAt: capturedAt
        )
        t.checkEqual(snapshot.updatedAt, capturedAt, "fixture: capture time is injected")
        t.checkEqual(snapshot.rows.count, 2, "fixture: only the two usage windows become rows")
        t.checkEqual(snapshot.rows.map(\.window), [.fiveHour, .weekly], "fixture: 5h then weekly")
        t.checkEqual(snapshot.rows.map(\.label), ["5h", "7d"], "fixture: labels derive from windows")
        t.checkEqual(snapshot.rows.map(\.used), [0, 0], "fixture: omitted used means zero")
        t.checkEqual(snapshot.rows.map(\.limit), [100, 100], "fixture: string limits parse")
        t.checkEqual(
            snapshot.rows[0].resetsAt.timeIntervalSince1970,
            1_785_237_372.75,
            "fixture: fractional 5-hour reset timestamp parses"
        )
        t.checkEqual(
            snapshot.rows[1].resetsAt.timeIntervalSince1970,
            1_785_809_772.75,
            "fixture: top-level usage becomes weekly"
        )
    } catch {
        t.check(false, "full Kimi fixture failed to parse: \(error)")
    }

    do {
        let a = try KimiUsageParser.parse(
            fixture("kimi-usages-partial-a.json"),
            capturedAt: capturedAt
        )
        let b = try KimiUsageParser.parse(
            fixture("kimi-usages-partial-b.json"),
            capturedAt: capturedAt
        )
        t.checkEqual(a.rows.map(\.used), [0, 27], "partial A: used field may be absent per row")
        t.checkEqual(b.rows.map(\.used), [1, 27], "partial B: windows advance independently")
    } catch {
        t.check(false, "partial Kimi fixture failed to parse: \(error)")
    }

    do {
        let exhausted = Data("""
        {
          "usage": {
            "limit": "100", "used": "100",
            "resetTime": "2026-08-04T02:16:12Z"
          },
          "limits": [{
            "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
            "detail": {
              "limit": "100", "used": "100",
              "resetTime": "2026-07-28T11:16:12Z"
            }
          }],
          "parallel": {"limit": "999"},
          "totalQuota": {"anything": "ignored"},
          "extra_usage": {"also": "ignored"}
        }
        """.utf8)
        let snapshot = try KimiUsageParser.parse(exhausted, capturedAt: capturedAt)
        t.checkEqual(
            snapshot.rows.map(\.used), [100, 100],
            "parser: absent remaining at exhaustion does not blank either row"
        )
        t.checkEqual(
            snapshot.rows.count, 2,
            "parser: parallel, totalQuota, and extra_usage are not rows"
        )
    } catch {
        t.check(false, "exhausted Kimi payload failed to parse: \(error)")
    }

    t.checkThrows(
        KimiUsageParseError.malformedPayload,
        "parser: malformed body is rejected"
    ) {
        _ = try KimiUsageParser.parse(Data("not json".utf8), capturedAt: capturedAt)
    }

    t.checkThrows(
        KimiUsageParseError.malformedPayload,
        "parser: numeric JSON is not silently accepted where the wire uses strings"
    ) {
        _ = try KimiUsageParser.parse(Data("""
        {
          "usage": {"limit": 100, "remaining": 100, "resetTime": "2026-08-04T02:16:12Z"},
          "limits": []
        }
        """.utf8), capturedAt: capturedAt)
    }

    // MARK: Response state machine — every outcome is synthetic

    let goodBody = fixture("kimi-usages-partial-b.json")
    let goodState = KimiResponseStateMachine.reduce(
        .response(statusCode: 200, body: goodBody),
        capturedAt: capturedAt
    )
    if case .snapshot(let snapshot) = goodState {
        t.checkEqual(snapshot.rows.map(\.used), [1, 27], "state: 200 publishes parsed snapshot")
    } else {
        t.check(false, "state: 200 did not publish a snapshot")
    }
    t.checkEqual(
        KimiResponseStateMachine.reduce(
            .response(statusCode: 401, body: Data()), capturedAt: capturedAt
        ),
        .tokenExpired,
        "state: 401 is the routine expired-token state"
    )
    t.checkEqual(
        KimiResponseStateMachine.reduce(
            .response(statusCode: 500, body: Data()), capturedAt: capturedAt
        ),
        .unreachable,
        "state: 5xx is unreachable"
    )
    t.checkEqual(
        KimiResponseStateMachine.reduce(.timeout, capturedAt: capturedAt),
        .unreachable,
        "state: timeout is unreachable"
    )
    t.checkEqual(
        KimiResponseStateMachine.reduce(.networkFailure, capturedAt: capturedAt),
        .unreachable,
        "state: other transport failure is unreachable"
    )
    t.checkEqual(
        KimiResponseStateMachine.reduce(
            .response(statusCode: 200, body: Data("{".utf8)), capturedAt: capturedAt
        ),
        .unreachable,
        "state: malformed 200 body is unreachable"
    )

    // MARK: Adaptive cadence and dropdown-open override

    do {
        var schedule = KimiPollSchedule()
        let live = KimiCredential(
            accessToken: "token",
            expiresAt: capturedAt.addingTimeInterval(900)
        )
        let first = schedule.plan(credential: live, now: capturedAt, trigger: .startup)
        t.checkEqual(first.bearerToken, "token", "cadence: startup polls immediately when live")
        t.checkEqual(first.networkInterval, 60, "cadence: live network interval is ~60s")

        let early = schedule.plan(
            credential: live,
            now: capturedAt.addingTimeInterval(30),
            trigger: .timer
        )
        t.checkEqual(early.shouldRequest, false, "cadence: timer does not poll early")

        let opened = schedule.plan(
            credential: live,
            now: capturedAt.addingTimeInterval(30),
            trigger: .dropdownOpened
        )
        t.checkEqual(opened.shouldRequest, true, "cadence: dropdown open polls immediately")

        let expired = schedule.plan(
            credential: live,
            now: capturedAt.addingTimeInterval(900),
            trigger: .timer
        )
        t.checkEqual(expired.shouldRequest, false, "cadence: expired token never reaches network")
        t.checkEqual(expired.networkInterval, 900, "cadence: idle network phase is ~15min")
        t.checkEqual(
            expired.nextCredentialCheckAfter, 60,
            "cadence: cheap credential recovery check stays under a minute"
        )

        let refreshed = KimiCredential(
            accessToken: "fresh",
            expiresAt: capturedAt.addingTimeInterval(1_860)
        )
        let recovered = schedule.plan(
            credential: refreshed,
            now: capturedAt.addingTimeInterval(960),
            trigger: .timer
        )
        t.checkEqual(
            recovered.bearerToken, "fresh",
            "cadence: a newly live token overrides the slow phase immediately"
        )
    }

    // MARK: Request construction and provider-neutral rendering

    do {
        let request = URLSessionKimiUsageTransport.request(bearerToken: "secret")
        t.checkEqual(
            request.url, URL(string: "https://api.kimi.com/coding/v1/usages"),
            "transport: calls only the usage endpoint"
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
    }

    do {
        let account = Account(
            provider: .kimi,
            label: "kimi",
            configDir: URL(fileURLWithPath: "/fixtures/kimi")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let expired = render(
            accounts: [AccountState(account: account, kimi: .tokenExpired)],
            settings: AppSettings(),
            now: capturedAt,
            calendar: calendar
        )
        t.checkEqual(
            expired.menuBar[2], StyledText("kimi —", .dimmed),
            "render: expired token uses existing dimmed no-data bar"
        )
        t.checkEqual(
            expired.accounts[0].note, "token expired — run kimi to refresh",
            "render: expired token explains the routine recovery"
        )
        t.checkEqual(expired.accounts[0].noteTone, .dimmed, "render: expiry is not a warning")

        let unreachable = render(
            accounts: [AccountState(account: account, kimi: .unreachable)],
            settings: AppSettings(),
            now: capturedAt,
            calendar: calendar
        )
        t.checkEqual(
            unreachable.menuBar[2], StyledText("kimi —", .dimmed),
            "render: reachability failure uses existing dimmed no-data bar"
        )
        t.checkEqual(
            unreachable.accounts[0].note, "couldn't reach Kimi",
            "render: reachability is distinct from expiry"
        )
        t.checkEqual(unreachable.accounts[0].noteTone, .warn, "render: reachability warns")

        let claudeAccount = Account(
            label: "claude", configDir: URL(fileURLWithPath: "/fixtures/claude")
        )
        let claudeSnapshot = Snapshot(
            rows: [
                UsageRow(
                    window: .fiveHour,
                    used: 23,
                    limit: 100,
                    resetsAt: capturedAt.addingTimeInterval(3_600)
                )
            ],
            updatedAt: capturedAt
        )
        let mixed = render(
            accounts: [
                AccountState(
                    account: claudeAccount,
                    snapshot: claudeSnapshot,
                    tapStatus: .installed
                ),
                AccountState(account: account, kimi: .unreachable),
            ],
            settings: AppSettings(),
            now: capturedAt,
            calendar: calendar
        )
        t.checkEqual(
            mixed.menuBar[2], StyledText("claude 23%", .normal),
            "isolation: Kimi failure leaves Claude's bar figure untouched"
        )
        t.checkEqual(
            mixed.accounts[0].windows.count, 1,
            "isolation: Kimi failure leaves Claude's dropdown rows untouched"
        )
    }
}
