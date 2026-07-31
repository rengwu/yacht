import Foundation

// MARK: - Credentials

/// The only two credential fields Yacht is permitted to retain. In particular,
/// there is intentionally no refresh-token field or refresh operation here.
public struct KimiCredential: Equatable {
    public let accessToken: String
    public let expiresAt: Date

    public init(accessToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    public func isLive(at now: Date) -> Bool {
        expiresAt > now
    }
}

public enum KimiCredentialStore {
    public static let relativePath = "credentials/kimi-code.json"

    public static func defaultHome(userHome: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        userHome.appendingPathComponent(".kimi-code", isDirectory: true)
    }

    /// Reads Kimi's credential file and nothing else.
    ///
    /// SAFETY BOUNDARY: never write this file and never refresh its token. Kimi
    /// rotates refresh tokens and persists the replacement itself; a competing
    /// writer can silently log the user out. A future refresh implementation
    /// must delete this warning before it can find anywhere to put that token.
    public static func read(kimiCodeHome: URL) -> KimiCredential? {
        let file = kimiCodeHome.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(StoredCredential.self, from: data),
              let token = stored.accessToken,
              !token.isEmpty,
              let expiresAt = stored.expiresAt
        else { return nil }

        return KimiCredential(
            accessToken: token,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }

    /// Decode only the access token and expiry. JSONDecoder skips unknown keys,
    /// so a refresh token in the same file is never decoded or retained.
    private struct StoredCredential: Decodable {
        let accessToken: String?
        let expiresAt: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresAt = "expires_at"
        }
    }
}

// MARK: - Payload adapter

public enum KimiUsageParseError: Error, Equatable {
    case malformedPayload
}

/// Adapts the real upstream `/usages` shape into UsageCore's provider-neutral
/// rows. This does not parse the differently-shaped local `kimi web` response.
public enum KimiUsageParser {
    public static func parse(_ data: Data, capturedAt: Date) throws -> Snapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw KimiUsageParseError.malformedPayload
        }

        guard let weekly = row(payload.usage, window: .weekly) else {
            throw KimiUsageParseError.malformedPayload
        }

        // The upstream row has no label. Its window shape is its identity:
        // 300 minutes means the shared 5-hour window and supplies the "5h"
        // display label through UsageWindow.
        let fiveHour = payload.limits.first {
            $0.window.duration == 300 && $0.window.timeUnit == "TIME_UNIT_MINUTE"
        }.flatMap {
            row($0.detail, window: .fiveHour)
        }

        // 5-hour first, weekly second: the dropdown's significance order. Kimi
        // sends no equivalent of Codex's `primary`, so this adapter declares it
        // — the 5-hour window, unchanged from what the bar has always shown.
        return Snapshot(
            rows: [fiveHour, weekly].compactMap { $0 },
            updatedAt: capturedAt,
            primary: .fiveHour
        )
    }

    private static func row(_ quota: Quota, window: UsageWindow) -> UsageRow? {
        guard let limit = number(quota.limit),
              let resetsAt = date(quota.resetTime)
        else { return nil }

        let used: Double
        if quota.used != nil {
            guard let parsed = number(quota.used) else { return nil }
            used = parsed
        } else {
            // Kimi omits zero-valued numerics. `remaining` is therefore also
            // expected to disappear at exhaustion; absent means zero.
            guard let remaining = number(quota.remaining) else { return nil }
            used = limit - remaining
        }

        return UsageRow(
            window: window,
            used: used,
            limit: limit,
            resetsAt: resetsAt
        )
    }

    /// Every numeric field is a JSON string when present; omission means zero.
    private static func number(_ value: String?) -> Double? {
        guard let value else { return 0 }
        return Double(value)
    }

    private static func date(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }

        let wholeSeconds = ISO8601DateFormatter()
        wholeSeconds.formatOptions = [.withInternetDateTime]
        return wholeSeconds.date(from: value)
    }

    private struct Payload: Decodable {
        let usage: Quota
        let limits: [Limit]
    }

    private struct Limit: Decodable {
        let window: Window
        let detail: Quota
    }

    private struct Window: Decodable {
        let duration: Int
        let timeUnit: String
    }

    private struct Quota: Decodable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String
    }
}

// MARK: - Pure poll state machine

/// Why a carried-forward figure is not being refreshed. `tokenExpired` is the
/// resting state, not a fault: the access token lives 900s and kimi renews it
/// only lazily, so any account that is not mid-turn is here.
public enum KimiStaleReason: Equatable {
    case tokenExpired
    case unreachable
}

public enum KimiProviderState: Equatable {
    case snapshot(Snapshot)
    /// The last figure that *was* fetched, still on display because usage only
    /// accrues while kimi runs — which is exactly when it can be re-polled.
    case stale(Snapshot, reason: KimiStaleReason)
    case tokenExpired
    case unreachable
}

/// Synthetic at the UsageCore seam so tests never need a live endpoint.
public enum KimiFetchResult: Equatable {
    case response(statusCode: Int, body: Data)
    case timeout
    case networkFailure
}

public enum KimiResponseStateMachine {
    public static func reduce(_ result: KimiFetchResult, capturedAt: Date) -> KimiProviderState {
        switch result {
        case .response(statusCode: 200, body: let body):
            guard let snapshot = try? KimiUsageParser.parse(body, capturedAt: capturedAt)
            else { return .unreachable }
            return .snapshot(snapshot)
        case .response(statusCode: 401, body: _):
            return .tokenExpired
        case .response, .timeout, .networkFailure:
            return .unreachable
        }
    }

    /// Second, separate step: `reduce` judges one response in isolation, and this
    /// decides what the *account* shows given what was last known. Kept pure and
    /// apart so the poller holds no display rule of its own, and so "an outcome
    /// with no figure yet" and "the same outcome over a figure" are one decision
    /// in one place.
    ///
    /// A fresh snapshot always wins and always replaces `lastKnown`; the caller
    /// reads the new figure back out of the returned state rather than tracking
    /// it separately.
    public static func carryForward(
        _ outcome: KimiProviderState, lastKnown: Snapshot?
    ) -> KimiProviderState {
        switch outcome {
        case .snapshot, .stale:
            return outcome
        case .tokenExpired:
            return lastKnown.map { .stale($0, reason: .tokenExpired) } ?? .tokenExpired
        case .unreachable:
            return lastKnown.map { .stale($0, reason: .unreachable) } ?? .unreachable
        }
    }
}

public enum KimiPollTrigger: Equatable {
    case timer
    case dropdownOpened
    case startup
}

public struct KimiPollDecision: Equatable {
    public let bearerToken: String?
    /// Credential freshness is cheap and is checked every minute even while the
    /// network is in its 15-minute idle phase. This detects a newly refreshed
    /// Kimi token without waiting for the slow network cadence.
    public let nextCredentialCheckAfter: TimeInterval
    public let networkInterval: TimeInterval

    public var shouldRequest: Bool { bearerToken != nil }
}

/// Cadence only; HTTP response handling stays in KimiResponseStateMachine.
public struct KimiPollSchedule {
    public static let liveInterval: TimeInterval = 60
    public static let idleInterval: TimeInterval = 15 * 60
    public static let credentialCheckInterval: TimeInterval = 60

    private var wasLive = false
    private var nextRequestAt = Date.distantPast

    public init() {}

    public mutating func plan(
        credential: KimiCredential?,
        now: Date,
        trigger: KimiPollTrigger
    ) -> KimiPollDecision {
        guard let credential, credential.isLive(at: now) else {
            wasLive = false
            nextRequestAt = now.addingTimeInterval(Self.idleInterval)
            return KimiPollDecision(
                bearerToken: nil,
                nextCredentialCheckAfter: Self.credentialCheckInterval,
                networkInterval: Self.idleInterval
            )
        }

        // A transition from expired to live means kimi just refreshed the token:
        // poll immediately. Opening the dropdown is also always immediate.
        let shouldRequest = trigger != .timer || !wasLive || now >= nextRequestAt
        wasLive = true
        if shouldRequest {
            nextRequestAt = now.addingTimeInterval(Self.liveInterval)
        }
        return KimiPollDecision(
            bearerToken: shouldRequest ? credential.accessToken : nil,
            nextCredentialCheckAfter: Self.credentialCheckInterval,
            networkInterval: Self.liveInterval
        )
    }
}

// MARK: - Network driver

public protocol KimiUsageTransport {
    func fetchUsage(
        bearerToken: String,
        completion: @escaping (KimiFetchResult) -> Void
    )
}

public final class URLSessionKimiUsageTransport: KimiUsageTransport {
    public static let endpoint = URL(string: "https://api.kimi.com/coding/v1/usages")!
    public static let timeout: TimeInterval = 8

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public static func request(bearerToken: String) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    public func fetchUsage(
        bearerToken: String,
        completion: @escaping (KimiFetchResult) -> Void
    ) {
        session.dataTask(with: Self.request(bearerToken: bearerToken)) { data, response, error in
            if (error as? URLError)?.code == .timedOut {
                completion(.timeout)
                return
            }
            if error != nil {
                completion(.networkFailure)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.networkFailure)
                return
            }
            completion(.response(statusCode: response.statusCode, body: data ?? Data()))
        }.resume()
    }
}

/// Owns the adaptive timer and one account's in-memory Kimi state. Account
/// registration/wiring is intentionally outside this type; it takes a concrete
/// KIMI_CODE_HOME and emits provider-neutral state.
public final class KimiUsagePoller {
    public typealias StateHandler = (KimiProviderState) -> Void

    private let credentialLoader: () -> KimiCredential?
    private let transport: KimiUsageTransport
    private let now: () -> Date
    private let stateHandler: StateHandler
    private var schedule = KimiPollSchedule()
    private var timer: DispatchSourceTimer?
    private var requestInFlight = false
    private var hasPublishedState = false
    /// The last figure a poll actually returned, and the whole of what survives a
    /// failure. Reading it back off `state` would lose it the moment the state
    /// became one of the figure-less cases, which is precisely when it is needed.
    private var lastKnown: Snapshot?

    public private(set) var state: KimiProviderState

    /// `lastKnown` seeds the account's figure from whatever the composition root
    /// cached on a previous run, so a relaunch shows the same number the bar was
    /// showing when it quit rather than blanking until kimi is next used. Disk
    /// stays out of this type: the caller reads the cache, and writes it back
    /// from `stateHandler` when a fresh snapshot arrives.
    public convenience init(
        kimiCodeHome: URL,
        transport: KimiUsageTransport = URLSessionKimiUsageTransport(),
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        self.init(
            credentialLoader: { KimiCredentialStore.read(kimiCodeHome: kimiCodeHome) },
            transport: transport,
            now: Date.init,
            lastKnown: lastKnown,
            stateHandler: stateHandler
        )
    }

    public init(
        credentialLoader: @escaping () -> KimiCredential?,
        transport: KimiUsageTransport,
        now: @escaping () -> Date,
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.now = now
        self.lastKnown = lastKnown
        self.stateHandler = stateHandler
        self.state = KimiResponseStateMachine.carryForward(.tokenExpired, lastKnown: lastKnown)
    }

    deinit {
        timer?.cancel()
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + KimiPollSchedule.credentialCheckInterval,
            repeating: KimiPollSchedule.credentialCheckInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in
            self?.evaluate(.timer)
        }
        timer.resume()
        self.timer = timer
        evaluate(.startup)
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// The AppKit composition root calls this from NSMenuDelegate.menuWillOpen.
    public func dropdownOpened() {
        evaluate(.dropdownOpened)
    }

    private func evaluate(_ trigger: KimiPollTrigger) {
        let timestamp = now()
        let decision = schedule.plan(
            credential: credentialLoader(),
            now: timestamp,
            trigger: trigger
        )
        guard let token = decision.bearerToken else {
            publish(.tokenExpired)
            return
        }
        guard !requestInFlight else { return }

        requestInFlight = true
        transport.fetchUsage(bearerToken: token) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestInFlight = false
                self.publish(KimiResponseStateMachine.reduce(result, capturedAt: self.now()))
            }
        }
    }

    private func publish(_ outcome: KimiProviderState) {
        if case .snapshot(let snapshot) = outcome { lastKnown = snapshot }
        let newState = KimiResponseStateMachine.carryForward(outcome, lastKnown: lastKnown)
        guard !hasPublishedState || state != newState else { return }
        state = newState
        hasPublishedState = true
        stateHandler(newState)
    }
}
