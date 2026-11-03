import SwiftUI
import AppKit

/// NSTextView that draws its own placeholder, so it disappears the moment typing starts —
/// including IME composition (pinyin marked text), which never reaches a SwiftUI binding.
final class PlaceholderTextView: NSTextView {
    var placeholder = "" { didSet { needsDisplay = true } }
    var onPasteMedia: (() -> Bool)?
    var onCommand: ((MarkdownCommand) -> Void)?
    /// Files/images dropped on the editor become attachments instead of their paths being typed in.
    var dropHandler: MediaDropHandler?

    private func isMedia(_ s: NSDraggingInfo) -> Bool {
        dropHandler != nil && MediaDropHandler.isMedia(s.draggingPasteboard)
    }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        if isMedia(s) { dropHandler?.setTargeted(true); return .copy }
        return super.draggingEntered(s)
    }
    override func draggingUpdated(_ s: NSDraggingInfo) -> NSDragOperation {
        isMedia(s) ? .copy : super.draggingUpdated(s)
    }
    override func draggingExited(_ s: NSDraggingInfo?) {
        dropHandler?.setTargeted(false)
        super.draggingExited(s)
    }
    override func prepareForDragOperation(_ s: NSDraggingInfo) -> Bool {
        isMedia(s) ? true : super.prepareForDragOperation(s)
    }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard isMedia(s) else { return super.performDragOperation(s) }
        dropHandler?.setTargeted(false)
        return dropHandler?.perform(s.draggingPasteboard) ?? false
    }
    override func concludeDragOperation(_ s: NSDraggingInfo?) {
        dropHandler?.setTargeted(false)
        super.concludeDragOperation(s)
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if window?.firstResponder === self, let cmd = MarkdownCommand.shortcut(for: e) {
            onCommand?(cmd); return true
        }
        return super.performKeyEquivalent(with: e)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        (placeholder as NSString).draw(at: NSPoint(x: x, y: textContainerInset.height), withAttributes: [
            .font: Theme.nsFont(MarkdownStyler.size), .foregroundColor: Theme.nsPlaceholder,
        ])
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
    }

    override func unmarkText() { super.unmarkText(); needsDisplay = true }

    /// Media goes to attachments; everything else is pasted as plain text (Markdown-friendly).
    var onPastedLink: ((String) -> Void)?

    override func paste(_ sender: Any?) {
        if onPasteMedia?() == true { return }
        let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        pasteAsPlainText(sender)
        if !s.contains(where: \.isWhitespace), let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
           u.host != nil { onPastedLink?(s) }
    }
}

struct CaptureTextView: NSViewRepresentable {
    @ObservedObject var model: CaptureModel

        static let minHeight: CGFloat = 76
    static let maxHeight: CGFloat = 300

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = PlaceholderTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = Theme.nsFont(MarkdownStyler.size)
        tv.textColor = Theme.nsText
        tv.insertionPointColor = Theme.nsText
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        let para = NSMutableParagraphStyle(); para.lineSpacing = 4
        tv.defaultParagraphStyle = para
        tv.typingAttributes = MarkdownStyler.baseAttributes
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = model.text
        tv.delegate = context.coordinator
        tv.onPasteMedia = { [weak model] in model?.pasteIfMedia() ?? false }
        tv.onCommand = { [weak tv] in tv?.perform($0) }
        tv.dropHandler = model.dropHandler
        tv.onPastedLink = { [weak coordinator = context.coordinator] in coordinator?.unfurl($0) }
        tv.registerForDraggedTypes(MediaDropHandler.acceptedTypes)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = tv
        context.coordinator.textView = tv
        context.coordinator.install()
        context.coordinator.refresh()

        DispatchQueue.main.async {
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = context.coordinator.textView else { return }
        tv.placeholder = model.amend != nil ? "补充你的想法…" : "记点什么…  可粘贴截图、拖入图片或视频"
        if tv.string != model.text, !tv.hasMarkedText() {
            tv.string = model.text
            context.coordinator.refresh()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: CaptureModel
        weak var textView: PlaceholderTextView?
        init(model: CaptureModel) { self.model = model }


        func install() {
            model.completeTag = { [weak self] tag in self?.complete(tag) }
            model.format = { [weak self] cmd in self?.textView?.perform(cmd) }
            model.focusEditor = { [weak self] in
                guard let tv = self?.textView else { return }
                tv.window?.makeKeyAndOrderFront(nil)
                tv.window?.makeFirstResponder(tv)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            model.text = tv.string
            refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) { updateTagQuery() }

        func textView(_ textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertTab(_:)) {
                if let first = model.tagSuggestions.first { complete(first); return true }
                return textView.indentListItem(false)
            }
            if sel == #selector(NSResponder.insertBacktab(_:)) { return textView.indentListItem(true) }
            if sel == #selector(NSResponder.insertNewline(_:)) { return textView.continueList() }
            if sel == #selector(NSResponder.cancelOperation(_:)) {
                // Esc: dismiss tag suggestions first, then close (NSTextView would otherwise autocomplete).
                if !model.tagSuggestions.isEmpty { model.tagQuery = nil } else { model.onCancel?() }
                return true
            }
            return false
        }

        /// Restyles #tags, grows the editor and updates tag completion.
        func refresh() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            if !tv.hasMarkedText() { MarkdownStyler.apply(to: storage) }
            if let lm = tv.layoutManager, let tc = tv.textContainer {
                lm.ensureLayout(for: tc)
                let h = ceil(lm.usedRect(for: tc).height) + 4
                let clamped = min(max(h, CaptureTextView.minHeight), CaptureTextView.maxHeight)
                if abs(clamped - model.editorHeight) > 0.5 {
                    DispatchQueue.main.async { self.model.editorHeight = clamped }
                }
            }
            updateTagQuery()
        }

        private func currentToken() -> NSRange? {
            guard let tv = textView else { return nil }
            let sel = tv.selectedRange()
            guard sel.length == 0 else { return nil }
            let ns = tv.string as NSString
            var start = sel.location
            while start > 0 {
                let c = ns.substring(with: NSRange(location: start - 1, length: 1))
                if c.rangeOfCharacter(from: .whitespacesAndNewlines) != nil { break }
                start -= 1
            }
            let r = NSRange(location: start, length: sel.location - start)
            guard r.length >= 1, ns.substring(with: r).hasPrefix("#") else { return nil }
            return r
        }

        private func updateTagQuery() {
            let q = currentToken().map { (textView!.string as NSString).substring(with: $0) }
            if q != model.tagQuery { DispatchQueue.main.async { self.model.tagQuery = q } }
        }

        /// Replaces a just-pasted bare link with [page title](url) once the title arrives (⌘Z undoes it).
        func unfurl(_ link: String) {
            guard Prefs.shared.linkTitles, let url = URL(string: link) else { return }
            LinkTitle.fetch(url) { [weak self] title in
                guard let self, let title, let tv = self.textView, !tv.hasMarkedText() else { return }
                let ns = tv.string as NSString
                let r = ns.range(of: link, options: .backwards)
                guard r.location != NSNotFound else { return }
                // Leave it alone if it's already inside Markdown link syntax.
                if r.location > 0, ["(", "<", "["].contains(ns.substring(with: NSRange(location: r.location - 1, length: 1))) { return }
                let safe = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
                let md = "[\(safe)](\(link))"
                let sel = tv.selectedRange()
                tv.insertText(md, replacementRange: r)
                let shift = (md as NSString).length - r.length
                tv.setSelectedRange(NSRange(location: sel.location >= NSMaxRange(r) ? sel.location + shift : sel.location, length: 0))
            }
        }

        private func complete(_ tag: String) {
            guard let tv = textView, let r = currentToken() else { return }
            tv.insertText(tag + " ", replacementRange: r)
            model.tagQuery = nil
        }
    }
}
