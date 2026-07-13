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
    /// The live system fact: will this app launch at the next login?
    var isEnabled: Bool { get }
    /// Register or unregister. Throws if the system refused; the caller surfaces
    /// that rather than pretending it took.
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLogin {
    /// The mechanism chosen for this build. Resolved once by the ticket-04
    /// experiment (see `chooseMechanism`), not re-decided per launch.
    static let item: LoginItem = chooseMechanism()

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

// MARK: - Mechanism choice (ticket-04 experiment outcome)

private let bundleIdentifier = "local.another-claude-tracker"

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
func chooseMechanism() -> LoginItem {
    #if LOGIN_USE_LAUNCH_AGENT
    return launchAgentItem()
    #else
    return SMAppServiceLoginItem()
    #endif
}

private func launchAgentItem() -> LaunchAgentLoginItem {
    LaunchAgentLoginItem(label: bundleIdentifier, executableURL: mainExecutableURL())
}

/// The app's own executable, resolved from the running bundle so the launch
/// agent points at exactly this copy.
private func mainExecutableURL() -> URL {
    Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
}
