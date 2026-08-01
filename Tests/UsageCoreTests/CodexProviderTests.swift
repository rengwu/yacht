import Foundation
import UsageCore

/// Codex's offline seam: the committed RPC capture, synthetic protocol
/// outcomes, injected filesystem probes, and an injected transport. No test
/// invokes the installed codex binary or reaches the network.
func runCodexProviderTests(_ t: Harness) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let repo = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = repo.appendingPathComponent(
        ".plan/codex-provider/assets/appserver-ratelimits-plus.json"
    )
    let fixture = (try? Data(contentsOf: fixtureURL)) ?? Data()
    let capturedAt = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Binary location — explicit order, no PATH lookup

    do {
        let home = URL(fileURLWithPath: "/Users/test")
        let npm = URL(fileURLWithPath: "/Users/test/.nvm/versions/node/v24.1.0")
        let bundle = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        let override = URL(fileURLWithPath: "/custom/codex")
        let candidates = CodexBinaryLocator.candidates(
            override: override,
            userHome: home,
            npmGlobalPrefix: npm,
            chatGPTCodex: bundle
        )
        t.checkEqual(
            candidates.map(\.path),
            [
                "/custom/codex",
                "/Users/test/.local/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/Users/test/.nvm/versions/node/v24.1.0/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex",
            ],
            "locator: override, user install, system installs, npm, then ChatGPT bundle"
        )
        t.checkEqual(
            CodexBinaryLocator.locate(
                override: override,
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { $0 == override.path || $0 == bundle.path }
            ),
            override,
            "locator: an executable override wins"
        )
        t.checkEqual(
            CodexBinaryLocator.locate(
                override: nil,
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { $0 == home.appendingPathComponent(".local/bin/codex").path
                    || $0 == bundle.path }
            ),
            home.appendingPathComponent(".local/bin/codex"),
            "locator: the user's CLI install beats ChatGPT's bundled version"
        )
        t.checkEqual(
            CodexBinaryLocator.locate(
                override: nil,
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { _ in false }
            ),
            nil,
            "locator: no executable candidate is not found"
        )
        t.checkEqual(
            CodexBinaryLocator.candidates(
                override: home.appendingPathComponent(".local/bin/codex"),
                userHome: home,
                chatGPTCodex: bundle
            ).filter { $0.path == "/Users/test/.local/bin/codex" }.count,
            1,
            "locator: duplicate candidate paths are probed once"
        )
        t.checkEqual(
            CodexBinaryLocator.resolve(
                configuredPath: "/missing/custom/codex",
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { $0 == bundle.path }
            ),
            nil,
            "settings: a missing override is not silently replaced by another codex"
        )
        t.checkEqual(
            CodexBinaryLocator.resolve(
                configuredPath: override.path,
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { $0 == override.path }
            ),
            override,
            "settings: an executable override resolves exactly"
        )
        t.checkEqual(
            CodexBinaryLocator.resolve(
                configuredPath: nil,
                userHome: home,
                npmGlobalPrefix: npm,
                chatGPTCodex: bundle,
                isExecutable: { $0 == bundle.path }
            ),
            bundle,
            "settings: no override uses automatic discovery"
        )
    }

    // MARK: JSON-RPC request contract (transport remains unspawned)

    do {
        func object(_ data: Data) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        }

        let initialize = try object(CodexClient.initializeRequest(clientVersion: "test-version"))
        t.checkEqual(
            (initialize["id"] as? NSNumber)?.intValue, 1,
            "client: initialize has request id 1"
        )
        t.checkEqual(
            initialize["method"] as? String, "initialize",
            "client: initialize method is exact"
        )
        let initializeParams = initialize["params"] as? [String: Any]
        let clientInfo = initializeParams?["clientInfo"] as? [String: Any]
        t.checkEqual(clientInfo?["name"] as? String, "Yacht", "client: identifies Yacht")
        t.checkEqual(
            clientInfo?["version"] as? String, "test-version", "client: sends Yacht's version"
        )

        let initialized = try object(CodexClient.initializedNotification())
        t.checkEqual(initialized["id"] as? NSNumber, nil, "client: initialized is a notification")
        t.checkEqual(
            initialized["method"] as? String, "initialized",
            "client: initialized notification is exact"
        )

        let read = try object(CodexClient.rateLimitsRequest())
        t.checkEqual((read["id"] as? NSNumber)?.intValue, 2, "client: rate-limit read has id 2")
        t.checkEqual(
            read["method"] as? String, "account/rateLimits/read",
            "client: rate-limit method is exact"
        )
        t.check(
            read["params"] is NSNull,
            "client: account/rateLimits/read sends params null, not an empty object"
        )
        t.checkEqual(CodexClient.arguments, ["app-server"], "client: invokes app-server directly")
        t.checkEqual(
            CodexClient.childEnvironment(
                codexHome: URL(fileURLWithPath: "/fixtures/codex-home/../codex-home"),
                base: ["PRESERVED": "yes"]
            ),
            ["PRESERVED": "yes", "CODEX_HOME": "/fixtures/codex-home"],
            "client: preserves the environment and sets the selected CODEX_HOME exactly"
        )
    } catch {
        t.check(false, "client request construction threw \(error)")
    }

    // MARK: Parser — committed live capture and strict drift handling

    do {
        let snapshot = try CodexUsageParser.parse(fixture, capturedAt: capturedAt)
        t.checkEqual(snapshot.updatedAt, capturedAt, "fixture: capture time is injected")
        t.checkEqual(snapshot.primary, .weekly, "fixture: the wire's primary is weekly")
        t.checkEqual(snapshot.rows.count, 1, "fixture: null secondary is not invented")
        t.checkEqual(snapshot.rows[0].window, .weekly, "fixture: 10080 minutes maps to weekly")
        t.checkEqual(snapshot.rows[0].label, "7d", "fixture: weekly label is shared")
        t.checkEqual(snapshot.rows[0].used, 10, "fixture: 10 percent is stored as 10 of 100")
        t.checkEqual(snapshot.rows[0].limit, 100, "fixture: percentage denominator is 100")
        t.checkEqual(
            snapshot.rows[0].resetsAt,
            Date(timeIntervalSince1970: 1_786_010_208),
            "fixture: resetsAt is Unix seconds at the captured instant"
        )
    } catch {
        t.check(false, "live Codex fixture failed to parse: \(error)")
    }

    let nullPrimary = Data("""
    {"id":2,"result":{"rateLimits":{"primary":null,"secondary":null}}}
    """.utf8)
    do {
        let snapshot = try CodexUsageParser.parse(nullPrimary, capturedAt: capturedAt)
        t.checkEqual(snapshot.rows.count, 0, "parser: null primary yields no rows")
        t.checkEqual(snapshot.primaryRow, nil, "parser: null primary is no data")
        t.check(
            !snapshot.rows.contains { $0.percentage == 0 },
            "parser: null primary is explicitly not a made-up 0% row"
        )
    } catch {
        t.check(false, "null primary should be valid no-data: \(error)")
    }

    t.checkThrows(
        CodexUsageParseError.malformedPayload,
        "parser: missing required usedPercent fails"
    ) {
        _ = try CodexUsageParser.parse(Data("""
        {"id":2,"result":{"rateLimits":{"primary":{
          "windowDurationMins":10080,"resetsAt":1786010208
        },"secondary":null}}}
        """.utf8), capturedAt: capturedAt)
    }

    t.checkThrows(
        CodexUsageParseError.malformedPayload,
        "parser: retyped required usedPercent fails"
    ) {
        _ = try CodexUsageParser.parse(Data("""
        {"id":2,"result":{"rateLimits":{"primary":{
          "usedPercent":"10","windowDurationMins":10080,"resetsAt":1786010208
        },"secondary":null}}}
        """.utf8), capturedAt: capturedAt)
    }

    for spelling in ["10", "10.0"] {
        do {
            let parsed = try CodexUsageParser.parse(Data("""
            {"id":2,"result":{"rateLimits":{"primary":{
              "usedPercent":\(spelling),"windowDurationMins":10080,"resetsAt":1786010208,
              "newWindowField":{"anything":true}
            },"secondary":null,"credits":{"unknown":"ignored"}},
            "newTopLevelField":[1,2,3]}}
            """.utf8), capturedAt: capturedAt)
            t.checkEqual(
                parsed.primaryRow?.used, 10,
                "parser: usedPercent \(spelling) parses and unknown keys are ignored"
            )
        } catch {
            t.check(false, "numeric spelling \(spelling) failed to parse: \(error)")
        }
    }

    do {
        let parsed = try CodexUsageParser.parse(Data("""
        {"id":2,"result":{"rateLimits":{"primary":{
          "usedPercent":12.5,"windowDurationMins":1440,"resetsAt":1786010208
        },"secondary":null}}}
        """.utf8), capturedAt: capturedAt)
        t.checkEqual(parsed.primary, .other(minutes: 1440), "parser: unknown duration stays distinct")
        t.checkEqual(parsed.primaryRow?.label, "24h", "parser: unknown duration gets its label")
        t.checkEqual(parsed.primaryRow?.used, 12.5, "parser: a non-integral percentage is preserved")
    } catch {
        t.check(false, "unknown duration failed to parse: \(error)")
    }

    do {
        let parsed = try CodexUsageParser.parse(Data("""
        {"id":2,"result":{"rateLimits":{"primary":{
          "usedPercent":10,"windowDurationMins":null,"resetsAt":1786010208
        },"secondary":{"usedPercent":50,"windowDurationMins":300,"resetsAt":1786010208}}}}
        """.utf8), capturedAt: capturedAt)
        t.checkEqual(
            parsed.rows, [],
            "parser: an unidentifiable primary cannot promote a secondary into the bar"
        )
    } catch {
        t.check(false, "nullable primary fields should produce honest no-data: \(error)")
    }

    // MARK: Four actionable response states and carry-forward

    let stateCases: [(CodexFetchResult, CodexFailure, String)] = [
        (.binaryNotFound, .binaryNotFound, "can't find codex — point Yacht at it"),
        (
            .jsonRPCError(
                code: -32600,
                message: CodexResponseStateMachine.authenticationRequiredMessage
            ),
            .signedOut,
            "signed out — run codex to sign in"
        ),
        (.timeout, .unreachable, "couldn't reach OpenAI — wait"),
        (.response(Data("{".utf8)), .unexpectedReply, "unexpected reply from codex — update Yacht"),
    ]
    for (result, expected, message) in stateCases {
        t.checkEqual(
            CodexResponseStateMachine.reduce(result, capturedAt: capturedAt),
            .failure(expected),
            "state: \(expected) is distinctly reachable"
        )
        t.checkEqual(expected.message, message, "state: \(expected) names its user action")
    }
    t.checkEqual(
        CodexResponseStateMachine.reduce(
            .jsonRPCError(code: -32000, message: "error sending request for url"),
            capturedAt: capturedAt
        ),
        .failure(.unreachable),
        "state: an app-server network error is reachability, not contract drift"
    )
    t.checkEqual(
        CodexResponseStateMachine.reduce(
            .jsonRPCError(code: -32600, message: "method changed"),
            capturedAt: capturedAt
        ),
        .failure(.unexpectedReply),
        "state: another JSON-RPC error is an unexpected reply"
    )

    let known = (try? CodexUsageParser.parse(fixture, capturedAt: capturedAt))
        ?? Snapshot(rows: [], updatedAt: capturedAt)

    // MARK: Registration projection — figures and actionable failures

    let codexAccount = Account(
        provider: .codex,
        label: "codex",
        configDir: URL(fileURLWithPath: "/fixtures/codex")
    )
    for failure in [
        CodexFailure.binaryNotFound,
        .signedOut,
        .unreachable,
        .unexpectedReply,
    ] {
        let vm = render(
            accounts: [AccountState(account: codexAccount, codex: .failure(failure))],
            settings: AppSettings(),
            now: capturedAt
        )
        t.checkEqual(
            vm.accounts[0].note, failure.message,
            "render: Codex failure is exposed as its actionable message: \(failure)"
        )
        t.checkEqual(
            vm.accounts[0].noteTone, .warn,
            "render: Codex failure warns: \(failure)"
        )
    }

    let workSnapshot = Snapshot(
        rows: [UsageRow(
            window: .weekly, used: 10, limit: 100,
            resetsAt: capturedAt.addingTimeInterval(86_400)
        )],
        updatedAt: capturedAt,
        primary: .weekly
    )
    let personalSnapshot = Snapshot(
        rows: [UsageRow(
            window: .weekly, used: 82, limit: 100,
            resetsAt: capturedAt.addingTimeInterval(86_400)
        )],
        updatedAt: capturedAt,
        primary: .weekly
    )
    let twoCodexAccounts = render(
        accounts: [
            AccountState(account: codexAccount, codex: .snapshot(workSnapshot)),
            AccountState(
                account: Account(
                    provider: .codex,
                    label: "codex2",
                    configDir: URL(fileURLWithPath: "/fixtures/codex2")
                ),
                codex: .snapshot(personalSnapshot)
            ),
        ],
        settings: AppSettings(showMenuBarIcon: false),
        now: capturedAt
    )
    t.checkEqual(
        twoCodexAccounts.menuBar,
        [
            StyledText("codex 10%", .normal),
            StyledText(AppSettings.defaultMenuBarSeparator, .dimmed),
            StyledText("codex2 82%", .warn),
        ],
        "render: two registered CODEX_HOME accounts keep independent figures"
    )

    let carried = render(
        accounts: [AccountState(
            account: codexAccount,
            codex: .stale(workSnapshot, reason: .failure(.unreachable))
        )],
        settings: AppSettings(),
        now: capturedAt.addingTimeInterval(12 * 60)
    )
    t.checkEqual(
        carried.accounts[0].note,
        "last fetched 12m ago — couldn't reach OpenAI — wait",
        "render: a carried Codex figure keeps its failure explanation and age"
    )
    t.checkEqual(
        carried.menuBar[2], StyledText("codex 10%", .dimmed),
        "render: a carried Codex figure remains visible in the bar"
    )

    t.checkEqual(
        CodexResponseStateMachine.carryForward(.failure(.unreachable), lastKnown: known),
        .stale(known, reason: .failure(.unreachable)),
        "carryForward: a failed poll after success keeps the exact figure"
    )
    t.checkEqual(
        CodexResponseStateMachine.carryForward(.failure(.unreachable), lastKnown: nil),
        .failure(.unreachable),
        "carryForward: a failed first poll remains no data"
    )

    // MARK: Rollout liveness and adaptive cadence

    let codexHome = root.appendingPathComponent("codex-home")
    let day = codexHome.appendingPathComponent("sessions/2026/08/01")
    try? fm.createDirectory(at: day, withIntermediateDirectories: true)
    let older = day.appendingPathComponent("rollout-older.jsonl")
    let newest = day.appendingPathComponent("rollout-newest.jsonl")
    let history = codexHome.appendingPathComponent("history.jsonl")
    try? Data("old".utf8).write(to: older)
    try? Data("new".utf8).write(to: newest)
    try? Data("newer but irrelevant".utf8).write(to: history)
    let oldDate = capturedAt.addingTimeInterval(-120)
    let freshDate = capturedAt.addingTimeInterval(-30)
    try? fm.setAttributes([.modificationDate: oldDate], ofItemAtPath: older.path)
    try? fm.setAttributes([.modificationDate: freshDate], ofItemAtPath: newest.path)
    try? fm.setAttributes(
        [.modificationDate: capturedAt.addingTimeInterval(100)],
        ofItemAtPath: history.path
    )
    t.checkEqual(
        CodexRolloutLiveness.newestModificationDate(codexHome: codexHome),
        freshDate,
        "liveness: newest dated rollout mtime is the signal; history.jsonl is ignored"
    )

    do {
        var schedule = CodexPollSchedule()
        let startup = schedule.plan(
            newestRolloutModifiedAt: nil, now: capturedAt, trigger: .startup
        )
        t.checkEqual(startup.shouldRequest, true, "cadence: startup polls immediately while idle")
        t.checkEqual(startup.networkInterval, 900, "cadence: idle network interval is ~15min")

        let earlyIdle = schedule.plan(
            newestRolloutModifiedAt: nil,
            now: capturedAt.addingTimeInterval(60),
            trigger: .timer
        )
        t.checkEqual(earlyIdle.shouldRequest, false, "cadence: idle timer does not poll early")
        t.checkEqual(
            earlyIdle.nextLivenessCheckAfter, 60,
            "cadence: rollout liveness is still checked about every minute while idle"
        )

        let becameLive = schedule.plan(
            newestRolloutModifiedAt: capturedAt.addingTimeInterval(119),
            now: capturedAt.addingTimeInterval(120),
            trigger: .timer
        )
        t.checkEqual(becameLive.shouldRequest, true, "cadence: a fresh rollout starts fast phase now")
        t.checkEqual(becameLive.isLive, true, "cadence: a fresh rollout reads live")
        t.checkEqual(becameLive.networkInterval, 60, "cadence: live interval is ~60s")

        let liveEarly = schedule.plan(
            newestRolloutModifiedAt: capturedAt.addingTimeInterval(119),
            now: capturedAt.addingTimeInterval(150),
            trigger: .timer
        )
        t.checkEqual(liveEarly.shouldRequest, false, "cadence: fast phase still respects its minute")

        let opened = schedule.plan(
            newestRolloutModifiedAt: capturedAt.addingTimeInterval(119),
            now: capturedAt.addingTimeInterval(150),
            trigger: .dropdownOpened
        )
        t.checkEqual(opened.shouldRequest, true, "cadence: dropdown open always polls immediately")

        let liveDue = schedule.plan(
            newestRolloutModifiedAt: capturedAt.addingTimeInterval(209),
            now: capturedAt.addingTimeInterval(210),
            trigger: .timer
        )
        t.checkEqual(liveDue.shouldRequest, true, "cadence: live phase polls when its minute is due")

        let backedOff = schedule.plan(
            newestRolloutModifiedAt: capturedAt.addingTimeInterval(119),
            now: capturedAt.addingTimeInterval(1_020),
            trigger: .timer
        )
        t.checkEqual(backedOff.isLive, false, "cadence: an old rollout leaves the fast phase")
        t.checkEqual(backedOff.shouldRequest, false, "cadence: backing off does not add a poll")
        t.checkEqual(backedOff.networkInterval, 900, "cadence: backed-off interval is ~15min")
    }

    // MARK: Poller isolation, carry-forward, cache, and the read-only home

    final class ScriptedTransport: CodexUsageTransport {
        private var script: [CodexFetchResult]
        private(set) var homes: [URL] = []

        init(_ script: [CodexFetchResult]) { self.script = script }

        func fetchRateLimits(
            codexHome: URL,
            completion: @escaping (CodexFetchResult) -> Void
        ) {
            homes.append(codexHome)
            completion(script.isEmpty ? .networkFailure : script.removeFirst())
        }
    }

    struct FileRecord: Equatable {
        let data: Data
        let modifiedAt: Date?
    }

    func tree(_ directory: URL) -> [String: FileRecord] {
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return [:] }
        var result: [String: FileRecord] = [:]
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            let relative = String(url.path.dropFirst(directory.path.count))
            result[relative] = FileRecord(
                data: (try? Data(contentsOf: url)) ?? Data(),
                modifiedAt: try? url.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
            )
        }
        return result
    }

    let auth = codexHome.appendingPathComponent("auth.json")
    try? Data("credential bytes Yacht must never touch".utf8).write(to: auth)
    let beforeHome = tree(codexHome)
    var clock = capturedAt
    var published: [CodexProviderState] = []
    let transport = ScriptedTransport([.response(fixture), .timeout])
    let poller = CodexUsagePoller(
        codexHome: codexHome,
        transport: transport,
        newestRolloutModificationDate: {
            CodexRolloutLiveness.newestModificationDate(codexHome: codexHome)
        },
        now: { clock },
        stateHandler: { published.append($0) }
    )

    func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    poller.start()
    pump()
    defer { poller.stop() }
    t.checkEqual(transport.homes, [codexHome], "poller: request is scoped to this CODEX_HOME")
    if case .snapshot(let fetched) = poller.state {
        t.checkEqual(fetched, known, "poller: a successful request publishes the parsed fixture")
    } else {
        t.check(false, "poller: a successful request publishes a snapshot")
    }

    clock = clock.addingTimeInterval(30)
    poller.dropdownOpened()
    pump()
    t.checkEqual(
        poller.state,
        .stale(known, reason: .failure(.unreachable)),
        "poller: a later failure carries the successful figure forward"
    )
    t.checkEqual(
        transport.homes, [codexHome, codexHome],
        "poller: dropdown open makes a second immediate request for the same account only"
    )
    t.checkEqual(
        CodexRolloutLiveness.newestModificationDate(codexHome: codexHome),
        freshDate,
        "liveness: Yacht's own poll does not advance the rollout signal"
    )
    t.checkEqual(
        tree(codexHome), beforeHome,
        "safety: Yacht-owned polling work creates or modifies nothing under CODEX_HOME"
    )

    let cold = CodexUsagePoller(
        codexHome: codexHome,
        transport: ScriptedTransport([.timeout]),
        newestRolloutModificationDate: { nil },
        now: { capturedAt },
        stateHandler: { _ in }
    )
    cold.start()
    pump()
    cold.stop()
    t.checkEqual(
        cold.state, .failure(.unreachable),
        "poller: a failure with no prior success stays no data"
    )

    let missingBinary = CodexUsagePoller(
        codexHome: codexHome,
        binaryURL: nil,
        stateHandler: { _ in }
    )
    missingBinary.start()
    pump()
    missingBinary.stop()
    t.checkEqual(
        missingBinary.state, .failure(.binaryNotFound),
        "poller: an unresolved binary reaches the can't-find-codex state"
    )

    let cacheURL = root.appendingPathComponent("yacht-support/codex-cache.json")
    t.checkEqual(
        CodexSnapshotCache.snapshot(
            codexHome: codexHome, in: CodexSnapshotCache.load(from: cacheURL)
        ),
        nil,
        "cache: a missing Yacht cache is no prior figure"
    )
    try? CodexSnapshotCache.store(known, codexHome: codexHome, at: cacheURL)
    let restored = CodexSnapshotCache.snapshot(
        codexHome: codexHome, in: CodexSnapshotCache.load(from: cacheURL)
    )
    t.checkEqual(restored, known, "cache: a successful snapshot round-trips outside CODEX_HOME")
    let relaunched = CodexUsagePoller(
        codexHome: codexHome,
        transport: ScriptedTransport([]),
        newestRolloutModificationDate: { nil },
        now: { capturedAt },
        lastKnown: restored,
        stateHandler: { _ in }
    )
    t.checkEqual(
        relaunched.state, .stale(known, reason: .awaitingRefresh),
        "cache: launch restores the last figure marked as awaiting refresh"
    )
    t.checkEqual(
        tree(codexHome), beforeHome,
        "safety: caching writes only to Yacht support, never CODEX_HOME"
    )

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
    let kimiAccount = Account(
        provider: .kimi, label: "kimi", configDir: URL(fileURLWithPath: "/fixtures/kimi")
    )
    let kimi = AccountState(account: kimiAccount, kimi: .snapshot(Snapshot(
        rows: [UsageRow(
            window: .fiveHour, used: 30, limit: 100,
            resetsAt: capturedAt.addingTimeInterval(3_600)
        )],
        updatedAt: capturedAt
    )))
    let beforeFailure = render(accounts: [claude, kimi], settings: AppSettings(), now: capturedAt)
    _ = CodexResponseStateMachine.reduce(.timeout, capturedAt: capturedAt)
    let afterFailure = render(accounts: [claude, kimi], settings: AppSettings(), now: capturedAt)
    t.checkEqual(
        afterFailure, beforeFailure,
        "isolation: a Codex failure leaves Claude and Kimi rendering byte-for-byte unchanged"
    )
}
