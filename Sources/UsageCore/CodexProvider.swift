import Foundation

// MARK: - Binary discovery

/// Resolves the executable without consulting PATH or invoking a shell. The
/// caller supplies npm's global prefix because obtaining it is a settings-time
/// concern; turning the ordered candidates into a choice stays pure here.
public enum CodexBinaryLocator {
    public static let chatGPTBundledCodex = URL(
        fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"
    )

    public static func candidates(
        override: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        npmGlobalPrefix: URL? = nil,
        chatGPTCodex: URL = chatGPTBundledCodex
    ) -> [URL] {
        var result: [URL] = []
        if let override { result.append(override) }
        result.append(userHome.appendingPathComponent(".local/bin/codex"))
        result.append(URL(fileURLWithPath: "/opt/homebrew/bin/codex"))
        result.append(URL(fileURLWithPath: "/usr/local/bin/codex"))
        if let npmGlobalPrefix {
            result.append(npmGlobalPrefix.appendingPathComponent("bin/codex"))
        }
        result.append(chatGPTCodex)

        var seen = Set<String>()
        return result.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    public static func locate(
        override: URL?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        npmGlobalPrefix: URL? = nil,
        chatGPTCodex: URL = chatGPTBundledCodex,
        isExecutable: ((String) -> Bool)? = nil
    ) -> URL? {
        let probe = isExecutable ?? { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: path)
        }
        return candidates(
            override: override,
            userHome: userHome,
            npmGlobalPrefix: npmGlobalPrefix,
            chatGPTCodex: chatGPTCodex
        ).first { probe($0.path) }
    }

    /// Resolves the Settings value. An entered path is authoritative: silently
    /// falling through to a different installation would leave the field saying
    /// one thing while Yacht executes another, and a missing override must reach
    /// the actionable `binaryNotFound` state. With no configured value, normal
    /// discovery uses the full candidate order above.
    public static func resolve(
        configuredPath: String?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser,
        npmGlobalPrefix: URL? = nil,
        chatGPTCodex: URL = chatGPTBundledCodex,
        isExecutable: ((String) -> Bool)? = nil
    ) -> URL? {
        let probe = isExecutable ?? { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && !isDirectory.boolValue
                && FileManager.default.isExecutableFile(atPath: path)
        }
        if let configuredPath, !configuredPath.isEmpty {
            let configured = URL(fileURLWithPath: configuredPath).standardizedFileURL
            return probe(configured.path) ? configured : nil
        }
        return locate(
            override: nil,
            userHome: userHome,
            npmGlobalPrefix: npmGlobalPrefix,
            chatGPTCodex: chatGPTCodex,
            isExecutable: probe
        )
    }
}

// MARK: - Strict payload adapter

public enum CodexUsageParseError: Error, Equatable {
    case malformedPayload
}

/// Adapts the generated `GetAccountRateLimitsResponse` contract, wrapped in its
/// JSON-RPC envelope, to provider-neutral rows. Unknown keys are deliberately
/// absent from these Decodable types; JSONDecoder reads past additive changes.
public enum CodexUsageParser {
    public static func parse(_ data: Data, capturedAt: Date) throws -> Snapshot {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw CodexUsageParseError.malformedPayload
        }

        // `primary: null` is explicitly no data. It must never acquire a made-up
        // 0%-used row. A primary lacking either nullable piece needed to render
        // it is treated the same way; omitting all rows also prevents a secondary
        // window from accidentally being promoted into the bar.
        guard let primaryPayload = envelope.result.rateLimits.primary,
              let primary = row(primaryPayload)
        else {
            return Snapshot(rows: [], updatedAt: capturedAt, primary: .fiveHour)
        }

        let secondary = envelope.result.rateLimits.secondary.flatMap(row)
        return Snapshot(
            rows: [primary, secondary].compactMap { $0 },
            updatedAt: capturedAt,
            primary: primary.window
        )
    }

    private static func row(_ payload: Window) -> UsageRow? {
        guard let minutes = payload.windowDurationMins,
              let resetsAt = payload.resetsAt
        else { return nil }

        return UsageRow(
            window: usageWindow(minutes),
            used: payload.usedPercent,
            limit: 100,
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
        )
    }

    private static func usageWindow(_ minutes: Int) -> UsageWindow {
        switch minutes {
        case 300: return .fiveHour
        case 10_080: return .weekly
        default: return .other(minutes: minutes)
        }
    }

    private struct Envelope: Decodable {
        let result: Result
    }

    private struct Result: Decodable {
        let rateLimits: RateLimits
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        /// Required by the generated schema. `Double` accepts both the integer
        /// spelling on the RPC and a mathematically equivalent JSON float.
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Int64?
    }
}

// MARK: - Pure response state machine

/// The four failures are deliberately user-action-shaped, not transport-shaped.
public enum CodexFailure: Equatable {
    case binaryNotFound
    case signedOut
    case unreachable
    case unexpectedReply

    public var message: String {
        switch self {
        case .binaryNotFound: return "can't find codex — point Yacht at it"
        case .signedOut: return "signed out — run codex to sign in"
        case .unreachable: return "couldn't reach OpenAI — wait"
        case .unexpectedReply: return "unexpected reply from codex — update Yacht"
        }
    }
}

public enum CodexStaleReason: Equatable {
    /// A disk-cached figure is shown during the immediate launch poll.
    case awaitingRefresh
    case failure(CodexFailure)
}

public enum CodexProviderState: Equatable {
    case waiting
    case snapshot(Snapshot)
    case stale(Snapshot, reason: CodexStaleReason)
    case failure(CodexFailure)
}

/// Synthetic at the UsageCore seam so protocol outcomes are testable without a
/// real account, network, or app-server process.
public enum CodexFetchResult: Equatable {
    case response(Data)
    case jsonRPCError(code: Int, message: String)
    case binaryNotFound
    case timeout
    case networkFailure
    case processFailure
}

public enum CodexResponseStateMachine {
    public static let authenticationRequiredMessage =
        "codex account authentication required to read rate limits"

    public static func reduce(
        _ result: CodexFetchResult, capturedAt: Date
    ) -> CodexProviderState {
        switch result {
        case .response(let data):
            guard let snapshot = try? CodexUsageParser.parse(data, capturedAt: capturedAt)
            else { return .failure(.unexpectedReply) }
            return .snapshot(snapshot)
        case .jsonRPCError(code: -32600, message: let message)
            where message == authenticationRequiredMessage:
            return .failure(.signedOut)
        case .jsonRPCError(code: _, message: let message) where looksLikeNetworkFailure(message):
            return .failure(.unreachable)
        case .binaryNotFound:
            return .failure(.binaryNotFound)
        case .timeout, .networkFailure:
            return .failure(.unreachable)
        case .jsonRPCError, .processFailure:
            return .failure(.unexpectedReply)
        }
    }

    public static func carryForward(
        _ outcome: CodexProviderState, lastKnown: Snapshot?
    ) -> CodexProviderState {
        switch outcome {
        case .snapshot, .stale, .waiting:
            return outcome
        case .failure(let failure):
            return lastKnown.map { .stale($0, reason: .failure(failure)) }
                ?? .failure(failure)
        }
    }

    fileprivate static func looksLikeNetworkFailure(_ message: String) -> Bool {
        let lower = message.lowercased()
        return [
            "network", "connection", "timed out", "timeout", "dns",
            "error sending request", "failed to connect", "couldn't connect",
        ].contains { lower.contains($0) }
    }
}

// MARK: - Rollout liveness and cadence

/// Reads rollout metadata only. It never opens the JSONL body and has no write
/// path into CODEX_HOME.
public enum CodexRolloutLiveness {
    public static func newestModificationDate(
        codexHome: URL, fileManager: FileManager = .default
    ) -> Date? {
        let sessions = codexHome.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: sessions,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: Date?
        for case let url as URL in enumerator {
            let sessionParts = sessions.standardizedFileURL.pathComponents
            let urlParts = url.standardizedFileURL.pathComponents
            guard urlParts.starts(with: sessionParts) else { continue }
            let parts = Array(urlParts.dropFirst(sessionParts.count))
            guard parts.count == 4,
                  parts[0].count == 4,
                  parts[0].allSatisfy(\.isNumber),
                  parts[1].count == 2,
                  parts[1].allSatisfy(\.isNumber),
                  parts[2].count == 2,
                  parts[2].allSatisfy(\.isNumber),
                  parts[3].hasPrefix("rollout-"),
                  parts[3].hasSuffix(".jsonl"),
                  let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .isRegularFileKey]
                  ),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            if let current = newest {
                if modified > current { newest = modified }
            } else {
                newest = modified
            }
        }
        return newest
    }
}

public enum CodexPollTrigger: Equatable {
    case timer
    case dropdownOpened
    case startup
}

public struct CodexPollDecision: Equatable {
    public let shouldRequest: Bool
    public let isLive: Bool
    public let networkInterval: TimeInterval
    /// Liveness stays cheap to inspect once a minute even in the idle phase, so
    /// a newly-written rollout starts fast polling within about a minute.
    public let nextLivenessCheckAfter: TimeInterval
}

public struct CodexPollSchedule {
    public static let liveInterval: TimeInterval = 60
    public static let idleInterval: TimeInterval = 15 * 60
    public static let livenessCheckInterval: TimeInterval = 60

    private var wasLive = false
    private var nextRequestAt = Date.distantPast

    public init() {}

    public mutating func plan(
        newestRolloutModifiedAt: Date?,
        now: Date,
        trigger: CodexPollTrigger
    ) -> CodexPollDecision {
        let isLive = newestRolloutModifiedAt.map {
            $0 >= now.addingTimeInterval(-Self.idleInterval)
        } ?? false
        let becameLive = isLive && !wasLive
        let becameIdle = !isLive && wasLive
        // When a rollout ages out, the due time still carries the fast phase's
        // one-minute deadline. Do not spend one last request on the transition;
        // replace it with the idle deadline below.
        let shouldRequest = trigger != .timer
            || becameLive
            || (!becameIdle && now >= nextRequestAt)
        let interval = isLive ? Self.liveInterval : Self.idleInterval

        if shouldRequest || becameIdle {
            nextRequestAt = now.addingTimeInterval(interval)
        }
        wasLive = isLive

        return CodexPollDecision(
            shouldRequest: shouldRequest,
            isLive: isLive,
            networkInterval: interval,
            nextLivenessCheckAfter: Self.livenessCheckInterval
        )
    }
}

// MARK: - App-server client

public protocol CodexUsageTransport {
    func fetchRateLimits(
        codexHome: URL,
        completion: @escaping (CodexFetchResult) -> Void
    )
}

private struct MissingCodexTransport: CodexUsageTransport {
    func fetchRateLimits(
        codexHome: URL,
        completion: @escaping (CodexFetchResult) -> Void
    ) {
        completion(.binaryNotFound)
    }
}

/// One short-lived app-server per request. It writes JSON-RPC directly to the
/// child's stdin — no shell, no PATH lookup, and no credential file access.
public final class CodexClient: CodexUsageTransport {
    public static let timeout: TimeInterval = 8
    public static let arguments = ["app-server"]

    /// Exposed like Kimi's URLRequest constructor: protocol construction is
    /// testable without spawning the process that transports it.
    public static func initializeRequest(clientVersion: String = "development") throws -> Data {
        try encode([
            "id": 1,
            "method": "initialize",
            "params": ["clientInfo": ["name": "Yacht", "version": clientVersion]],
        ])
    }

    public static func initializedNotification() throws -> Data {
        try encode(["method": "initialized", "params": [:]])
    }

    public static func rateLimitsRequest() throws -> Data {
        try encode([
            "id": 2,
            "method": "account/rateLimits/read",
            "params": NSNull(),
        ])
    }

    public static func childEnvironment(
        codexHome: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var result = base
        result["CODEX_HOME"] = codexHome.standardizedFileURL.path
        return result
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private let executableURL: URL
    private let timeout: TimeInterval
    private let environment: [String: String]
    private let clientVersion: String
    private let callbackQueue: DispatchQueue
    private let lock = NSLock()
    private var sessions: [UUID: Session] = [:]

    public init(
        executableURL: URL,
        timeout: TimeInterval = CodexClient.timeout,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        clientVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "development",
        callbackQueue: DispatchQueue = .main
    ) {
        self.executableURL = executableURL
        self.timeout = timeout
        self.environment = environment
        self.clientVersion = clientVersion
        self.callbackQueue = callbackQueue
    }

    public func fetchRateLimits(
        codexHome: URL,
        completion: @escaping (CodexFetchResult) -> Void
    ) {
        let id = UUID()
        let session = Session(
            executableURL: executableURL,
            codexHome: codexHome,
            timeout: timeout,
            environment: environment,
            clientVersion: clientVersion,
            callbackQueue: callbackQueue
        ) { [weak self] result in
            if let self {
                self.lock.lock()
                self.sessions.removeValue(forKey: id)
                self.lock.unlock()
            }
            completion(result)
        }
        lock.lock()
        sessions[id] = session
        lock.unlock()
        session.start()
    }

    private final class Session {
        private enum Stage { case initialize, rateLimits, finished }

        private let executableURL: URL
        private let codexHome: URL
        private let timeout: TimeInterval
        private let environment: [String: String]
        private let clientVersion: String
        private let callbackQueue: DispatchQueue
        private let completion: (CodexFetchResult) -> Void
        private let queue = DispatchQueue(label: "yacht.codex-app-server")
        private let process = Process()
        private let input = Pipe()
        private let output = Pipe()
        private let errorOutput = Pipe()
        private var stdoutBuffer = Data()
        private var stderrBuffer = Data()
        private var stage = Stage.initialize

        init(
            executableURL: URL,
            codexHome: URL,
            timeout: TimeInterval,
            environment: [String: String],
            clientVersion: String,
            callbackQueue: DispatchQueue,
            completion: @escaping (CodexFetchResult) -> Void
        ) {
            self.executableURL = executableURL
            self.codexHome = codexHome
            self.timeout = timeout
            self.environment = environment
            self.clientVersion = clientVersion
            self.callbackQueue = callbackQueue
            self.completion = completion
        }

        func start() {
            queue.async { self.launch() }
        }

        private func launch() {
            guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
                finish(.binaryNotFound)
                return
            }

            process.executableURL = executableURL
            process.arguments = CodexClient.arguments
            process.environment = CodexClient.childEnvironment(
                codexHome: codexHome, base: environment
            )
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errorOutput

            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.receiveStdout(data) }
            }
            errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                self?.queue.async { self?.receiveStderr(data) }
            }
            process.terminationHandler = { [weak self] _ in
                self?.queue.async { self?.processTerminated() }
            }

            do {
                try process.run()
                try writeJSONLine(CodexClient.initializeRequest(clientVersion: clientVersion))
            } catch {
                finish(.processFailure)
                return
            }

            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, self.stage != .finished else { return }
                self.finish(.timeout)
            }
        }

        private func receiveStdout(_ data: Data) {
            guard stage != .finished else { return }
            guard !data.isEmpty else {
                processTerminated()
                return
            }
            stdoutBuffer.append(data)
            while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(stdoutBuffer[..<newline])
                stdoutBuffer.removeSubrange(...newline)
                handleLine(line)
                if stage == .finished { return }
            }
        }

        private func receiveStderr(_ data: Data) {
            guard stage != .finished, !data.isEmpty else { return }
            stderrBuffer.append(data)
        }

        private func handleLine(_ line: Data) {
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = (object["id"] as? NSNumber)?.intValue
            else { return } // notifications and log lines are not responses

            if id == 1, stage == .initialize {
                if let error = rpcError(object) {
                    finish(.jsonRPCError(code: error.code, message: error.message))
                    return
                }
                guard object.keys.contains("result") else {
                    finish(.processFailure)
                    return
                }
                do {
                    try writeJSONLine(CodexClient.initializedNotification())
                    try writeJSONLine(CodexClient.rateLimitsRequest())
                    stage = .rateLimits
                } catch {
                    finish(.processFailure)
                }
                return
            }

            guard id == 2, stage == .rateLimits else { return }
            if let error = rpcError(object) {
                finish(.jsonRPCError(code: error.code, message: error.message))
            } else if object.keys.contains("result") {
                finish(.response(line))
            } else {
                finish(.processFailure)
            }
        }

        private func processTerminated() {
            guard stage != .finished else { return }
            let message = String(data: stderrBuffer, encoding: .utf8) ?? ""
            finish(
                CodexResponseStateMachine.looksLikeNetworkFailure(message)
                    ? .networkFailure : .processFailure
            )
        }

        private func writeJSONLine(_ message: Data) throws {
            var data = message
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        private func rpcError(_ object: [String: Any]) -> (code: Int, message: String)? {
            guard let error = object["error"] as? [String: Any],
                  let code = (error["code"] as? NSNumber)?.intValue,
                  let message = error["message"] as? String
            else { return nil }
            return (code, message)
        }

        private func finish(_ result: CodexFetchResult) {
            guard stage != .finished else { return }
            stage = .finished
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            callbackQueue.async { self.completion(result) }
        }
    }
}

// MARK: - Per-account poller

/// Owns one account's adaptive timer and carry-forward state. Registration and
/// AppKit projection remain outside this type; the only account input is its
/// CODEX_HOME.
public final class CodexUsagePoller {
    public typealias StateHandler = (CodexProviderState) -> Void

    private let codexHome: URL
    private let transport: CodexUsageTransport
    private let newestRolloutModificationDate: () -> Date?
    private let now: () -> Date
    private let stateHandler: StateHandler
    private var schedule = CodexPollSchedule()
    private var timer: DispatchSourceTimer?
    private var requestInFlight = false
    private var hasPublishedState = false
    private var lastKnown: Snapshot?

    public private(set) var state: CodexProviderState

    public convenience init(
        codexHome: URL,
        binaryURL: URL?,
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        let transport: CodexUsageTransport = binaryURL.map {
            CodexClient(executableURL: $0)
        } ?? MissingCodexTransport()
        self.init(
            codexHome: codexHome,
            transport: transport,
            newestRolloutModificationDate: {
                CodexRolloutLiveness.newestModificationDate(codexHome: codexHome)
            },
            now: Date.init,
            lastKnown: lastKnown,
            stateHandler: stateHandler
        )
    }

    public init(
        codexHome: URL,
        transport: CodexUsageTransport,
        newestRolloutModificationDate: @escaping () -> Date?,
        now: @escaping () -> Date,
        lastKnown: Snapshot? = nil,
        stateHandler: @escaping StateHandler
    ) {
        self.codexHome = codexHome
        self.transport = transport
        self.newestRolloutModificationDate = newestRolloutModificationDate
        self.now = now
        self.lastKnown = lastKnown
        self.stateHandler = stateHandler
        self.state = lastKnown.map { .stale($0, reason: .awaitingRefresh) } ?? .waiting
    }

    deinit { timer?.cancel() }

    public func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + CodexPollSchedule.livenessCheckInterval,
            repeating: CodexPollSchedule.livenessCheckInterval,
            leeway: .seconds(2)
        )
        timer.setEventHandler { [weak self] in self?.evaluate(.timer) }
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

    private func evaluate(_ trigger: CodexPollTrigger) {
        let decision = schedule.plan(
            newestRolloutModifiedAt: newestRolloutModificationDate(),
            now: now(),
            trigger: trigger
        )
        guard decision.shouldRequest, !requestInFlight else { return }
        requestInFlight = true
        transport.fetchRateLimits(codexHome: codexHome) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestInFlight = false
                self.publish(CodexResponseStateMachine.reduce(result, capturedAt: self.now()))
            }
        }
    }

    private func publish(_ outcome: CodexProviderState) {
        if case .snapshot(let snapshot) = outcome { lastKnown = snapshot }
        let newState = CodexResponseStateMachine.carryForward(outcome, lastKnown: lastKnown)
        guard !hasPublishedState || state != newState else { return }
        state = newState
        hasPublishedState = true
        stateHandler(newState)
    }
}
