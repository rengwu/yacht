import Cocoa
import UsageCore

final class AccountsHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        // The rounded group supplies the outer edge, so omit the trailing divider.
        NSGraphicsContext.saveGraphicsState()
        var frame = bounds
        frame.size.width -= 1
        frame.clip()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class AccountNameCell: NSTableCellView {
    init(account: Account) {
        super.init(frame: .zero)
        let icon = NSImageView(image: ProviderImages.image(account.provider))
        icon.translatesAutoresizingMaskIntoConstraints = false
        imageView = icon
        addSubview(icon)
        let label = GrowingAccountLabelField(string: account.label)
        label.identifier = NSUserInterfaceItemIdentifier(account.configDir.path)
        label.setAccessibilityLabel("Label for \(account.configDir.path)")
        label.toolTip = account.configDir.path
        textField = label
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            imageView?.contentTintColor = backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : .labelColor
            (textField as? GrowingAccountLabelField)?.refreshTextColor()
        }
    }
}

/// A real AppKit field editor, sized to its text and bounded by the table column.
final class GrowingAccountLabelField: NSTextField {
    private var contentWidth: NSLayoutConstraint!

    init(string: String) {
        super.init(frame: .zero)
        stringValue = string
        translatesAutoresizingMaskIntoConstraints = false
        font = .systemFont(ofSize: 13)
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        cell?.isScrollable = true
        isBezeled = false
        isBordered = false
        drawsBackground = false
        bezelStyle = .roundedBezel
        contentWidth = widthAnchor.constraint(equalToConstant: 72)
        contentWidth.priority = .defaultHigh
        contentWidth.isActive = true
        resizeToContents()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func resizeToContents() {
        let width = (stringValue as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13)]).width
        contentWidth.constant = max(72, ceil(width) + 16)
    }
    func refreshTextColor() {
        textColor = currentEditor() == nil && cell?.backgroundStyle == .emphasized
            ? .alternateSelectedControlTextColor : .labelColor
    }
    override func textDidBeginEditing(_ notification: Notification) {
        isBezeled = true
        drawsBackground = true
        backgroundColor = .textBackgroundColor
        super.textDidBeginEditing(notification)
        refreshTextColor()
    }
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        resizeToContents()
    }
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        isBezeled = false
        drawsBackground = false
        resizeToContents()
        refreshTextColor()
    }
}

final class AccountWindowCell: NSTableCellView {
    private let popup: NSPopUpButton
    init(popup: NSPopUpButton) {
        self.popup = popup
        super.init(frame: .zero)
        popup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(popup)
        NSLayoutConstraint.activate([
            popup.leadingAnchor.constraint(equalTo: leadingAnchor),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(equalToConstant: 114),
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { popup.cell?.backgroundStyle = backgroundStyle }
    }
}
