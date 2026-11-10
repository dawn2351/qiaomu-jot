import SwiftUI
import AppKit

// Small design kit for the 1.6 pages (AI settings, 记录): Vercel black and white, Geist,
// 1px hairlines, one black primary action per surface.

extension Theme {
    /// Geist for Latin with PingFang for CJK, as a SwiftUI font.
    static func text(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font { Font(nsFont(size, weight) as CTFont) }
    static let card = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.07, alpha: 1) : .white
    })
    static let canvas = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.035, alpha: 1) : NSColor(white: 0.975, alpha: 1)
    })
    static let success = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.24, green: 0.80, blue: 0.47, alpha: 1)
            : NSColor(srgbRed: 0.09, green: 0.55, blue: 0.27, alpha: 1)
    })
    static let danger = Color(nsColor: NSColor(name: nil) {
        $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 1, green: 0.42, blue: 0.42, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.13, blue: 0.13, alpha: 1)
    })
}

/// A provider or tool logo on a soft tile; monogram when there is no mark.
struct BrandMark: View {
    let icon: String?
    let name: String
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(Theme.hover)
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).strokeBorder(Theme.border)
            if let icon, let img = SourceIcons.image(named: "ai/\(icon)") {
                Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: size * 0.56, height: size * 0.56).foregroundStyle(Theme.text)
            } else {
                Text(String(name.prefix(1)).uppercased()).font(Theme.text(size * 0.42, .semibold)).foregroundStyle(Theme.text)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Single-choice marker.
struct RadioDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? Theme.text : Theme.subtle.opacity(0.7), lineWidth: on ? 5 : 1.2)
        }
        .frame(width: 16, height: 16)
        .animation(.easeOut(duration: 0.12), value: on)
    }
}

/// Small caps-like label above a group.
struct GroupLabel: View {
    let title: String
    var trailing: AnyView? = nil
    init(_ title: String, trailing: AnyView? = nil) { self.title = title; self.trailing = trailing }
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(Theme.text(12, .medium)).foregroundStyle(Theme.muted)
            Spacer()
            trailing
        }
        .padding(.horizontal, 2)
    }
}

/// White surface with a hairline border; rows inside get hairline separators via `CardDivider`.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.border))
    }
}

struct CardDivider: View {
    var inset: CGFloat = 0
    var body: some View { Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, inset) }
}

/// Text input with a hairline that darkens on focus.
struct JotField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var mono = false
    @FocusState private var focused: Bool

    var body: some View {
        Group {
            if secure { SecureField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.subtle)) }
            else { TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Theme.subtle)) }
        }
        .textFieldStyle(.plain)
        .font(mono ? .custom("GeistMono-Regular", size: 12.5) : Theme.text(13))
        .focused($focused)
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(focused ? Theme.text.opacity(0.55) : Theme.border, lineWidth: 1))
        .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// Label column + control, for forms drawn without `Form`.
struct FieldRow<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.text(12, .medium)).foregroundStyle(Theme.text)
            content
            if let hint { Text(hint).font(Theme.text(11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

// MARK: - Buttons

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.text(12.5, .medium))
            .padding(.horizontal, 12).frame(height: 30)
            .foregroundStyle(Theme.inverse)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.text))
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

struct PillButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.text(12.5, .medium))
            .padding(.horizontal, 10).frame(minWidth: 30, minHeight: 30)
            .foregroundStyle(Theme.text)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(configuration.isPressed || hover ? Theme.hover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { hover = $0 && enabled }
    }
}

/// Text-only action (编辑, 获取 Key ↗).
struct QuietButton: ButtonStyle {
    var color: Color = Theme.muted
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Theme.text(12, .medium))
            .foregroundStyle(hover ? Theme.text : color)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover || configuration.isPressed ? Theme.hover : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// Inline result line: green check or red cross with a message.
struct StatusLine: View {
    let ok: Bool
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
            Text(text).font(Theme.text(12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ok ? Theme.success : Theme.danger)
    }
}
