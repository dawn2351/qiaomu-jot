import SwiftUI
import AppKit

/// Inline "save to…" switcher (lives inside the panel: a popover can't reliably take keyboard focus
/// from a non-activating panel).
struct DestinationPicker: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.subtle)
                SearchField(text: $model.pickerQuery, placeholder: "搜索笔记、文件夹或内容（支持拼音）…",
                            onMove: { model.movePicker($0) }, onSubmit: { model.choosePicked() },
                            onCancel: { model.closePicker() })
                    .frame(height: 22)
                Button { model.closePicker() } label: { Kbd("esc") }
                    .buttonStyle(.plain).help("返回（Esc）")
            }
            .padding(.horizontal, 20).frame(height: 52)
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    // Eager VStack (≤ ~70 rows): LazyVStack kept stale rows when results changed in quick succession.
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.pickerRows) { row in
                            switch row.kind {
                            case .header(let title):
                                Text(title).font(Theme.sans(11, .medium)).foregroundStyle(Theme.subtle)
                                    .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
                            case .item(let i, let item):
                                let d = item.destination
                                DestinationRow(destination: d, selected: i == model.pickerSelection,
                                               current: d == model.destination, date: item.date, snippet: item.snippet)
                                    .id(i)
                                    .onTapGesture { model.choose(d) }
                            }
                        }
                        if model.pickerRows.isEmpty {
                            Text(model.indexLoaded ? "没有匹配的文件夹或笔记" : "正在读取…")
                                .font(Theme.sans(13)).foregroundStyle(Theme.subtle)
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .id(model.pickerQuery)      // a new query is a new list
                }
                .frame(height: 300)
                .onChange(of: model.pickerSelection) { i in proxy.scrollTo(i) }
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 14) {
                keyHint("↑↓", "选择")
                keyHint("↩", "确定")
                Button { model.closePicker() } label: { keyHint("esc", "返回") }.buttonStyle(.plain)
                Spacer()
                Text(Prefs.shared.prependEntries ? "选笔记写入开头，选文件夹新建笔记" : "选笔记追加到末尾，选文件夹新建笔记")
                    .font(Theme.sans(11)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 20).frame(height: 34)
        }
    }
}

private func keyHint(_ key: String, _ label: String) -> some View {
    HStack(spacing: 5) {
        Kbd(key)
        Text(label).font(Theme.sans(11)).foregroundStyle(Theme.subtle)
    }
}

private struct DestinationRow: View {
    let destination: Destination
    let selected: Bool
    let current: Bool
    var date: Date? = nil
    var snippet: String? = nil

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .short; return f
    }()
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbol).font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.text : Theme.muted).frame(width: 16)
            Text(destination.kind == .daily ? "今日日记" : destination.name)
                .font(Theme.sans(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            if let snippet, !snippet.isEmpty {
                Text(snippet).font(Theme.sans(12)).foregroundStyle(Theme.subtle).lineLimit(1).truncationMode(.tail)
            } else if !destination.parent.isEmpty {
                Text(destination.parent).font(Theme.sans(12)).foregroundStyle(Theme.subtle)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer(minLength: 8)
            if current {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            // Recents show when they were used; the action hint appears on the highlighted row.
            if let date, !selected {
                Text(Self.relative.localizedString(for: date, relativeTo: Date()))
                    .font(Theme.sans(11)).foregroundStyle(Theme.subtle).monospacedDigit()
            } else {
                Text(hint).font(Theme.sans(11)).foregroundStyle(selected ? Theme.muted : Theme.subtle.opacity(0.8))
            }
        }
        .padding(.horizontal, 12).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Theme.hover.opacity(1.4) : hover ? Theme.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var hint: String {
        switch destination.kind {
        case .daily: return "写入今日日记"
        case .note: return Prefs.shared.prependEntries ? "写入开头" : "追加到末尾"
        case .folder: return "新建笔记"
        }
    }
}

/// Single-line field that hands ↑ ↓ ↩ Esc to the picker.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onMove: (Int) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = Theme.nsFont(15)
        f.textColor = Theme.nsText
        f.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: Theme.nsFont(15), .foregroundColor: Theme.nsPlaceholder,
        ])
        f.cell?.usesSingleLineMode = true
        f.cell?.lineBreakMode = .byTruncatingTail
        f.delegate = context.coordinator
        f.stringValue = text
        DispatchQueue.main.async { f.window?.makeFirstResponder(f) }
        return f
    }

    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        if f.stringValue != text, (f.currentEditor() as? NSTextView)?.hasMarkedText() != true { f.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField
        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ n: Notification) {
            if let f = n.object as? NSTextField { parent.text = f.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1); return true
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1); return true
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel(); return true
            default: return false
            }
        }
    }
}

struct DestinationButton: View {
    let destination: Destination
    let label: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if destination.kind != .daily {
                    Image(systemName: destination.symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(label).lineLimit(1).truncationMode(.middle).frame(maxWidth: 220, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.subtle)
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 6).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.hover : .clear))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("选择保存位置  ⌘P")
    }
}
