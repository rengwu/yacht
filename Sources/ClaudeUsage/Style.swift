import Cocoa
import UsageCore

/// The only place semantic tones become colours. Everything else about the
/// display was decided in UsageCore.
enum Style {
    static func color(_ tone: Tone) -> NSColor {
        switch tone {
        case .normal: return .labelColor
        case .warn: return .systemOrange
        case .critical: return .systemRed
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

    static func menuLabel(
        _ text: String, tone: Tone = .normal, monospace: Bool = false, indent: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(
            string: (indent ? "    " : "") + text,
            attributes: [
                .font: monospace
                    ? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                    : NSFont.systemFont(ofSize: 12),
                .foregroundColor: color(tone),
            ]
        )
        return item
    }
}
