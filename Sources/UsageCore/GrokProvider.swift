import Foundation

// MARK: - Why this adapter polls grok.com

// The Grok TUI's "Usage limit" tab is not a local reconstruction: it is
// `creditUsagePercent` plus `currentPeriod.end` from
// `GET https://cli-chat-proxy.grok.com/v1/billing?format=credits`, authenticated
// with the session already sitting in `<GROK_HOME>/auth.json`. That is the
// weekly pool the screenshot labels "Weekly limit (X Premium)". This adapter
// asks the same endpoint and maps it onto UsageCore's one-row snapshot, the
// way Kimi asks `/usages`.
//
// SAFETY BOUNDARY: never write `auth.json` and never refresh its token. Grok
// rotates the session itself; a competing writer can log the user out. An
// expired token therefore shows as expired rather than being renewed.

// MARK: - Credentials

public struct GrokCredential: Equatable {
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

public enum GrokCredentialStore {
    public static let relativePath = "auth.json"

    /// Reads Grok's credential file and nothing else. The file is a map of
    /// issuer entries; each entry has many fields this adapter is not allowed
    /// to retain (`refresh_token` in particular). Codable skips unknown keys.
    public static func read(grokHome: URL) -> GrokCredential? {
        let file = grokHome.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return nil }

        var best: GrokCredential?
        for entry in entries.values {
            guard let token = entry.key, !token.isEmpty else { continue }
            let expiresAt = GrokDate.parse(entry.expiresAt) ?? Date.distantFuture
            let credential = GrokCredential(accessToken: token, expiresAt: expiresAt)
            if best == nil || credential.expiresAt > best!.expiresAt {
                best = credential
            }
        }
        return best
    }

    private struct Entry: Decodable {
        let key: String?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case key
            case expiresAt = "expires_at"
        }
    }
}

// MARK: - Payload adapter

public enum GrokUsageParseError: Error, Equatable {
    case malformedPayload
}

/// Adapts grok's `/v1/billing?format=credits` body into one UsageCore row —
/// the weekly (or, rarely, monthly) pool the TUI draws as its usage-limit bar.
public enum GrokUsageParser {
    public static func parse(_ data: Data, capturedAt: Date) throws -> Snapshot {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw GrokUsageParseError.malformedPayload
        }

        guard let percent = payload.config.creditUsagePercent,
              percent.isFinite, percent >= 0,
              let endRaw = payload.config.currentPeriod?.end,
              let resetsAt = GrokDate.parse(endRaw)
        else { throw GrokUsageParseError.malformedPayload }

        let window = window(for: payload.config.currentPeriod)
        // A percentage-only source is a count out of 100, the same floor Claude
        // uses. The TUI bar *is* this percentage; there is no token denominator
        // on the wire.
        return Snapshot(
            rows: [UsageRow(
                window: window,
                used: percent,
                limit: 100,
                resetsAt: resetsAt
            )],
            updatedAt: capturedAt,
            primary: window
        )
    }

    private static func window(for period: Period?) -> UsageWindow {
        switch period?.type {
        case "USAGE_PERIOD_TYPE_WEEKLY":
            return .weekly
        case "USAGE_PERIOD_TYPE_MONTHLY":
            return .other(minutes: 30 * 1440)
        default:
            return .weekly
        }
    }

    private struct Payload: Decodable {
        let config: Config
    }

    private struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
    }

    private struct Period: Decodable {
        let type: String?
        let end: String?
    }
}

enum GrokDate {
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return whole.date(from: raw)
    }
}

// MARK: - Pure poll state machine

public enum GrokStaleReason: Equatable {
    case tokenExpired
    case unreachable
}

public enum GrokProviderState: Equatable {
    case snapshot(Snapshot)
    case stale(Snapshot, reason: GrokStaleReason)
    case tokenExpired
    case unreachable
}

public enum GrokFetchResult: Equatable {
    case response(statusCode: Int, body: Data)
    case timeout
    case networkFailure
}

public enum GrokResponseStateMachine {
    public static func reduce(_ result: GrokFetchResult, capturedAt: Date) -> GrokProviderState {
        switch result {
        case .response(statusCode: 200, body: let body):
            guard let snapshot = try? GrokUsageParser.parse(body, capturedAt: capturedAt)
            else { return .unreachable }
            return .snapshot(snapshot)
        case .response(statusCode: 401, body: _),
             .response(statusCode: 403, body: _):
            return .tokenExpired
        case .response, .timeout, .networkFailure:
            return .unreachable
        }
    }

    public static func carryForward(
        _ outcome: GrokProviderState, lastKnown: Snapshot?
    ) -> GrokProviderState {
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

public enum GrokPollTrigger: Equatable {
    case timer
    case dropdownOpened
    case startup
}

public struct GrokPollDecision: Equatable {
    public let bearerToken: String?
    public let nextCredentialCheckAfter: TimeInterval
    public let networkInterval: TimeInterval

    public var shouldRequest: Bool { bearerToken != nil }
}

public struct GrokPollSchedule {
    public static let liveInterval: TimeInterval = 60
    public static let idleInterval: TimeInterval = 15 * 60
    public static let credentialCheckInterval: TimeInterval = 60

    private var wasLive = false
    private var nextRequestAt = Date.distantPast

    public init() {}

    public mutating func plan(
        credential: GrokCredential?,
        now: Date,
        trigger: GrokPollTrigger
    ) -> GrokPollDecision {
        guard let credential, credential.isLive(at: now) else {
            wasLive = false
            nextRequestAt = now.addingTimeInterval(Self.idleInterval)
            return GrokPollDecision(
                bearerToken: nil,
                nextCredentialCheckAfter: Self.credentialCheckInterval,
                networkInterval: Self.idleInterval
            )
        }

        let shouldRequest = trigger != .timer || !wasLive || now >= nextRequestAt
        wasLive = true
        if shouldRequest {
            nextRequestAt = now.addingTimeInterval(Self.liveInterval)
        }
        return GrokPollDecision(
            bearerToken: shouldRequest ? credential.accessToken : nil,
            nextCredentialCheckAfter: Self.credentialCheckInterval,
            networkInterval: Self.liveInterval
        )
    }
}

// MARK: - Network driver

public protocol GrokUsageTransport {
    func fetchUsage(
        bearerToken: String,
        completion: @escaping (GrokFetchResult) -> Void
    )
}

public final class URLSessionGrokUsageTransport: GrokUsageTransport {
    public static let endpoint = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
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
        // The grok binary sends this; without it the proxy has been seen to
        // answer as if the caller were a browser.
        request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
        return request
    }

    public func fetchUsage(
        bearerToken: String,
        completion: @escaping (GrokFetchResult) -> Void
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

/// Owns the adaptive timer and one account's in-memory Grok state. Account
/// registration is outside this type; it takes a GROK_HOME and emits
/// provider-neutral state.
public final class GrokUsagePoller {
    public typealias StateHandler = (GrokProviderState) -> Void

    private let credentialLoader: () -> GrokCredential?
    private let transport: GrokUsageTransport
    private let now: () -> Date
    private let stateHandler: StateHandler
    private var schedule = GrokPollSchedule()
    private var timer: DispatchSourceTimer?
    private var requestInFlight = false
    private var hasPublishedState = false
    private var lastKnown: Snapshot?

    public private(set) var state: GrokProviderState

    public convenience init(
        grokHome: URL,
        transport: GrokUsageTransport = URLSessionGrokUsageTransport(),
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        self.init(
            credentialLoader: { GrokCredentialStore.read(grokHome: grokHome) },
            transport: transport,
            now: Date.init,
            lastKnown: lastKnown,
            stateHandler: stateHandler
        )
    }

    public init(
        credentialLoader: @escaping () -> GrokCredential?,
        transport: GrokUsageTransport,
        now: @escaping () -> Date,
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        self.credentialLoader = credentialLoader
        self.transport = transport
        self.now = now
        self.lastKnown = lastKnown
        self.stateHandler = stateHandler
        self.state = GrokResponseStateMachine.carryForward(.tokenExpired, lastKnown: lastKnown)
    }

    deinit {
        timer?.cancel()
    }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + GrokPollSchedule.credentialCheckInterval,
            repeating: GrokPollSchedule.credentialCheckInterval,
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

    public func dropdownOpened() {
        evaluate(.dropdownOpened)
    }

    private func evaluate(_ trigger: GrokPollTrigger) {
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
                self.publish(GrokResponseStateMachine.reduce(result, capturedAt: self.now()))
            }
        }
    }

    private func publish(_ outcome: GrokProviderState) {
        if case .snapshot(let snapshot) = outcome { lastKnown = snapshot }
        let newState = GrokResponseStateMachine.carryForward(outcome, lastKnown: lastKnown)
        guard !hasPublishedState || state != newState else { return }
        state = newState
        hasPublishedState = true
        stateHandler(newState)
    }
}

// MARK: - Persistence

/// One last-known snapshot per GROK_HOME. Yacht-owned; never written under the
/// Grok home, and never next to `auth.json`.
public enum GrokSnapshotCache {
    public static func load(from url: URL) -> [String: Snapshot] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Snapshot].self, from: data)
        else { return [:] }
        return entries
    }

    public static func snapshot(grokHome: URL, in cache: [String: Snapshot]) -> Snapshot? {
        cache[key(grokHome)]
    }

    public static func store(
        _ snapshot: Snapshot, grokHome: URL, at url: URL
    ) throws {
        var cache = load(from: url)
        cache[key(grokHome)] = snapshot
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: url, options: .atomic)
    }

    private static func key(_ grokHome: URL) -> String {
        grokHome.standardizedFileURL.path
    }
}
