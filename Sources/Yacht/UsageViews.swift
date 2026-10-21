import Cocoa
import UsageCore

enum ProviderImages {
    private static var images: [Provider: NSImage] = [:]

    static func image(_ provider: Provider) -> NSImage {
        if let image = images[provider] { return image }
        let url = Bundle.main.url(forResource: provider.rawValue, withExtension: "pdf")
            ?? Bundle.module.url(forResource: provider.rawValue, withExtension: "pdf")
        let image = url.flatMap(NSImage.init(contentsOf:)) ?? NSImage(
            size: NSSize(width: 14, height: 14), flipped: false
        ) { rect in
            NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3).stroke()
            String(provider.displayName.prefix(1)).draw(
                at: NSPoint(x: 3, y: 1), withAttributes: [.font: NSFont.systemFont(ofSize: 10)]
            )
            return true
        }
        image.size = NSSize(width: 14, height: 14)
        image.isTemplate = true
        image.accessibilityDescription = provider.displayName
        images[provider] = image
        return image
    }
}

/// Draw once into the status button's image when values change. Live NSTextField
/// children inside NSStatusBarButton cause repeated replicant snapshots on macOS 27.
/// The same drawing is used by the settings preview, with no additional timer.
final class StatusContentView: NSView {
    private var entries: [UsageAccountPresentation] = []
    private var style: AccountDisplay = .labels
    private var initialized = false
    private var widths: [CGFloat] = []
    private(set) var contentWidth: CGFloat = 26

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @discardableResult
    func update(_ accounts: [UsageAccountPresentation], style: AccountDisplay) -> Bool {
        let shown = accounts.filter { $0.account.showInMenuBar }
        guard !initialized || shown != entries || style != self.style else { return false }
        initialized = true
        entries = shown
        self.style = style
        widths = entries.map { entry in
            let value = entry.menuBarFigure?.value ?? "—"
            let valueWidth = max(24, (value as NSString).size(withAttributes: [.font: valueFont]).width)
            let labelWidth = (entry.account.label as NSString).size(withAttributes: [.font: labelFont]).width
            return ceil(style == .labels ? max(valueWidth, labelWidth) : 18 + valueWidth)
        }
        contentWidth = entries.isEmpty ? 26 : widths.reduce(0, +) + CGFloat(entries.count) * 10
        frame.size = NSSize(width: contentWidth, height: 24)
        let summary = entries.map { entry in
            let figure = entry.menuBarFigure
            let convention = entry.percentages == .used ? "used" : "remaining"
            let value = figure?.resetPassed == true ? "awaiting update"
                : figure.map { "\($0.value) \(convention)" } ?? "no data"
            return "\(entry.account.label), \(entry.selectedWindow.defaultLabel): \(value)"
        }.joined(separator: ", ")
        toolTip = summary.isEmpty ? "Yacht — open Settings to show accounts" : summary
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(toolTip)
        needsDisplay = true
        return true
    }

    private var valueFont: NSFont {
        .monospacedDigitSystemFont(ofSize: style == .labels ? 11 : 13, weight: .semibold)
    }
    private var labelFont: NSFont { .systemFont(ofSize: 9) }

    func image(appearance: NSAppearance) -> NSImage {
        let image = NSImage(size: NSSize(width: contentWidth, height: 24))
        image.lockFocus()
        appearance.performAsCurrentDrawingAppearance { drawContent() }
        image.unlockFocus()
        return image
    }

    override func draw(_ dirtyRect: NSRect) { drawContent() }

    private func drawContent() {
        if entries.isEmpty {
            drawImage(NSImage(systemSymbolName: "sailboat", accessibilityDescription: nil)!,
                      in: NSRect(x: 4, y: 3, width: 18, height: 18), color: .labelColor)
            return
        }
        var x: CGFloat = 5
        for (entry, width) in zip(entries, widths) {
            let figure = entry.menuBarFigure
            let valueX = style == .labels ? x : x + 18
            let valueWidth = style == .labels ? width : width - 18
            if style == .labels {
                drawText(entry.account.label, font: labelFont, color: .labelColor,
                         in: NSRect(x: x, y: 12, width: width, height: 11))
            } else {
                drawImage(ProviderImages.image(entry.account.provider),
                          in: NSRect(x: x, y: 5, width: 14, height: 14), color: .labelColor)
            }
            drawText(figure?.value ?? "—", font: valueFont,
                     color: Style.color(figure?.tone ?? .dimmed),
                     in: NSRect(x: valueX, y: style == .labels ? -1 : 4, width: valueWidth, height: 16))
            x += width + 10
        }
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
        ])
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect)
    }
}

final class UsageMeter: NSView {
    let row: UsageWindowPresentation?
    init(row: UsageWindowPresentation?, percentages: PercentageDisplay, frame: NSRect) {
        self.row = row
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.levelIndicator)
        setAccessibilityLabel(row?.label ?? "Usage")
        if let row, row.percentage != nil {
            setAccessibilityValue("\(row.value) \(percentages == .used ? "used" : "remaining")")
        } else {
            setAccessibilityValue(row?.resetPassed == true ? "Awaiting update" : "No data")
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: bounds.midY - 2, width: bounds.width, height: 4)
        NSColor.separatorColor.setFill()
        if let row, let percentage = row.percentage {
            NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
            Style.color(row.tone).setFill()
            var fill = track
            fill.size.width *= CGFloat(percentage / 100)
            if fill.width > 0 { NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill() }
        } else {
            for x in stride(from: CGFloat(0), to: track.width, by: 6) {
                NSRect(x: x, y: track.minY, width: min(3, track.width - x), height: 4).fill()
            }
        }
    }
}

/// Native text and images within a non-command menu item; actions remain standard
/// NSMenuItems, retaining system dismissal, keyboard navigation and overflow scrolling.
final class UsageAccountMenuView: NSView {
    override var isFlipped: Bool { true }
    private var lastEntry: UsageAccountPresentation?
    private var lastStyle: AccountDisplay?
    static let width: CGFloat = 320

    init(entry: UsageAccountPresentation, style: AccountDisplay) {
        super.init(frame: .zero)
        update(entry, style: style)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ entry: UsageAccountPresentation, style: AccountDisplay) {
        guard entry != lastEntry || style != lastStyle else { return }
        lastEntry = entry
        lastStyle = style
        subviews.forEach { $0.removeFromSuperview() }
        // A nil row is a visual placeholder, not an invented quota window.
        let rows: [UsageWindowPresentation?] = entry.windows.isEmpty ? [nil] : entry.windows.map { $0 }
        frame.size = NSSize(width: Self.width, height: 32 + CGFloat(rows.count) * 21)
        var labelX: CGFloat = 14
        if style == .icons {
            let icon = NSImageView(image: ProviderImages.image(entry.account.provider))
            icon.contentTintColor = .labelColor
            icon.frame = NSRect(x: 14, y: 9, width: 14, height: 14)
            addSubview(icon)
            labelX = 33
        }
        let label = addText(entry.account.label, x: labelX, y: 6, width: 210 - labelX, bold: true)
        label.toolTip = entry.explanation ?? entry.account.configDir.path
        if entry.staleAge != nil {
            let clock = NSImageView(image: NSImage(
                systemSymbolName: "clock", accessibilityDescription: "Saved reading"
            )!)
            clock.contentTintColor = .secondaryLabelColor
            clock.frame = NSRect(x: 296, y: 10, width: 10, height: 10)
            clock.toolTip = entry.explanation
            addSubview(clock)
        }
        for (index, row) in rows.enumerated() {
            let y = CGFloat(27 + index * 21)
            if let row {
                addText(row.label, x: 14, y: y, width: 48, color: .secondaryLabelColor)
            }
            addSubview(UsageMeter(row: row, percentages: entry.percentages,
                                  frame: NSRect(x: 68, y: y, width: 88, height: 17)))
            let value = addText(row?.value ?? "—", x: 162, y: y, width: 42,
                                color: Style.color(row?.tone ?? .dimmed), alignment: .right)
            if row?.percentage == nil {
                value.toolTip = row?.resetPassed == true
                    ? "Reset passed — awaiting a fresh reading" : entry.explanation
            }
            if let reset = row?.reset, !reset.isEmpty {
                addText(reset, x: 210, y: y, width: 96, color: .secondaryLabelColor, alignment: .right)
            }
        }
        setAccessibilityElement(false)
        toolTip = entry.explanation
    }

    @discardableResult
    private func addText(
        _ text: String, x: CGFloat, y: CGFloat, width: CGFloat,
        color: NSColor = .labelColor, alignment: NSTextAlignment = .left, bold: Bool = false
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .systemFont(ofSize: 13, weight: .semibold) : .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: x, y: y, width: width, height: 19)
        addSubview(label)
        return label
    }
}
