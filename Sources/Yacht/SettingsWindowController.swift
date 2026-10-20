import Cocoa
import UsageCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private unowned let app: AppDelegate
    private let settingsStack = NSStackView()
    private let table = AccountsTableView()
    private let removeButton = NSButton(title: "−", target: nil, action: nil)
    private let folderPath = NSTextField(labelWithString: "")
    private let tapButton = NSButton(title: "Install Tap…", target: nil, action: nil)
    private var accountsHeight: NSLayoutConstraint?
    private let thresholdCaption = NSTextField(labelWithString: "")
    private let preview = StatusContentView()
    private var addController: AddAccountController?
    private var knownWindows: [String: [UsageWindow]] = [:]
    private let dragType = NSPasteboard.PasteboardType("local.yacht.account-folder")

    init(app: AppDelegate) {
        self.app = app
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = AppDelegate.isDemo ? "Yacht Settings — Demo" : "Yacht Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
        fitWindowToContents()
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let content = window?.contentView else { return }
        let stack = settingsStack
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
        ])
        stack.addArrangedSubview(header("Accounts"))
        stack.addArrangedSubview(buildAccounts())
        let orderHint = NSTextField(labelWithString: "Drag accounts to reorder. Click a label to rename it.")
        orderHint.textColor = .secondaryLabelColor
        orderHint.font = .systemFont(ofSize: 11)
        stack.addArrangedSubview(orderHint)
        stack.addArrangedSubview(header("Display"))
        let display = NSStackView()
        display.orientation = .vertical
        display.alignment = .leading
        display.spacing = 12
        display.addArrangedSubview(setting("Show accounts as", control: segments(
            ["Icons", "Labels"], selected: app.config.display.accounts == .icons ? 0 : 1,
            action: #selector(changeAccountStyle(_:))
        )))
        display.addArrangedSubview(setting("Percentages", control: segments(
            ["Remaining", "Used"], selected: app.config.display.percentages == .remaining ? 0 : 1,
            action: #selector(changePercentages(_:))
        )))
        display.addArrangedSubview(setting("Reset times", control: segments(
            ["Countdown", "Exact time"], selected: app.config.display.resets == .countdown ? 0 : 1,
            action: #selector(changeResets(_:))
        )))
        let slider = NSSlider(value: app.config.warnThreshold, minValue: 50, maxValue: 95,
                              target: self, action: #selector(changeThreshold(_:)))
        slider.isContinuous = true
        slider.setAccessibilityLabel("Warning threshold, percent used")
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        thresholdCaption.font = .systemFont(ofSize: 11)
        thresholdCaption.textColor = .secondaryLabelColor
        display.addArrangedSubview(setting("Warning threshold", control: row([slider, thresholdCaption])))
        let previewScroll = NSScrollView()
        previewScroll.documentView = preview
        previewScroll.hasHorizontalScroller = true
        previewScroll.autohidesScrollers = true
        previewScroll.widthAnchor.constraint(equalToConstant: 440).isActive = true
        previewScroll.heightAnchor.constraint(equalToConstant: 44).isActive = true
        display.addArrangedSubview(setting("Menu bar preview", control: previewScroll))
        stack.addArrangedSubview(display)
        stack.addArrangedSubview(header("General"))
        let login = NSButton(checkboxWithTitle: "Launch at login", target: self,
                             action: #selector(toggleLogin(_:)))
        login.state = !AppDelegate.isDemo && LaunchAtLogin.isEnabled ? .on : .off
        login.isEnabled = !AppDelegate.isDemo && LaunchAtLogin.isSupported
        login.toolTip = AppDelegate.isDemo ? "Disabled in offline demo" : "Requires a bundled Yacht.app"
        stack.addArrangedSubview(login)
        if app.config.accounts.contains(where: { $0.provider == .codex }) && app.resolvedCodexBinaryURL == nil {
            stack.addArrangedSubview(NSButton(title: "Locate Codex executable…", target: self,
                                             action: #selector(locateCodex)))
        }
        refreshPreview()
    }

    private func fitWindowToContents() {
        guard let window else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let size = NSSize(width: 660, height: ceil(settingsStack.fittingSize.height) + 36)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    private func buildAccounts() -> NSView {
        table.headerView = AccountsHeaderView(frame: NSRect(x: 0, y: 0, width: 620, height: 24))
        table.cornerView = NSTableHeaderView()
        table.style = .plain
        table.rowHeight = 36
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = false
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("move", "", 28.0), ("account", "Account", 308.0),
                                    ("provider", "Provider", 130.0), ("window", "Menu bar", 130.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            let heading = NSMutableAttributedString(attributedString: column.headerCell.attributedStringValue)
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = 8
            paragraph.headIndent = 8
            paragraph.tailIndent = -8
            heading.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: heading.length))
            column.headerCell.attributedStringValue = heading
            column.width = width
            column.minWidth = id == "move" ? 28 : (id == "provider" ? 90 : 120)
            column.resizingMask = id == "move" ? [] : [.userResizingMask, .autoresizingMask]
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Accounts in display order")
        table.registerForDraggedTypes([dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        accountsHeight = scroll.heightAnchor.constraint(equalToConstant: 24 + 36 * CGFloat(max(1, min(6, app.config.accounts.count))))
        accountsHeight?.isActive = true

        let group = NSBox()
        group.boxType = .custom
        group.borderWidth = 0
        group.cornerRadius = 12
        group.fillColor = .quaternaryLabelColor
        group.isTransparent = false
        group.contentViewMargins = .zero
        group.wantsLayer = true
        group.layer?.cornerRadius = 12
        group.layer?.masksToBounds = true
        group.widthAnchor.constraint(equalToConstant: 620).isActive = true
        let content = group.contentView!

        let footer = NSBox()
        footer.boxType = .custom
        footer.borderWidth = 0
        footer.fillColor = .quaternaryLabelColor
        footer.isTransparent = false
        footer.contentViewMargins = .zero
        footer.translatesAutoresizingMaskIntoConstraints = false
        let add = NSButton(title: "+", target: self, action: #selector(addAccount))
        add.setAccessibilityLabel("Add account")
        removeButton.target = self
        removeButton.action = #selector(removeAccount)
        removeButton.setAccessibilityLabel("Remove selected account")
        removeButton.isEnabled = false
        for (button, symbol) in [(add, "plus"), (removeButton, "minus")] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: button.title)
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.widthAnchor.constraint(equalToConstant: 24).isActive = true
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        tapButton.target = self
        tapButton.action = #selector(installTap(_:))
        tapButton.controlSize = .small
        tapButton.bezelStyle = .inline
        tapButton.isHidden = true
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        folderPath.font = .systemFont(ofSize: 11)
        folderPath.textColor = .secondaryLabelColor
        folderPath.lineBreakMode = .byTruncatingMiddle
        folderPath.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        folderPath.setAccessibilityLabel("Selected account folder")
        let controls = row([add, divider, removeButton, tapButton, spacer, folderPath])
        controls.spacing = 4
        controls.translatesAutoresizingMaskIntoConstraints = false
        footer.contentView!.addSubview(controls)
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        content.addSubview(footer)
        content.addSubview(separator)
        NSLayoutConstraint.activate([
            group.heightAnchor.constraint(equalTo: scroll.heightAnchor, constant: 30),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.topAnchor.constraint(equalTo: scroll.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 30),
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            controls.leadingAnchor.constraint(equalTo: footer.contentView!.leadingAnchor, constant: 8),
            controls.trailingAnchor.constraint(equalTo: footer.contentView!.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: footer.contentView!.centerYAnchor),
        ])
        updateAccountFooter()
        return group
    }

    func refreshPreview() {
        preview.update(app.presentation, style: app.config.display.accounts)
        let remaining = app.config.display.percentages == .remaining
        let warn = remaining ? 100 - app.config.warnThreshold : app.config.warnThreshold
        let critical = remaining ? 100 - app.config.settings.criticalThreshold : app.config.settings.criticalThreshold
        func number(_ n: Double) -> String { n == n.rounded() ? String(Int(n)) : String(format: "%.1f", n) }
        thresholdCaption.stringValue = "orange at \(number(warn))%, red at \(number(critical))% \(remaining ? "left" : "used")"
        let reported = app.states.reduce(into: [String: [UsageWindow]]()) {
            $0[$1.account.configDir.path] = $1.snapshot?.rows.map(\.window) ?? []
        }
        if reported != knownWindows {
            knownWindows = reported
            if table.numberOfColumns > 3 {
                table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<min(table.numberOfRows, app.config.accounts.count)),
                                 columnIndexes: IndexSet(integer: 3))
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { app.config.accounts.count }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row index: Int) -> NSView? {
        guard app.config.accounts.indices.contains(index) else { return nil }
        let account = app.config.accounts[index]
        switch column?.identifier.rawValue {
        case "move":
            let cell = NSTableCellView()
            let icon = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Drag to reorder")!)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.contentTintColor = .secondaryLabelColor
            cell.imageView = icon
            cell.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 11),
                icon.heightAnchor.constraint(equalToConstant: 11),
            ])
            return cell
        case "account":
            let cell = AccountNameCell(account: account)
            cell.textField?.delegate = self
            return cell
        case "provider":
            let container = NSTableCellView()
            let label = NSTextField(labelWithString: account.provider.displayName)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 13)
            container.textField = label
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            return container
        case "window":
            let popup = AccountWindowPopup()
            popup.isBordered = false
            popup.font = .systemFont(ofSize: 13)
            popup.accountPath = account.configDir
            let state = app.states.first { $0.account.configDir == account.configDir }
            let primary = state?.snapshot?.primary ?? account.provider.defaultPrimaryWindow
            let selected = account.menuBarWindow ?? primary
            var windows = state?.snapshot?.rows.map(\.window) ?? []
            if windows.isEmpty { windows = [primary] }
            if !windows.contains(selected) { windows.append(selected) }
            popup.windows = windows
            popup.addItems(withTitles: windows.map { $0 == .weekly ? "Weekly" : $0.defaultLabel } + ["Off"])
            popup.selectItem(at: account.showInMenuBar ? (windows.firstIndex(of: selected) ?? 0) : windows.count)
            popup.target = self
            popup.action = #selector(changeWindow(_:))
            popup.setAccessibilityLabel("Menu bar window for \(account.label)")
            popup.toolTip = "Off hides only this menu bar figure; the dropdown still shows all usage."
            return AccountWindowCell(popup: popup)
        default: return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateAccountFooter()
    }

    private var selectedAccount: Account? {
        app.config.accounts.indices.contains(table.selectedRow) ? app.config.accounts[table.selectedRow] : nil
    }

    private func updateAccountFooter() {
        let account = selectedAccount
        removeButton.isEnabled = account != nil
        folderPath.stringValue = account.map { abbreviate($0.configDir) } ?? ""
        folderPath.toolTip = account?.configDir.path
        tapButton.isHidden = true
        tapButton.identifier = nil
        if let account, account.provider.usesTap, !AppDelegate.isDemo {
            let status = TapInstaller.detect(configDir: account.configDir, tapCommand: AppDelegate.tapCommand)
            if status != .installed {
                tapButton.isHidden = false
                tapButton.identifier = NSUserInterfaceItemIdentifier(account.configDir.path)
                tapButton.title = "Install Tap…"
                if case .foreign = status { tapButton.title = "Replace Tap…" }
            }
        }
    }

    private func reloadAccounts(selecting path: URL?) {
        table.reloadData()
        accountsHeight?.constant = 24 + 36 * CGFloat(max(1, min(6, app.config.accounts.count)))
        if let path, let index = app.config.accounts.firstIndex(where: { $0.configDir == path }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            table.deselectAll(nil)
        }
        updateAccountFooter()
        fitWindowToContents()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard app.config.accounts.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(app.config.accounts[row].configDir.path, forType: dragType)
        return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === table else { return [] }
        table.setDropRow(row, dropOperation: .above)
        return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let path = info.draggingPasteboard.string(forType: dragType) else { return false }
        window?.makeFirstResponder(nil)
        let directory = URL(fileURLWithPath: path)
        app.update { $0.moveAccount(configDir: directory, before: row) }
        reloadAccounts(selecting: directory)
        return true
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? GrowingAccountLabelField else { return }
        let index = table.row(for: field)
        if index >= 0 {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let path = field.identifier?.rawValue else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path)
        if value.isEmpty { field.stringValue = app.config.account(configDir: url)?.label ?? "" }
        else {
            field.stringValue = value
            app.update { $0.relabel(configDir: url, to: value) }
            let index = table.row(for: field)
            if index >= 0 {
                table.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 3))
            }
        }
    }
    func windowWillClose(_ notification: Notification) { window?.makeFirstResponder(nil) }

    @objc private func changeWindow(_ sender: AccountWindowPopup) {
        guard let index = app.config.accounts.firstIndex(where: { $0.configDir == sender.accountPath }) else { return }
        table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        app.update {
            $0.accounts[index].showInMenuBar = sender.indexOfSelectedItem < sender.windows.count
            if $0.accounts[index].showInMenuBar {
                $0.accounts[index].menuBarWindow = sender.windows[sender.indexOfSelectedItem]
            }
        }
    }
    @objc private func changeAccountStyle(_ sender: NSSegmentedControl) {
        app.update { $0.display.accounts = sender.selectedSegment == 0 ? .icons : .labels }
    }
    @objc private func changePercentages(_ sender: NSSegmentedControl) {
        app.update { $0.display.percentages = sender.selectedSegment == 0 ? .remaining : .used }
    }
    @objc private func changeResets(_ sender: NSSegmentedControl) {
        app.update { $0.display.resets = sender.selectedSegment == 0 ? .countdown : .exactTime }
    }
    @objc private func changeThreshold(_ sender: NSSlider) {
        app.update { $0.warnThreshold = sender.doubleValue.rounded() }
    }
    @objc private func toggleLogin(_ sender: NSButton) {
        guard !AppDelegate.isDemo else { return }
        do { try LaunchAtLogin.setEnabled(sender.state == .on) }
        catch { NSAlert(error: error).runModal() }
        sender.state = LaunchAtLogin.isEnabled ? .on : .off
    }
    @objc private func locateCodex() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.title = "Choose the Codex executable"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.app.update { $0.codexBinaryPath = url.path }
        }
    }
    @objc private func installTap(_ sender: NSButton) {
        guard !AppDelegate.isDemo, let path = sender.identifier?.rawValue,
              let account = app.config.account(configDir: URL(fileURLWithPath: path)) else { return }
        if case .foreign = TapInstaller.detect(configDir: account.configDir, tapCommand: AppDelegate.tapCommand) {
            let alert = NSAlert()
            alert.messageText = "Replace this account’s status line?"
            alert.informativeText = "Yacht will replace the existing status-line command with its usage tap."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do { try app.installTap(for: account) }
        catch { NSAlert(error: error).runModal() }
        updateAccountFooter()
    }
    @objc private func removeAccount() {
        window?.makeFirstResponder(nil)
        guard app.config.accounts.indices.contains(table.selectedRow) else { return }
        let index = table.selectedRow
        let account = app.config.accounts[index]
        app.update { $0.remove(configDir: account.configDir) }
        let next = app.config.accounts.isEmpty ? nil : app.config.accounts[min(index, app.config.accounts.count - 1)].configDir
        reloadAccounts(selecting: next)
    }
    @objc private func addAccount() {
        guard let window else { return }
        window.makeFirstResponder(nil)
        let previousSelection = selectedAccount?.configDir
        let existingPaths = Set(app.config.accounts.map(\.configDir))
        let controller = AddAccountController(app: app) { [weak self] in
            guard let self else { return }
            let added = self.app.config.accounts.first { !existingPaths.contains($0.configDir) }
            self.reloadAccounts(selecting: added?.configDir ?? previousSelection)
            self.addController = nil
        }
        addController = controller
        window.beginSheet(controller.window!)
    }

    private func segments(_ labels: [String], selected: Int, action: Selector) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: action)
        control.selectedSegment = selected
        return control
    }
    private func setting(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 160).isActive = true
        return row([label, control])
    }
}

private final class AccountsTableView: NSTableView {
    // Label fields should edit on the first click, without the table's
    // deferred focus used for row selection and double-click actions.
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if let field = responder as? NSTextField, field.isEditable, field.isEnabled,
           row(for: field) >= 0 {
            return true
        }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}

private final class AccountWindowPopup: NSPopUpButton {
    var accountPath = URL(fileURLWithPath: "/")
    var windows: [UsageWindow] = []
}

final class AddAccountController: NSWindowController, NSTextFieldDelegate {
    private unowned let app: AppDelegate
    private let completion: () -> Void
    private let provider = NSPopUpButton()
    private let folder = NSTextField()
    private let label = NSTextField()
    private let found = NSStackView()
    private let validation = NSTextField(labelWithString: "")
    private let add = NSButton(title: "Add Account", target: nil, action: nil)

    init(app: AppDelegate, completion: @escaping () -> Void) {
        self.app = app
        self.completion = completion
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Add Account"
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -16),
        ])
        stack.addArrangedSubview(header("Add Account"))
        provider.addItems(withTitles: Provider.allCases.map(\.displayName))
        provider.target = self
        provider.action = #selector(providerChanged)
        stack.addArrangedSubview(field("Provider", provider))
        folder.placeholderString = "Account folder"
        folder.setAccessibilityLabel("Account folder")
        folder.delegate = self
        folder.widthAnchor.constraint(equalToConstant: 270).isActive = true
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        stack.addArrangedSubview(field("Folder", row([folder, choose])))
        label.placeholderString = "Work"
        label.setAccessibilityLabel("Account label")
        label.delegate = self
        label.widthAnchor.constraint(equalToConstant: 270).isActive = true
        stack.addArrangedSubview(field("Label", label))
        let help = NSTextField(wrappingLabelWithString:
            "Choose an existing profile signed in through the provider’s CLI. Use a separate folder for each account. Claude profiles offer an optional usage tap after adding.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.widthAnchor.constraint(equalToConstant: 452).isActive = true
        stack.addArrangedSubview(help)
        stack.addArrangedSubview(header("Found on this Mac"))
        found.orientation = .vertical
        found.alignment = .leading
        found.spacing = 4
        let discoveryScroll = NSScrollView()
        discoveryScroll.documentView = found
        discoveryScroll.hasVerticalScroller = true
        discoveryScroll.widthAnchor.constraint(equalToConstant: 452).isActive = true
        discoveryScroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(discoveryScroll)
        validation.font = .systemFont(ofSize: 11)
        validation.textColor = .secondaryLabelColor
        stack.addArrangedSubview(validation)
        add.target = self
        add.action = #selector(submit)
        add.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let spacer = NSView()
        let buttons = row([spacer, cancel, add])
        stack.addArrangedSubview(buttons)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        providerChanged()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private var selectedProvider: Provider { Provider.allCases[provider.indexOfSelectedItem] }
    private var selectedURL: URL {
        URL(fileURLWithPath: NSString(string: folder.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath).standardizedFileURL
    }
    private func field(_ name: String, _ control: NSView) -> NSView {
        let title = NSTextField(labelWithString: name)
        title.widthAnchor.constraint(equalToConstant: 62).isActive = true
        return row([title, control])
    }
    @objc private func providerChanged() {
        folder.stringValue = ""
        label.stringValue = ""
        found.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories: [URL]
        if AppDelegate.isDemo { directories = [] }
        else {
            switch selectedProvider {
            case .claude: directories = Discovery.claudeConfigDirs(home: home)
            case .codex: directories = Discovery.codexConfigDirs(home: home)
            case .grok: directories = Discovery.grokConfigDirs(home: home)
            case .kimi: directories = Discovery.kimiConfigDirs(home: home)
            }
        }
        for directory in directories {
            let text = NSTextField(labelWithString: abbreviate(directory))
            text.lineBreakMode = .byTruncatingMiddle
            text.widthAnchor.constraint(equalToConstant: 270).isActive = true
            if let account = app.config.account(configDir: directory) {
                found.addArrangedSubview(row([text, NSTextField(labelWithString: "Added as \(account.label)")]))
            } else {
                let use = NSButton(title: "Use", target: self, action: #selector(useFolder(_:)))
                use.identifier = NSUserInterfaceItemIdentifier(directory.path)
                found.addArrangedSubview(row([text, use]))
            }
        }
        if directories.isEmpty { found.addArrangedSubview(NSTextField(labelWithString: "Choose a folder to add this account.")) }
        found.frame.size = NSSize(width: 440, height: max(64, CGFloat(directories.count) * 28))
        validate()
    }
    @objc private func useFolder(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        setFolder(URL(fileURLWithPath: path))
    }
    private func setFolder(_ url: URL) {
        folder.stringValue = abbreviate(url)
        if label.stringValue.isEmpty {
            label.stringValue = url.lastPathComponent.hasPrefix(".") ? String(url.lastPathComponent.dropFirst()) : url.lastPathComponent
        }
        validate()
    }
    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.title = "Choose \(selectedProvider.configDirectoryLabel)"
        panel.prompt = "Choose"
        panel.beginSheetModal(for: window!) { [weak self] response in
            if response == .OK, let url = panel.url { self?.setFolder(url) }
        }
    }
    func controlTextDidChange(_ notification: Notification) { validate() }
    private func validate() {
        var directory: ObjCBool = false
        let exists = !folder.stringValue.isEmpty && FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &directory) && directory.boolValue
        let duplicate = app.config.account(configDir: selectedURL)
        let hasLabel = !label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        add.isEnabled = exists && duplicate == nil && hasLabel
        validation.stringValue = duplicate.map { "Already added as \($0.label)" }
            ?? (!folder.stringValue.isEmpty && !exists ? "Choose an existing folder." : " ")
    }
    @objc private func submit() {
        validate()
        guard add.isEnabled else { return }
        let account = Account(provider: selectedProvider,
                              label: label.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                              configDir: selectedURL)
        app.update { $0.register(account) }
        if app.config.account(configDir: selectedURL) != nil { closeSheet() }
    }
    @objc private func cancel() { closeSheet() }
    private func closeSheet() {
        window?.sheetParent?.endSheet(window!)
        completion()
    }
}

private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 8
    return stack
}
private func header(_ text: String) -> NSTextField {
    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 12, weight: .semibold)
    return label
}
private func abbreviate(_ url: URL) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let path = url.standardizedFileURL.path
    return path == home ? "~" : (path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path)
}
