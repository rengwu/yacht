import Foundation
import ServiceManagement
import os

/// Launch-at-login. The checkbox that drives this reports the state the system
/// *actually* holds, queried live — never a preference the app stored and hoped
/// was honoured (spec: "a toggle that silently failed and kept claiming success
/// is worse than not having one").
///
/// Two mechanisms exist because the modern one is not assumed to work: the
/// bundle is ad-hoc signed, which is the condition `SMAppService` is known to
/// reject. Ticket 04 ran the experiment on this machine; `chooseMechanism()`
/// records the outcome. Either mechanism satisfies the same `LoginItem` contract,
/// so the settings window and the rest of the app never know which one won.
protocol LoginItem {
    /// Can this copy of the app be a login item at all? False for a loose
    /// executable — see `UnsupportedLoginItem`.
    var isSupported: Bool { get }
    /// The live system fact: will this app launch at the next login?
    var isEnabled: Bool { get }
    /// Register or unregister. Throws if the system refused; the caller surfaces
    /// that rather than pretending it took.
    func setEnabled(_ enabled: Bool) throws
}

extension LoginItem {
    var isSupported: Bool { true }
}

enum LaunchAtLogin {
    /// The mechanism chosen for this build. Resolved once by the ticket-04
    /// experiment (see `chooseMechanism`), not re-decided per launch.
    static let item: LoginItem = chooseMechanism()

    static var isSupported: Bool { item.isSupported }
    static var isEnabled: Bool { item.isEnabled }
    static func setEnabled(_ enabled: Bool) throws { try item.setEnabled(enabled) }
}

// MARK: - SMAppService (modern, preferred)

/// Wraps `SMAppService.mainApp`. Registration identifies the app by its bundle;
/// there is no path or plist to maintain. Rejects on some ad-hoc-signed bundles,
/// which is exactly what the ticket-04 experiment probes.
struct SMAppServiceLoginItem: LoginItem {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Launch agent (fallback, signing-independent)

/// A per-user launch agent: a plist in `~/Library/LaunchAgents` that the system
/// honours regardless of code signing (the user already runs seven of these).
/// The plist's presence *is* the "launches at login" fact, so `isEnabled` reads
/// the file rather than trusting a stored flag.
struct LaunchAgentLoginItem: LoginItem {
    let label: String
    let executableURL: URL

    private var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        if enabled {
            try fm.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try plistData().write(to: plistURL, options: .atomic)
            // Load it into the running session too, so "launch at login" also
            // means "running now" without waiting for a reboot. Best-effort:
            // the file is the durable fact and is already written.
            bootstrap(load: true)
        } else if fm.fileExists(atPath: plistURL.path) {
            bootstrap(load: false)
            try fm.removeItem(at: plistURL)
        }
    }

    private func plistData() throws -> Data {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executableURL.path],
            "RunAtLoad": true,
            // Only in a graphical login session — this is a menu bar app.
            "LimitLoadToSessionType": "Aqua",
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )
    }

    /// `launchctl bootstrap`/`bootout` against the current GUI domain. Failures
    /// are non-fatal: the plist on disk already decides the next login.
    private func bootstrap(load: Bool) {
        let domain = "gui/\(getuid())"
        let args = load
            ? ["bootstrap", domain, plistURL.path]
            : ["bootout", "\(domain)/\(label)"]
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }
}

// MARK: - Unbundled builds

/// The refusal used when the running code is a loose executable rather than an
/// `.app` — i.e. a `swift run` / `.build` development copy.
///
/// Registering one of those is not a harmless no-op: the system dutifully honours
/// it, and because a bare Unix executable has no bundle to open, macOS launches
/// it *through Terminal*. The first sign is a stray Terminal window at the next
/// login, months later, pointing at a `.build` path that may not even exist any
/// more. So the dev copy declines to register at all; only an installed
/// `Yacht.app` may become a login item.
struct UnsupportedLoginItem: LoginItem {
    var isSupported: Bool { false }
    var isEnabled: Bool { false }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled else { return }  // "off" is already the truth
        throw LoginItemError.notAnAppBundle
    }
}

enum LoginItemError: LocalizedError {
    case notAnAppBundle

    var errorDescription: String? {
        "Launch at login needs Yacht to be running as an app. This copy is a "
            + "loose executable, so the system would launch it through Terminal."
    }
}

// MARK: - Mechanism choice (ticket-04 experiment outcome)

private let bundleIdentifier = "local.yacht"

/// Selects the launch-at-login mechanism for this build.
///
/// **Experiment result (ticket 04, this Mac — macOS 27.0, ad-hoc-signed bundle):**
/// `SMAppService.mainApp.register()` *succeeded*. A fresh process then read
/// `.enabled`, and `sfltool dumpbtm` listed the item under the bundle id — so the
/// registration is a real, persisted system fact, not an in-process claim.
/// `unregister()` cleared it back to `.notRegistered`. The modern API therefore
/// ships; the launch-agent path below stays as a documented, compile-guarded
/// fallback (build with `-DLOGIN_USE_LAUNCH_AGENT`) for a future context where an
/// ad-hoc bundle *is* refused.
///
/// Both mechanisms are gated on actually being an `.app` first — see
/// `UnsupportedLoginItem` for why a `.build` copy must never register.
func chooseMechanism() -> LoginItem {
    guard isRunningFromAppBundle() else { return UnsupportedLoginItem() }
    #if LOGIN_USE_LAUNCH_AGENT
    return launchAgentItem()
    #else
    return SMAppServiceLoginItem()
    #endif
}

/// True only when the executable sits inside a real `Foo.app`. A SwiftPM binary
/// run straight out of `.build` still has a `Bundle.main` — it is just the
/// containing directory, with no `.app` extension and no bundle identifier.
private func isRunningFromAppBundle() -> Bool {
    Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
}

private func launchAgentItem() -> LaunchAgentLoginItem {
    LaunchAgentLoginItem(label: bundleIdentifier, executableURL: mainExecutableURL())
}

/// The app's own executable, resolved from the running bundle so the launch
/// agent points at exactly this copy.
private func mainExecutableURL() -> URL {
    Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
}
