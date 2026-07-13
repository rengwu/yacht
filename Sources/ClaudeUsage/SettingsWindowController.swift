import Cocoa
import UsageCore

/// The settings window: register accounts, label them, install the tap, set
/// the warn threshold. Pure projection + explicit actions; all facts (tap
/// status, discovery) come from UsageCore.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {

    private unowned let app: AppDelegate
    private let stack = NSStackView()

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
        stack.addArrangedSubview(caption("Dropdown row template"))
        stack.addArrangedSubview(rowTemplateRow())
        stack.addArrangedSubview(dimmed(
            "{name} {bar} {pct} {reset_at} (8:00pm) {reset_in} (1h 24m) — anything else is literal."
        ))

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

    private func thresholdText() -> String {
        "orange at \(Int(app.config.warnThreshold))%, red at \(Int(app.config.settings.criticalThreshold))%"
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

    /// Both editable fields land here, told apart by identifier. This notification
    /// can arrive *after* the click that removed the very account being edited —
    /// hence the rename by config directory, which finds nothing and does nothing
    /// when that account is gone.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let id = field.identifier?.rawValue else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)

        if id == "row-template" {
            // An emptied field means "give me the default back", not "render an
            // empty row" — a blank row would leave the account with no numbers at
            // all and no way to tell why.
            app.update { $0.rowTemplate = text.isEmpty ? AppSettings.defaultRowTemplate : text }
            field.stringValue = app.config.rowTemplate
            return
        }

        guard id.hasPrefix("label:"), !text.isEmpty else { return }
        let dir = URL(fileURLWithPath: String(id.dropFirst("label:".count)))
        app.update { $0.relabel(configDir: dir, to: text) }
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
