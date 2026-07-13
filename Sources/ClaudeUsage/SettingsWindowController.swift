import Cocoa
import UsageCore

/// The settings window: register accounts, label them, install the tap, set
/// the warn threshold. Pure projection + explicit actions; all facts (tap
/// status, discovery) come from UsageCore.
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate {

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

        stack.addArrangedSubview(header("Accounts"))
        if app.config.accounts.isEmpty {
            stack.addArrangedSubview(dimmed("None registered yet."))
        }
        for (index, account) in app.config.accounts.enumerated() {
            stack.addArrangedSubview(accountRow(index: index, account: account))
        }

        let discovered = discoveredDirs()
        if !discovered.isEmpty {
            stack.addArrangedSubview(header("Discovered"))
            for dir in discovered {
                stack.addArrangedSubview(discoveredRow(dir))
            }
        }

        let addButton = NSButton(
            title: "Add Folder…", target: self, action: #selector(addFolder)
        )
        stack.addArrangedSubview(addButton)

        stack.addArrangedSubview(header("Warning threshold"))
        stack.addArrangedSubview(thresholdRow())

        stack.addArrangedSubview(header("Startup"))
        stack.addArrangedSubview(launchAtLoginRow())

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

    private func accountRow(index: Int, account: Account) -> NSView {
        let label = NSTextField(string: account.label)
        label.tag = index
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
        remove.tag = index
        installButton?.tag = index

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
        app.update { $0.accounts.remove(at: sender.tag) }
        reload()
    }

    @objc private func installTap(_ sender: NSButton) {
        let account = app.config.accounts[sender.tag]
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

    /// Relabelling: text fields carry the account index in their tag.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field.tag < app.config.accounts.count else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        app.update { $0.accounts[field.tag] = Account(
            label: text, configDir: $0.accounts[field.tag].configDir
        ) }
    }

    // MARK: - Small helpers

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private func header(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func dimmed(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func abbreviate(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
