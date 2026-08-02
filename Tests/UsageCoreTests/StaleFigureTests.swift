import Foundation
import UsageCore

/// Carrying Kimi's last-known figure forward instead of blanking on token
/// expiry — the whole path, from the pure carry-forward rule through the poller
/// to what the bar and dropdown actually say, plus the cache that survives a
/// relaunch. See `.plan/multi-provider/tickets/08-stale-kimi-figures.md`.
func runStaleFigureTests(_ t: Harness) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")

    let capturedAt = Date(timeIntervalSince1970: 1_753_920_000)
    let account = Account(
        provider: .kimi, label: "kimi", configDir: URL(fileURLWithPath: "/fixtures/kimi")
    )

    /// Both windows live well past every `now` these tests use, so nothing here
    /// is accidentally measuring the reset-boundary rule instead of staleness.
    func snapshot(fiveHour: Double, weekly: Double, at moment: Date = capturedAt) -> Snapshot {
        Snapshot(
            rows: [
                UsageRow(
                    window: .fiveHour, used: fiveHour, limit: 100,
                    resetsAt: moment.addingTimeInterval(30 * 86_400)
                ),
                UsageRow(
                    window: .weekly, used: weekly, limit: 100,
                    resetsAt: moment.addingTimeInterval(60 * 86_400)
                ),
            ],
            updatedAt: moment
        )
    }

    // MARK: - The pure rule

    let known = snapshot(fiveHour: 0, weekly: 51)

    t.checkEqual(
        KimiResponseStateMachine.carryForward(.tokenExpired, lastKnown: known),
        .stale(known, reason: .tokenExpired),
        "carryForward: expiry over a known figure keeps the figure"
    )
    t.checkEqual(
        KimiResponseStateMachine.carryForward(.unreachable, lastKnown: known),
        .stale(known, reason: .unreachable),
        "carryForward: a failed poll keeps the figure too, with its own reason"
    )
    t.checkEqual(
        KimiResponseStateMachine.carryForward(.tokenExpired, lastKnown: nil),
        .tokenExpired,
        "carryForward: nothing ever fetched still reads as no data"
    )
    t.checkEqual(
        KimiResponseStateMachine.carryForward(.unreachable, lastKnown: nil),
        .unreachable,
        "carryForward: an unreachable first poll still reads as no data"
    )
    let fresh = snapshot(fiveHour: 4, weekly: 60)
    t.checkEqual(
        KimiResponseStateMachine.carryForward(.snapshot(fresh), lastKnown: known),
        .snapshot(fresh),
        "carryForward: a fresh poll always beats the carried figure"
    )

    // MARK: - What the bar and dropdown say

    func view(_ state: KimiProviderState, now: Date) -> ViewModel {
        render(
            accounts: [AccountState(account: account, kimi: state)],
            settings: AppSettings(),
            now: now,
            calendar: calendar
        )
    }

    let twelveMinutesLater = capturedAt.addingTimeInterval(12 * 60)
    let expired = view(.stale(known, reason: .tokenExpired), now: twelveMinutesLater)

    t.checkEqual(
        expired.menuBar[2], StyledText("kimi 0%", .dimmed),
        "render: a stale figure is shown in the bar, dimmed — not replaced by a dash"
    )
    t.checkEqual(
        expired.accounts[0].windows.count, 2,
        "render: the dropdown still lists every window a stale snapshot carries"
    )
    t.checkEqual(
        expired.accounts[0].note, "last fetched 12m ago — kimi hasn't run since",
        "render: the note sizes the doubt with a relative age"
    )
    t.checkEqual(
        expired.accounts[0].noteTone, .dimmed,
        "render: the resting expired state is routine, not a warning"
    )

    let failed = view(.stale(known, reason: .unreachable), now: twelveMinutesLater)
    t.checkEqual(
        failed.accounts[0].note, "last fetched 12m ago — couldn't reach Kimi since",
        "render: a failed poll is distinguished from kimi simply not running"
    )
    t.checkEqual(
        failed.accounts[0].noteTone, .warn,
        "render: a failed poll still warns, even with a figure on screen"
    )

    // Decision 2 of the ticket accepted losing the colour channel to dimming, on
    // the premise that the bar's primary sits near zero — false for a provider
    // whose primary is a weekly window, and the ticket named the carve-out as the
    // remedy in advance. Taken in `.plan/codex-provider/tickets/01`: warn and
    // critical beat dimmed, so staleness never mutes the alarm. Below the warn
    // threshold there is no alarm to mute and dimming is unchanged — which is
    // every assertion above this one.
    let hot = view(
        .stale(snapshot(fiveHour: 95, weekly: 99), reason: .tokenExpired),
        now: twelveMinutesLater
    )
    t.checkEqual(
        hot.menuBar[2], StyledText("kimi 95%", .critical),
        "render: a stale figure over the critical threshold keeps its alarm colour"
    )
    let warm = view(
        .stale(snapshot(fiveHour: 75, weekly: 99), reason: .unreachable),
        now: twelveMinutesLater
    )
    t.checkEqual(
        warm.menuBar[2], StyledText("kimi 75%", .warn),
        "render: exactly at the warn threshold, warn wins over dimmed too"
    )
    let cool = view(
        .stale(snapshot(fiveHour: 74.9, weekly: 99), reason: .tokenExpired),
        now: twelveMinutesLater
    )
    t.checkEqual(
        cool.menuBar[2], StyledText("kimi 75%", .dimmed),
        "render: a hair below warn, a stale figure still dims — the carve-out is"
            + " the alarm, not an exemption from staleness"
    )

    // Age wording across the units the note can reach.
    t.checkEqual(
        view(.stale(known, reason: .tokenExpired), now: capturedAt.addingTimeInterval(30))
            .accounts[0].note,
        "last fetched moments ago — kimi hasn't run since",
        "render: an age under a minute floors instead of reading 0m"
    )
    t.checkEqual(
        view(.stale(known, reason: .tokenExpired), now: capturedAt.addingTimeInterval(-5))
            .accounts[0].note,
        "last fetched moments ago — kimi hasn't run since",
        "render: a capture time nudged into the future never reads as a negative age"
    )
    t.checkEqual(
        view(.stale(known, reason: .tokenExpired), now: capturedAt.addingTimeInterval(9_000))
            .accounts[0].note,
        "last fetched 2h 30m ago — kimi hasn't run since",
        "render: hours and minutes"
    )
    t.checkEqual(
        view(.stale(known, reason: .tokenExpired), now: capturedAt.addingTimeInterval(273_600))
            .accounts[0].note,
        "last fetched 3d 4h ago — kimi hasn't run since",
        "render: days and hours"
    )

    // A stale figure is still subject to the reset boundary — the reason the
    // ticket sets no maximum age. Nothing withdraws the row; the window empties
    // on its own schedule and says so.
    let boundary = capturedAt.addingTimeInterval(3_600)
    let pastReset = Snapshot(
        rows: [
            UsageRow(
                window: .fiveHour, used: 80, limit: 100,
                resetsAt: capturedAt.addingTimeInterval(600)
            )
        ],
        updatedAt: capturedAt
    )
    let expiredRow = view(.stale(pastReset, reason: .tokenExpired), now: boundary)
    t.checkEqual(
        expiredRow.menuBar[2], StyledText("kimi 0%", .dimmed),
        "render: a stale row past its own reset still empties rather than freezing"
    )
    t.check(
        expiredRow.accounts[0].windows[0].text.hasSuffix("reset passed"),
        "render: the stale row states the reset inference, unchanged by staleness"
    )

    // MARK: - Claude is untouched by any of it

    let claudeAccount = Account(
        label: "claude", configDir: URL(fileURLWithPath: "/fixtures/claude")
    )
    let claudeState = AccountState(
        account: claudeAccount, snapshot: snapshot(fiveHour: 23, weekly: 40), tapStatus: .installed
    )
    let mixed = render(
        accounts: [claudeState, AccountState(account: account, kimi: .stale(known, reason: .unreachable))],
        settings: AppSettings(),
        now: twelveMinutesLater,
        calendar: calendar
    )
    t.checkEqual(
        mixed.menuBar[2], StyledText("claude 23%", .normal),
        "isolation: a stale Kimi figure leaves Claude's bar segment and tone alone"
    )
    t.checkEqual(
        mixed.accounts[0].note, nil,
        "isolation: Claude gains no staleness note of its own"
    )

    // MARK: - The poller

    /// Replays a fixed script of outcomes, one per request, so the poller's own
    /// carry-forward and de-duplication can be driven without a network.
    final class ScriptedTransport: KimiUsageTransport {
        private var script: [KimiFetchResult]
        private(set) var requests = 0

        init(_ script: [KimiFetchResult]) { self.script = script }

        func fetchUsage(bearerToken: String, completion: @escaping (KimiFetchResult) -> Void) {
            requests += 1
            completion(script.isEmpty ? .networkFailure : script.removeFirst())
        }
    }

    let payload = Data(
        """
        {"usage":{"limit":"100","used":"51","remaining":"49","resetTime":"2026-08-05T15:16:12Z"},
         "limits":[{"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},
                    "detail":{"limit":"100","remaining":"100","resetTime":"2026-08-01T06:16:12Z"}}]}
        """.utf8
    )

    var clock = capturedAt
    var live = true
    var published: [KimiProviderState] = []
    let transport = ScriptedTransport([.response(statusCode: 200, body: payload)])
    let poller = KimiUsagePoller(
        credentialLoader: {
            KimiCredential(
                accessToken: "secret",
                expiresAt: live ? clock.addingTimeInterval(600) : clock.addingTimeInterval(-600)
            )
        },
        transport: transport,
        now: { clock },
        stateHandler: { published.append($0) }
    )

    /// The poller hands every response back through `DispatchQueue.main.async`,
    /// which in a plain executable only runs while the main run loop does. The
    /// poller's own 60s timer cannot fire inside a window this short, so this
    /// drains the response and nothing else.
    func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    poller.start()
    pump()
    defer { poller.stop() }

    guard case .snapshot = poller.state else {
        return t.check(false, "poller: a live credential yields a fresh snapshot")
    }
    t.check(true, "poller: a live credential yields a fresh snapshot")
    let polled = poller.state

    // The token lapses — the real resting state, fifteen minutes after a turn.
    live = false
    clock = clock.addingTimeInterval(900)
    poller.dropdownOpened()

    if case .stale(let carried, let reason) = poller.state {
        t.checkEqual(.snapshot(carried), polled, "poller: expiry carries the exact polled figure")
        t.checkEqual(reason, .tokenExpired, "poller: and records why it stopped refreshing")
    } else {
        t.check(false, "poller: expiry carries the polled figure forward")
    }
    t.checkEqual(
        transport.requests, 1,
        "poller: an expired token still plans no request — decision 4's boundary is untouched"
    )

    published.removeAll()
    poller.dropdownOpened()
    t.checkEqual(
        published.count, 0,
        "poller: an unchanged stale state does not re-publish and re-render every minute"
    )

    // A poller that has never polled successfully is exactly as it was before.
    let coldPoller = KimiUsagePoller(
        credentialLoader: { nil },
        transport: ScriptedTransport([]),
        now: { capturedAt },
        stateHandler: { _ in }
    )
    t.checkEqual(
        coldPoller.state, .tokenExpired,
        "poller: with no cached figure the state is unchanged from before this ticket"
    )

    // MARK: - The cache

    let cacheURL = root.appendingPathComponent("nested").appendingPathComponent("kimi-cache.json")
    let configDir = URL(fileURLWithPath: "/fixtures/kimi")

    t.checkEqual(
        KimiSnapshotCache.snapshot(
            configDir: configDir, in: KimiSnapshotCache.load(from: cacheURL)
        ),
        nil,
        "cache: a missing file is no cached figure, not an error"
    )

    try? KimiSnapshotCache.store(known, configDir: configDir, at: cacheURL)
    t.checkEqual(
        KimiSnapshotCache.snapshot(
            configDir: configDir, in: KimiSnapshotCache.load(from: cacheURL)
        ),
        known,
        "cache: a stored snapshot round-trips every row, label and date intact"
    )

    let other = URL(fileURLWithPath: "/fixtures/kimi-work")
    try? KimiSnapshotCache.store(fresh, configDir: other, at: cacheURL)
    let both = KimiSnapshotCache.load(from: cacheURL)
    t.checkEqual(
        KimiSnapshotCache.snapshot(configDir: configDir, in: both), known,
        "cache: a second account's write leaves the first account's figure alone"
    )
    t.checkEqual(
        KimiSnapshotCache.snapshot(configDir: other, in: both), fresh,
        "cache: and both are addressable by their own config directory"
    )
    t.checkEqual(
        KimiSnapshotCache.snapshot(
            configDir: URL(fileURLWithPath: "/fixtures/kimi/"), in: both
        ),
        known,
        "cache: the key is the standardized path, so a trailing slash still finds it"
    )

    try? Data("not json".utf8).write(to: cacheURL)
    t.checkEqual(
        KimiSnapshotCache.load(from: cacheURL), [:],
        "cache: a corrupt file reads as empty rather than throwing into the launch path"
    )

    // A cached figure seeds the poller, which is the whole point of the file:
    // the bar shows the number it was showing before the relaunch.
    try? KimiSnapshotCache.store(known, configDir: configDir, at: cacheURL)
    let seeded = KimiUsagePoller(
        credentialLoader: { nil },
        transport: ScriptedTransport([]),
        now: { capturedAt },
        lastKnown: KimiSnapshotCache.snapshot(
            configDir: configDir, in: KimiSnapshotCache.load(from: cacheURL)
        ),
        stateHandler: { _ in }
    )
    t.checkEqual(
        seeded.state, .stale(known, reason: .tokenExpired),
        "cache: a relaunched poller starts stale on the cached figure, not blank"
    )
}
