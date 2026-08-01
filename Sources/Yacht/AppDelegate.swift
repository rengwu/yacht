import Cocoa
import UsageCore

/// Composition root and status item. Owns no display logic: it gathers inputs,
/// calls UsageCore's render, and projects the resulting view model.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    static let supportDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Yacht")
    static let configURL = supportDir.appendingPathComponent("config.json")
    /// Kimi's last-known figures, so a relaunch shows what the bar was showing
    /// when it quit. Yacht's own directory — never anything under KIMI_CODE_HOME.
    static let kimiCacheURL = supportDir.appendingPathComponent("kimi-cache.json")
    /// Codex's last-known figures, keyed by CODEX_HOME. Like the Kimi cache,
    /// this is Yacht-owned and never placed under an account directory.
    static let codexCacheURL = supportDir.appendingPathComponent("codex-cache.json")
    /// The command the installer writes; detection compares against it whether
    /// or not the script has been deployed yet. Shell-quoted, because Claude Code
    /// runs the statusLine value through a shell and the deploy path has a space.
    static let tapCommand = TapDeployment.command(
        forScriptAt: TapDeployment.scriptURL(in: supportDir)
    )

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settingsController: SettingsWindowController?
    /// One adaptive poller per explicitly registered Kimi account. Claude keeps
    /// its independent snapshot reader; a failure here can therefore replace
    /// only the corresponding Kimi state.
    private var kimiPollers: [String: KimiUsagePoller] = [:]
    /// One app-server poller per explicitly registered Codex account.
    private var codexPollers: [String: CodexUsagePoller] = [:]
    /// Rebuild the per-account clients when the one machine-wide executable
    /// changes (including appearing or disappearing between refreshes).
    private var codexPollerBinaryPath: String?

    private(set) var config = ConfigStore.load(from: AppDelegate.configURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        refresh()
        // The snapshots only change while Claude Code runs, but countdowns and the
        // reset boundary are relative to now, so redraw on a timer regardless.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // .common, or the countdowns freeze while the dropdown is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// A menu-bar-only (`.accessory`) app has no main menu by default, which
    /// silently disables the standard text-editing key equivalents — Cmd-A, C, V,
    /// X, Z — because AppKit routes those through the Edit menu to the field
    /// editor. This installs a minimal Edit menu (targets are nil, so they travel
    /// the responder chain to whatever text field is being edited) purely to
    /// restore those shortcuts in the settings window's fields.
    private func installMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
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
        guard account.provider.usesTap else { return }
        try TapDeployment.deploy(to: AppDelegate.supportDir)
        try TapInstaller.install(configDir: account.configDir, tapCommand: AppDelegate.tapCommand)
        refresh()
    }

    // MARK: - Render cycle

    @objc func refresh() {
        syncKimiPollers()
        syncCodexPollers()
        let states = config.accounts.map { account in
            switch account.provider {
            case .claude:
                return AccountState.gather(
                    account: account, tapCommand: AppDelegate.tapCommand
                )
            case .kimi:
                let state = kimiPollers[accountKey(account)]?.state ?? .tokenExpired
                return AccountState(account: account, kimi: state)
            case .codex:
                let state = codexPollers[accountKey(account)]?.state ?? .waiting
                return AccountState(account: account, codex: state)
            }
        }
        let vm = render(accounts: states, settings: config.settings, now: Date())
        statusItem.button?.attributedTitle = Style.statusTitle(vm.menuBar)
        statusItem.menu = menu(for: vm)
        // The settings window reloads itself after its own actions; reloading it
        // here would rebuild its fields every timer tick, mid-edit.
    }

    private func menu(for vm: ViewModel) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if let empty = vm.emptyState {
            menu.addItem(Style.menuLabel(empty, tone: .dimmed))
        }
        for account in vm.accounts {
            menu.addItem(Style.menuLabel(account.label))
            for window in account.windows {
                menu.addItem(Style.menuLabel(
                    window.text, tone: window.tone, monospace: true, indent: true
                ))
            }
            if let note = account.note {
                menu.addItem(Style.menuLabel(note, tone: account.noteTone, indent: true))
            }
            menu.addItem(.separator())
        }

        let refresh = NSMenuItem(
            title: "Refresh", action: #selector(refresh as () -> Void), keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

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

    /// Opening the dropdown is the user-driven override to each pulled
    /// provider's adaptive cadence. Every poller still decides independently
    /// whether it can make a request.
    func menuWillOpen(_ menu: NSMenu) {
        kimiPollers.values.forEach { $0.dropdownOpened() }
        codexPollers.values.forEach { $0.dropdownOpened() }
    }

    private func syncKimiPollers() {
        let kimiAccounts = config.accounts.filter { $0.provider == .kimi }
        let desiredKeys = Set(kimiAccounts.map(accountKey))

        for key in kimiPollers.keys.filter({ !desiredKeys.contains($0) }) {
            kimiPollers.removeValue(forKey: key)?.stop()
        }

        // Read once per sync rather than per account: the file holds every
        // account's entry, and a sync that creates no poller reads nothing.
        lazy var cached = KimiSnapshotCache.load(from: AppDelegate.kimiCacheURL)

        for account in kimiAccounts {
            let key = accountKey(account)
            guard kimiPollers[key] == nil else { continue }
            let poller = KimiUsagePoller(
                kimiCodeHome: account.configDir,
                lastKnown: KimiSnapshotCache.snapshot(configDir: account.configDir, in: cached)
            ) { [weak self] state in
                // Cache only what a poll actually returned. A carried-forward
                // figure is already in the file; rewriting it on every failure
                // would be a disk write per minute per account for no new fact.
                if case .snapshot(let snapshot) = state {
                    try? KimiSnapshotCache.store(
                        snapshot, configDir: account.configDir, at: AppDelegate.kimiCacheURL
                    )
                }
                self?.refresh()
            }
            kimiPollers[key] = poller
            poller.start()
        }
    }

    private func syncCodexPollers() {
        let codexAccounts = config.accounts.filter { $0.provider == .codex }
        let desiredKeys = Set(codexAccounts.map(accountKey))
        let binaryURL = resolvedCodexBinaryURL
        let binaryPath = binaryURL?.standardizedFileURL.path

        if binaryPath != codexPollerBinaryPath {
            codexPollers.values.forEach { $0.stop() }
            codexPollers.removeAll()
            codexPollerBinaryPath = binaryPath
        }

        for key in codexPollers.keys.filter({ !desiredKeys.contains($0) }) {
            codexPollers.removeValue(forKey: key)?.stop()
        }

        lazy var cached = CodexSnapshotCache.load(from: AppDelegate.codexCacheURL)

        for account in codexAccounts {
            let key = accountKey(account)
            guard codexPollers[key] == nil else { continue }
            let poller = CodexUsagePoller(
                codexHome: account.configDir,
                binaryURL: binaryURL,
                lastKnown: CodexSnapshotCache.snapshot(
                    codexHome: account.configDir, in: cached
                )
            ) { [weak self] state in
                if case .snapshot(let snapshot) = state {
                    try? CodexSnapshotCache.store(
                        snapshot,
                        codexHome: account.configDir,
                        at: AppDelegate.codexCacheURL
                    )
                }
                self?.refresh()
            }
            codexPollers[key] = poller
            poller.start()
        }
    }

    /// The configured path is exact and authoritative. Without one, the core
    /// locator searches the settled launchd-safe candidates (never PATH).
    var resolvedCodexBinaryURL: URL? {
        CodexBinaryLocator.resolve(configuredPath: config.codexBinaryPath)
    }

    /// Settings shows the user's exact override even when it is invalid; only
    /// an unset field is filled from automatic discovery.
    var displayedCodexBinaryPath: String {
        config.codexBinaryPath ?? resolvedCodexBinaryURL?.path ?? ""
    }

    private func accountKey(_ account: Account) -> String {
        account.configDir.standardizedFileURL.path
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
