import Cocoa
import UsageCore

/// Composition root and status item. Owns no display logic: it gathers inputs,
/// calls UsageCore's presentation, and projects the resulting view model.
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
    /// Grok's last-known figures, keyed by GROK_HOME. Yacht-owned, never
    /// written next to `auth.json`.
    static let grokCacheURL = supportDir.appendingPathComponent("grok-cache.json")
    /// The command the installer writes; detection compares against it whether
    /// or not the script has been deployed yet. Shell-quoted, because Claude Code
    /// runs the statusLine value through a shell and the deploy path has a space.
    static let tapCommand = TapDeployment.command(
        forScriptAt: TapDeployment.scriptURL(in: supportDir)
    )

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var settingsController: SettingsWindowController?
    private let statusContent = StatusContentView()
    private var appearanceObservation: NSKeyValueObservation?
    private var menuIsOpen = false
    private(set) var states: [AccountState] = []
    private(set) var presentation: [UsageAccountPresentation] = []
    static let isDemo = CommandLine.arguments.contains("--demo")
    /// One adaptive poller per explicitly registered Kimi account. Claude keeps
    /// its independent snapshot reader and Codex its own pollers below; a failure
    /// here can therefore replace only the corresponding Kimi state.
    private var kimiPollers: [String: KimiUsagePoller] = [:]
    /// One app-server poller per explicitly registered Codex account.
    private var codexPollers: [String: CodexUsagePoller] = [:]
    /// One billing poller per explicitly registered Grok account.
    private var grokPollers: [String: GrokUsagePoller] = [:]
    /// Rebuild the per-account clients when the one machine-wide executable
    /// changes (including appearing or disappearing between refreshes).
    private var codexPollerBinaryPath: String?

    private(set) var config = AppDelegate.isDemo ? Demo.config : ConfigStore.load(from: AppDelegate.configURL)

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.isDemo {
            if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
            if CommandLine.arguments.contains("--contrast") { NSApp.appearance = NSAppearance(named: .accessibilityHighContrastAqua) }
        }
        installMainMenu()
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
                guard let self else { return }
                button.image = self.statusContent.image(appearance: button.effectiveAppearance)
            }
        }
        refresh()
        if Self.isDemo || config.accounts.isEmpty { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
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
        let appItem = NSMenuItem(title: "Yacht", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Yacht")
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        if Self.isDemo {
            let previewItem = appMenu.addItem(withTitle: "Usage Preview (Demo)", action: #selector(showDemoMenu), keyEquivalent: "u")
            previewItem.target = self
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Yacht", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        editItem.title = "Edit"
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func showDemoMenu() {
        guard Self.isDemo, let view = settingsController?.window?.contentView else { return }
        statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX, y: view.bounds.maxY), in: view)
    }

    // MARK: - Config mutations (settings window calls these; UI updates at once)

    func update(_ mutate: (inout AppConfig) -> Void) {
        var next = config
        mutate(&next)
        do {
            if !Self.isDemo { try ConfigStore.save(next, to: AppDelegate.configURL) }
            config = next
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn’t save Yacht settings"
            alert.runModal()
        }
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
        if !Self.isDemo {
            syncKimiPollers()
            syncCodexPollers()
            syncGrokPollers()
        }
        let now = Date()
        let previousStates = states
        states = Self.isDemo ? Demo.states(config.accounts) : config.accounts.map { account in
            switch account.provider {
            case .claude:
                return AccountState.gather(
                    account: account, tapCommand: AppDelegate.tapCommand,
                    previous: previousStates.first { $0.account.configDir == account.configDir }?.snapshot
                )
            case .kimi:
                let state = kimiPollers[accountKey(account)]?.state ?? .tokenExpired
                return AccountState(account: account, kimi: state)
            case .codex:
                let state = codexPollers[accountKey(account)]?.state ?? .waiting
                return AccountState(account: account, codex: state)
            case .grok:
                let state = grokPollers[accountKey(account)]?.state ?? .tokenExpired
                return AccountState(account: account, grok: state)
            }
        }
        presentation = presentUsage(accounts: states, config: config, now: now)
        if statusContent.update(presentation, style: config.display.accounts),
           let button = statusItem.button {
            statusItem.length = statusContent.contentWidth
            button.image = statusContent.image(appearance: button.effectiveAppearance)
        }
        statusItem.button?.setAccessibilityLabel("Yacht usage")
        statusItem.button?.setAccessibilityValue(statusContent.toolTip)
        statusItem.button?.toolTip = statusContent.toolTip
        if menuIsOpen {
            let accountViews = statusItem.menu?.items.compactMap { $0.view as? UsageAccountMenuView } ?? []
            for (view, entry) in zip(accountViews, presentation) {
                view.update(entry, style: config.display.accounts)
            }
        } else {
            statusItem.menu = makeMenu()
        }
        settingsController?.refreshPreview()
        // No seconds are displayed. Refresh at minute boundaries or the next reset,
        // while provider completion callbacks still update figures immediately.
        timer?.invalidate()
        let nextMinute = 60 - now.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        let nextReset = states.flatMap { $0.snapshot?.rows ?? [] }
            .map { $0.resetsAt.timeIntervalSince(now) }.filter { $0 > 0 }.min() ?? 60
        let timer = Timer(timeInterval: max(1, min(nextMinute, nextReset)), repeats: false) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        if presentation.isEmpty {
            menu.addItem(Style.menuLabel("Add an account in Settings…", tone: .dimmed))
        }
        for (index, entry) in presentation.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: entry.account.label, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.view = UsageAccountMenuView(entry: entry, style: config.display.accounts)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)

        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(
            title: "Quit Yacht", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        ))
        return menu
    }

    /// Opening the dropdown is the user-driven override to each pulled
    /// provider's adaptive cadence. Every poller still decides independently
    /// whether it can make a request.
    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refreshUsage()
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    @objc func refreshUsage() {
        kimiPollers.values.forEach { $0.dropdownOpened() }
        codexPollers.values.forEach { $0.dropdownOpened() }
        grokPollers.values.forEach { $0.dropdownOpened() }
        refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        kimiPollers.values.forEach { $0.stop() }
        codexPollers.values.forEach { $0.stop() }
        grokPollers.values.forEach { $0.stop() }
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

    /// One billing poller per registered Grok account. Cache is read when a
    /// poller is created and rewritten only on a fresh snapshot, same as Kimi.
    private func syncGrokPollers() {
        let grokAccounts = config.accounts.filter { $0.provider == .grok }
        let desiredKeys = Set(grokAccounts.map(accountKey))

        for key in grokPollers.keys.filter({ !desiredKeys.contains($0) }) {
            grokPollers.removeValue(forKey: key)?.stop()
        }

        lazy var cached = GrokSnapshotCache.load(from: AppDelegate.grokCacheURL)

        for account in grokAccounts {
            let key = accountKey(account)
            guard grokPollers[key] == nil else { continue }
            let poller = GrokUsagePoller(
                grokHome: account.configDir,
                lastKnown: GrokSnapshotCache.snapshot(
                    grokHome: account.configDir, in: cached
                )
            ) { [weak self] state in
                if case .snapshot(let snapshot) = state {
                    try? GrokSnapshotCache.store(
                        snapshot,
                        grokHome: account.configDir,
                        at: AppDelegate.grokCacheURL
                    )
                }
                self?.refresh()
            }
            grokPollers[key] = poller
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
