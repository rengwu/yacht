import Cocoa
import UsageCore

/// An "ⓘ" button that carries the text its popover should show — `NSButton` has
/// nowhere else to hold that per-instance.
private final class InfoButton: NSButton {
    var helpText: String = ""
}

/// The settings window: register accounts, label them, install the tap, set
/// the warn threshold. Pure projection + explicit actions; all facts (tap
/// status, discovery) come from UsageCore.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {

    private unowned let app: AppDelegate
    private let stack = NSStackView()
    /// The icon-preset popover, held onto so picking a preset can close it —
    /// unlike the info popovers, a pick is a completed action, not something to
    /// leave open until the next click elsewhere.
    private var iconPresetsPopover: NSPopover?
    /// The dozen preset buttons currently on screen, held onto so the Shuffle
    /// button can redraw them in place — a new random sample, same buttons —
    /// instead of tearing down and rebuilding the popover just to change what
    /// twelve glyphs it's showing.
    private var iconPresetButtons: [NSButton] = []

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Claude Usage Settings"
        window.center()
        super.init(window: window)
        window.delegate = self

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        window.contentView = stack
        reload()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Build

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // MARK: General

        stack.addArrangedSubview(header("General"))
        stack.addArrangedSubview(launchAtLoginRow())
        stack.addArrangedSubview(showMenuBarIconRow())
        stack.addArrangedSubview(caption("Menu bar icon"))
        stack.addArrangedSubview(menuBarIconRow())
        stack.addArrangedSubview(caption("Warning threshold"))
        stack.addArrangedSubview(thresholdRow())

        stack.addArrangedSubview(separator())

        // MARK: Accounts

        stack.addArrangedSubview(header("Accounts"))
        if app.config.accounts.isEmpty {
            stack.addArrangedSubview(dimmed("None registered yet."))
        }
        for account in app.config.accounts {
            stack.addArrangedSubview(accountRow(account: account))
        }

        let discovered = discoveredDirs()
        if !discovered.isEmpty {
            stack.addArrangedSubview(caption("Discovered"))
            for dir in discovered {
                stack.addArrangedSubview(discoveredRow(dir))
            }
        }

        let addButton = NSButton(
            title: "Add Claude Config Folder…", target: self, action: #selector(addFolder)
        )
        stack.addArrangedSubview(addButton)

        stack.addArrangedSubview(separator())

        // MARK: Advanced

        stack.addArrangedSubview(header("Advanced"))

        stack.addArrangedSubview(captionRow(
            "Menu bar text", variables: "{name} {bar} {pct} {pct_7d} {reset_at} {reset_in}"
        ))
        stack.addArrangedSubview(menuBarTemplateRow())

        stack.addArrangedSubview(captionRow("Menu bar text (no data yet)", variables: "{name}"))
        stack.addArrangedSubview(menuBarNoDataTemplateRow())

        stack.addArrangedSubview(caption("Menu bar separator"))
        stack.addArrangedSubview(menuBarSeparatorRow())

        stack.addArrangedSubview(caption("Max accounts shown in menu bar"))
        stack.addArrangedSubview(menuBarMaxAccountsRow())

        stack.addArrangedSubview(captionRow(
            "Dropdown row template", variables: "{name} {bar} {pct} {reset_at} {reset_in}"
        ))
        stack.addArrangedSubview(rowTemplateRow())

        window?.layoutIfNeeded()
    }

    /// Discovery minus what is already registered.
    private func discoveredDirs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let registered = Set(app.config.accounts.map { $0.configDir.standardizedFileURL.path })
        return Discovery.claudeConfigDirs(home: home)
            .filter { !registered.contains($0.standardizedFileURL.path) }
    }

    // MARK: - Rows

    /// Every control in the row carries the account's config directory — its
    /// identity — not its index. See the note on `AppConfig.remove`.
    private func accountRow(account: Account) -> NSView {
        let label = NSTextField(string: account.label)
        label.identifier = NSUserInterfaceItemIdentifier("label:" + account.configDir.path)
        label.delegate = self
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let path = dimmed(abbreviate(account.configDir))
        path.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let status = TapInstaller.detect(
            configDir: account.configDir, tapCommand: AppDelegate.tapCommand
        )
        let statusText: NSTextField
        var installButton: NSButton?
        switch status {
        case .installed:
            statusText = dimmed("tap installed ✓")
        case .notInstalled:
            statusText = dimmed("tap not installed")
            installButton = NSButton(title: "Install Tap", target: self, action: #selector(installTap(_:)))
        case .foreign(let command):
            statusText = dimmed("other status line: \(command)")
            installButton = NSButton(title: "Replace with Tap", target: self, action: #selector(installTap(_:)))
        }

        let remove = NSButton(title: "Remove", target: self, action: #selector(removeAccount(_:)))
        remove.identifier = NSUserInterfaceItemIdentifier(account.configDir.path)
        installButton?.identifier = NSUserInterfaceItemIdentifier(account.configDir.path)

        var views: [NSView] = [label, path, statusText]
        if let installButton { views.append(installButton) }
        views.append(remove)
        return row(views)
    }

    private func discoveredRow(_ dir: URL) -> NSView {
        let add = NSButton(title: "Add", target: self, action: #selector(addDiscovered(_:)))
        add.identifier = NSUserInterfaceItemIdentifier(dir.path)
        return row([dimmed(abbreviate(dir)), add])
    }

    private func thresholdRow() -> NSView {
        let slider = NSSlider(
            value: app.config.warnThreshold, minValue: 50, maxValue: 95,
            target: self, action: #selector(thresholdChanged(_:))
        )
        slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let label = dimmed(thresholdText())
        label.identifier = NSUserInterfaceItemIdentifier("threshold-label")
        return row([slider, label])
    }

    private func rowTemplateRow() -> NSView {
        let field = NSTextField(string: app.config.rowTemplate)
        field.identifier = NSUserInterfaceItemIdentifier("row-template")
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)  // as the row is
        field.widthAnchor.constraint(equalToConstant: 380).isActive = true
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetRowTemplate))
        return row([field, reset])
    }

    /// The checkbox is set from the system's *live* state, not a stored flag —
    /// so if registration ever silently fails, the box reflects the failure
    /// rather than a hopeful intention.
    private func launchAtLoginRow() -> NSView {
        let check = NSButton(
            checkboxWithTitle: "Launch at login",
            target: self, action: #selector(toggleLaunchAtLogin(_:))
        )
        check.state = LaunchAtLogin.isEnabled ? .on : .off
        return row([check])
    }

    /// Unchecking this is not absolute — `render` shows the icon anyway if every
    /// account's text has gone empty, so the status item is never unclickable.
    /// See the comment on `AppSettings.showMenuBarIcon`.
    private func showMenuBarIconRow() -> NSView {
        let check = NSButton(
            checkboxWithTitle: "Show menu bar icon",
            target: self, action: #selector(toggleShowMenuBarIcon(_:))
        )
        check.state = app.config.showMenuBarIcon ? .on : .off
        return row([check])
    }

    private func thresholdText() -> String {
        "orange at \(Int(app.config.warnThreshold))%, red at \(Int(app.config.settings.criticalThreshold))%"
    }

    /// The default glyph, plus a much larger pool than the popover ever shows
    /// at once — `showMenuBarIconPresets` samples `presetsShown` of these at
    /// random on every open, so the grid is never the same list twice. Grouped
    /// by theme rather than picked at random itself: AI/hardware, time (the
    /// moon phases echo ◐ directly), usage/metrics, the uncanny/mystical angle
    /// on what a model actually is, learning, thinking, plain fun, expressions,
    /// body/communication, people, animals, nature/food, alerts/signals, and
    /// objects. A starting point regardless — the field beside it takes
    /// anything.
    private static let menuBarIconPool: [String] = ["◐"] + [
        "🤖", "👾", "🧠", "🦾", "👽", "🛸", "💻", "🖥️", "⌨️",
        "⏳", "⌛", "⏱️", "⏰", "🕰️", "⏲️", "🌙", "🌗", "🌘", "🌑",
        "⚡", "🔋", "🪫",   "🌡️", "📈", "📉", "📊", "🧮",
        "🔮", "✨", "🪄", "🌀", "💫", "🪐", "🌠", "☄️", "🛰️",
        "📚", "🎓", "🔬", "🧪", "💡", "🧩", "🤔","🧃", "🌪️", "🔄", "🎡",
        "🎉", "🎲", "🌈", "🎨",
        // expressions
        "😎", "🤓", "🧐", "🤤",
        // body / communication
        "👀", "🫀", "✍️", "💭", "💬", "🗨️", "🗣️",
        // people
        "💁", "👨‍🍳", "👩‍🔬", "🧞‍♂️", "👯",
        // animals
        "🦧", "🐎", "🦮", "🐥", "🐸", "🦦", "🦞", "🐌",
        // nature / food
        "🌱", "☘️", "🍯", "🍼", "🍕", "🍞",
        // alerts / signals
        "🚨", "🚦", "🛎️", "🔔", "📶", "✳️", "🏁",
        // objects
        "🚀", "🔥", "🪩", "🧨", "💎", "💣", "🗿", "🚬", "🚰", "🫪",
    ]

    /// How many of the pool the popover grid holds at once, laid out `columns`
    /// wide. 12 sits comfortably in the 8–16 range a popover can hold without
    /// feeling either sparse or crowded.
    private static let presetsShown = 12
    private static let presetsColumns = 4

    private func menuBarIconRow() -> NSView {
        let field = NSTextField(string: app.config.menuBarIcon)
        field.identifier = NSUserInterfaceItemIdentifier("menubar-icon")
        field.delegate = self
        field.alignment = .center
        field.font = .systemFont(ofSize: 14)
        field.widthAnchor.constraint(equalToConstant: 36).isActive = true
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetMenuBarIcon))
        let presets = NSButton(
            title: "Presets…", target: self, action: #selector(showMenuBarIconPresets(_:))
        )
        return row([field, reset, presets])
    }

    /// A 3x4 grid of preset buttons in a popover, rather than a permanent row —
    /// a dozen buttons sitting in the window at all times outweighs how often
    /// they're actually used, which is once, maybe twice. The grid draws a
    /// random dozen when it opens, same as before, but a Shuffle button below
    /// it — not the act of opening — is now what redraws it: reopening the
    /// popover repeatedly used to be the only way to see a different set,
    /// which meant closing it (a click anywhere else) just to try again. Each
    /// button's identifier carries the glyph itself, the same way an account
    /// row's controls carry its config directory — the value the click means
    /// to set, not a position to look it up from.
    @objc private func showMenuBarIconPresets(_ sender: NSButton) {
        let buttons = (0..<Self.presetsShown).map { _ -> NSButton in
            let button = NSButton(title: "", target: self, action: #selector(pickMenuBarIcon(_:)))
            button.font = .systemFont(ofSize: 16)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return button
        }
        iconPresetButtons = buttons
        reshuffleIconPresets()

        let rows = stride(from: 0, to: buttons.count, by: Self.presetsColumns).map { start -> NSStackView in
            let end = min(start + Self.presetsColumns, buttons.count)
            let buttonRow = NSStackView(views: Array(buttons[start..<end]))
            buttonRow.spacing = 4
            return buttonRow
        }
        let grid = NSStackView(views: rows)
        grid.orientation = .vertical
        grid.spacing = 4

        let shuffle = NSButton(title: "Shuffle", target: self, action: #selector(shuffleMenuBarIconPresets))

        let content = NSStackView(views: [grid, shuffle])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
        ])

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        iconPresetsPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    /// Draws a fresh random dozen and pushes them onto `iconPresetButtons` in
    /// place. `shuffled()` on the whole pool before taking a `prefix` gives
    /// both a random subset *and* a random order in one step.
    private func reshuffleIconPresets() {
        let picks = Self.menuBarIconPool.shuffled().prefix(iconPresetButtons.count)
        for (button, icon) in zip(iconPresetButtons, picks) {
            button.title = icon
            button.identifier = NSUserInterfaceItemIdentifier(icon)
        }
    }

    @objc private func shuffleMenuBarIconPresets() {
        reshuffleIconPresets()
    }

    /// Mirrors `syncMenuBarMaxAccountsControls`: pushes the current value to the
    /// field wherever it is in the stack, so a preset click updates it in place.
    private func syncMenuBarIconField() {
        for case let field as NSTextField in stack.arrangedSubviews
            .compactMap({ ($0 as? NSStackView)?.arrangedSubviews }).joined()
        where field.identifier?.rawValue == "menubar-icon" {
            field.stringValue = app.config.menuBarIcon
        }
    }

    private func menuBarTemplateRow() -> NSView {
        let field = NSTextField(string: app.config.menuBarTemplate)
        field.identifier = NSUserInterfaceItemIdentifier("menubar-template")
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetMenuBarTemplate))
        return row([field, reset])
    }

    private func menuBarNoDataTemplateRow() -> NSView {
        let field = NSTextField(string: app.config.menuBarNoDataTemplate)
        field.identifier = NSUserInterfaceItemIdentifier("menubar-nodata-template")
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let reset = NSButton(
            title: "Reset", target: self, action: #selector(resetMenuBarNoDataTemplate)
        )
        return row([field, reset])
    }

    /// No width-based fallback and no font distinct from its own row: a separator
    /// is typically one or two glyphs, not a template, so it gets a narrow field.
    private func menuBarSeparatorRow() -> NSView {
        let field = NSTextField(string: app.config.menuBarSeparator)
        field.identifier = NSUserInterfaceItemIdentifier("menubar-separator")
        field.delegate = self
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let reset = NSButton(title: "Reset", target: self, action: #selector(resetMenuBarSeparator))
        return row([field, reset])
    }

    /// A typed number and the stepper stay in sync (`syncMenuBarMaxAccountsControls`
    /// pushes to whichever one didn't just change) — a stepper alone has no visible
    /// number to type into, and a field alone has no click-to-nudge.
    private func menuBarMaxAccountsRow() -> NSView {
        let field = NSTextField(string: "\(app.config.menuBarMaxAccounts)")
        field.identifier = NSUserInterfaceItemIdentifier("menubar-max-accounts-field")
        field.delegate = self
        field.alignment = .center
        field.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let stepper = NSStepper()
        stepper.identifier = NSUserInterfaceItemIdentifier("menubar-max-accounts-stepper")
        stepper.minValue = 0
        stepper.maxValue = 20
        stepper.integerValue = app.config.menuBarMaxAccounts
        stepper.target = self
        stepper.action = #selector(menuBarMaxAccountsChanged(_:))

        return row([field, stepper, dimmed("0 = no limit")])
    }

    /// Pushes the current value to both controls, wherever they are in the stack —
    /// mirrors how `thresholdChanged` updates its label in place, so neither
    /// control gets torn out from under an in-progress click or keystroke.
    private func syncMenuBarMaxAccountsControls() {
        let n = app.config.menuBarMaxAccounts
        for view in stack.arrangedSubviews.compactMap({ ($0 as? NSStackView)?.arrangedSubviews }).joined() {
            if let field = view as? NSTextField, field.identifier?.rawValue == "menubar-max-accounts-field" {
                field.integerValue = n
            }
            if let stepper = view as? NSStepper,
               stepper.identifier?.rawValue == "menubar-max-accounts-stepper" {
                stepper.integerValue = n
            }
        }
    }

    // MARK: - Actions

    @objc private func addDiscovered(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        register(URL(fileURLWithPath: path))
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true  // config dirs are dotfiles
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Register"
        if panel.runModal() == .OK, let url = panel.url {
            register(url)
        }
    }

    private func register(_ dir: URL) {
        var label = dir.lastPathComponent
        if label.hasPrefix(".") { label.removeFirst() }
        app.update { $0.accounts.append(Account(label: label, configDir: dir)) }
        reload()
    }

    @objc private func removeAccount(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        app.update { $0.remove(configDir: URL(fileURLWithPath: path)) }
        reload()
    }

    @objc private func installTap(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue,
              let account = app.config.account(configDir: URL(fileURLWithPath: path))
        else { return }
        do {
            try app.installTap(for: account)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not install the tap"
            alert.informativeText = error is TapInstallerError
                ? "\(abbreviate(account.configDir))/settings.json could not be parsed, so it was left untouched. Fix the file and try again."
                : "\(error)"
            alert.runModal()
        }
        reload()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSButton) {
        do {
            try LaunchAtLogin.setEnabled(sender.state == .on)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
        // Snap the checkbox back to what the system actually holds now — whether
        // the change took or not, the box tells the truth.
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func thresholdChanged(_ sender: NSSlider) {
        app.update { $0.warnThreshold = sender.doubleValue.rounded() }
        // Update the caption in place; a full reload would tear the slider out
        // from under the drag.
        for case let text as NSTextField in stack.arrangedSubviews
            .compactMap({ ($0 as? NSStackView)?.arrangedSubviews }).joined()
        where text.identifier?.rawValue == "threshold-label" {
            text.stringValue = thresholdText()
        }
    }

    @objc private func toggleShowMenuBarIcon(_ sender: NSButton) {
        app.update { $0.showMenuBarIcon = sender.state == .on }
    }

    @objc private func pickMenuBarIcon(_ sender: NSButton) {
        guard let icon = sender.identifier?.rawValue else { return }
        app.update { $0.menuBarIcon = icon }
        syncMenuBarIconField()
        iconPresetsPopover?.close()
        iconPresetsPopover = nil
        iconPresetButtons = []
    }

    @objc private func resetMenuBarIcon() {
        app.update { $0.menuBarIcon = AppSettings.defaultMenuBarIcon }
        syncMenuBarIconField()
    }

    @objc private func resetMenuBarTemplate() {
        app.update { $0.menuBarTemplate = AppSettings.defaultMenuBarTemplate }
        reload()
    }

    @objc private func resetMenuBarNoDataTemplate() {
        app.update { $0.menuBarNoDataTemplate = AppSettings.defaultMenuBarNoDataTemplate }
        reload()
    }

    @objc private func resetMenuBarSeparator() {
        app.update { $0.menuBarSeparator = AppSettings.defaultMenuBarSeparator }
        reload()
    }

    @objc private func menuBarMaxAccountsChanged(_ sender: NSStepper) {
        app.update { $0.menuBarMaxAccounts = sender.integerValue }
        syncMenuBarMaxAccountsControls()
    }

    /// Closing the window with a label field still being edited would otherwise
    /// drop the pending rename — `controlTextDidEndEditing` never fires because
    /// editing never "ended." Resigning first responder ends it, committing the
    /// edit through the same path. This is why no Save button is needed.
    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    @objc private func resetRowTemplate() {
        app.update { $0.rowTemplate = AppSettings.defaultRowTemplate }
        reload()
    }

    /// Every editable field lands here, told apart by identifier. This
    /// notification can arrive *after* the click that removed the very account
    /// being edited — hence the rename by config directory, which finds nothing
    /// and does nothing when that account is gone.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }

        // Not trimmed: unlike the templates below, whitespace *is* the separator's
        // content — a lone space is a legitimate, common choice, and trimming it
        // would silently turn "a space" into "nothing" without the user asking.
        // Empty is also left alone here, for the same reason: pressing accounts
        // together with no separator at all is a real choice, not a mistake.
        if id == "menubar-separator" {
            app.update { $0.menuBarSeparator = field.stringValue }
            return
        }

        let text = field.stringValue.trimmingCharacters(in: .whitespaces)

        // An emptied template field means "give me the default back," not "render
        // an empty row" — a blank template would leave the account with nothing
        // shown and no way to tell why.
        switch id {
        case "row-template":
            app.update { $0.rowTemplate = text.isEmpty ? AppSettings.defaultRowTemplate : text }
            field.stringValue = app.config.rowTemplate
        case "menubar-template":
            app.update { $0.menuBarTemplate = text.isEmpty ? AppSettings.defaultMenuBarTemplate : text }
            field.stringValue = app.config.menuBarTemplate
        case "menubar-nodata-template":
            app.update {
                $0.menuBarNoDataTemplate = text.isEmpty ? AppSettings.defaultMenuBarNoDataTemplate : text
            }
            field.stringValue = app.config.menuBarNoDataTemplate
        case "menubar-icon":
            // `prefix(1)` on a `String` takes one grapheme cluster, not one UTF-16
            // unit — an emoji built from several scalars (a flag, a skin-tone
            // modifier) still comes through whole rather than split mid-glyph.
            app.update {
                $0.menuBarIcon = text.isEmpty ? AppSettings.defaultMenuBarIcon : String(text.prefix(1))
            }
            field.stringValue = app.config.menuBarIcon
        case "menubar-max-accounts-field":
            // Anything that isn't a number in range — blank, "abc", "-3" — settles
            // back on the current value rather than erroring or going negative.
            let n = max(0, min(20, Int(text) ?? app.config.menuBarMaxAccounts))
            app.update { $0.menuBarMaxAccounts = n }
            syncMenuBarMaxAccountsControls()
        default:
            guard id.hasPrefix("label:"), !text.isEmpty else { return }
            let dir = URL(fileURLWithPath: String(id.dropFirst("label:".count)))
            app.update { $0.relabel(configDir: dir, to: text) }
        }
    }

    // MARK: - Small helpers

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    /// A section title — the only bold text in the window, so "General",
    /// "Accounts", and "Advanced" read as the three groupings and nothing inside
    /// them competes for that weight.
    private func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    /// A field's name, sitting above its control within a section — lighter than
    /// a section header, since it isn't one.
    private func caption(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    /// A caption with a small "ⓘ" beside it that reveals `variables` in a popover
    /// on click, under a bold "Available variables" title — this is the
    /// template's token list, useful once and then just visual noise if left as
    /// a permanent line under the field.
    private func captionRow(_ text: String, variables: String) -> NSView {
        let button = InfoButton()
        button.image = NSImage(
            systemSymbolName: "info.circle", accessibilityDescription: "More info"
        )
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.helpText = variables
        button.target = self
        button.action = #selector(showHelp(_:))
        return row([caption(text), button])
    }

    @objc private func showHelp(_ sender: InfoButton) {
        let title = NSTextField(labelWithString: "Available variables")
        title.font = .boldSystemFont(ofSize: 12)

        let body = NSTextField(wrappingLabelWithString: sender.helpText)
        body.font = .systemFont(ofSize: 12)
        body.preferredMaxLayoutWidth = 260

        let content = NSStackView(views: [title, body])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 4
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            // The width has to be pinned explicitly, not just capped via
            // preferredMaxLayoutWidth: that only bounds how a wrapping label's
            // *height* is computed, so without a real width constraint on `body`
            // neither it, the stack around it, nor the popover built from that
            // has any way to settle on a size — it collapses to a sliver instead
            // of wrapping at 260pt.
            body.widthAnchor.constraint(equalToConstant: 260),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])

        let controller = NSViewController()
        controller.view = container
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient  // dismisses on the next click elsewhere
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    private func dimmed(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    /// A full-width rule between sections. Constrained explicitly: the stack
    /// itself sizes to its widest arranged subview rather than to the window, so
    /// a stock `NSBox` separator — which has no intrinsic width — would collapse
    /// to nothing without one.
    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 568).isActive = true
        return box
    }

    private func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
