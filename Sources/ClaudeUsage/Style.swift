import Cocoa
import UsageCore

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// A color that resolves to a different hex value depending on whether
    /// the current appearance is light or dark.
    convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// The only place semantic tones become colours. Everything else about the
/// display was decided in UsageCore.
enum Style {
    static func color(_ tone: Tone) -> NSColor {
        switch tone {
        case .normal: return .labelColor
        case .warn: return NSColor(light: 0xeb9317, dark: 0xffbd61)
        case .critical: return NSColor(light: 0xFF3B30, dark: 0xff9c9c)
        case .dimmed: return .secondaryLabelColor
        }
    }

    static func statusTitle(_ segments: [StyledText]) -> NSAttributedString {
        let title = NSMutableAttributedString()
        for segment in segments {
            title.append(NSAttributedString(string: segment.text, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: color(segment.tone),
            ]))
        }
        return title
    }

    /// A disabled `NSMenuItem` — the state every row here is in, since none of
    /// them are commands — gets its title drawn through AppKit's own disabled
    /// style, which dims whatever colour `attributedTitle` specifies on top of
    /// whatever dimming the tone already called for. `.warn`/`.critical`'s
    /// saturated system colours mostly survive that; `.normal`/`.dimmed` wash
    /// out to a flat, low-contrast grey. A custom view sidesteps it: `isEnabled
    /// = false` still suppresses the hover highlight and click (a custom view
    /// on a disabled item draws with no highlight, same as a plain title
    /// would), but the view is responsible for its own drawing, so the text
    /// colour actually painted is the one this function set.
    static func menuLabel(
        _ text: String, tone: Tone = .normal, monospace: Bool = false, indent: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false

        let label = NSTextField(labelWithString: text)
        label.font = monospace
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        label.textColor = color(tone)
        label.sizeToFit()

        let leading: CGFloat = indent ? 34 : 14
        label.frame.origin = NSPoint(x: leading, y: 3)

        let container = NSView(frame: NSRect(
            x: 0, y: 0, width: leading + label.frame.width + 14, height: label.frame.height + 6
        ))
        container.addSubview(label)
        item.view = container

        return item
    }
}
