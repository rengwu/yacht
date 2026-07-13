import Cocoa
import UsageCore

/// Composition root and status item. Owns no display logic: it gathers inputs,
/// calls UsageCore's render, and projects the resulting view model.
final class AppDelegate: NSObject, NSApplicationDelegate {

    static let supportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ClaudeUsage")
    static let configURL = supportDir.appendingPathComponent("config.json")
    /// The command the installer writes; detection compares against it whether
    /// or not the script has been deployed yet.
    static let tapCommand = TapDeployment.scriptURL(in: supportDir).path

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settingsController: SettingsWindowController?

    private(set) var config = ConfigStore.load(from: AppDelegate.configURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        refresh()
        // The snapshots only change while Claude Code runs, but countdowns and
        // staleness are relative to now, so redraw on a timer regardless.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // .common, or the countdowns freeze while the dropdown is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Config mutations (settings window calls these; UI updates at once)

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        try? ConfigStore.save(config, to: AppDelegate.configURL)
        refresh()
    }

    /// Deploy the shared script and write the status line into this account's
    /// settings.json — only ever called from an explicit click.
    func installTap(for account: Account) throws {
        try TapDeployment.deploy(to: AppDelegate.supportDir)
        try TapInstaller.install(configDir: account.configDir, tapCommand: AppDelegate.tapCommand)
        refresh()
    }

    // MARK: - Render cycle

    func refresh() {
        let states = config.accounts.map {
            AccountState.gather(account: $0, tapCommand: AppDelegate.tapCommand)
        }
        let vm = render(accounts: states, settings: config.settings, now: Date())
        statusItem.button?.attributedTitle = Style.statusTitle(vm.menuBar)
        statusItem.menu = menu(for: vm)
        // The settings window reloads itself after its own actions; reloading it
        // here would rebuild its fields every timer tick, mid-edit.
    }

    private func menu(for vm: ViewModel) -> NSMenu {
        let menu = NSMenu()

        if let empty = vm.emptyState {
            menu.addItem(Style.menuLabel(empty, tone: .dimmed))
        }
        for account in vm.accounts {
            menu.addItem(Style.menuLabel(account.label))
            for window in account.windows {
                let name = window.name.padding(toLength: 8, withPad: " ", startingAt: 0)
                menu.addItem(Style.menuLabel(
                    "\(name) \(window.bar)  \(window.percentText)",
                    tone: window.tone, monospace: true, indent: true
                ))
                menu.addItem(Style.menuLabel(window.detail, tone: .dimmed, indent: true))
            }
            menu.addItem(Style.menuLabel(account.freshness, tone: .dimmed, indent: true))
            if let note = account.note {
                menu.addItem(Style.menuLabel(note, tone: .warn, indent: true))
            }
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(
            title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        return menu
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(app: self)
        }
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
