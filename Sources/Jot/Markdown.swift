import AppKit

// MARK: - Commands

enum MarkdownCommand: Equatable {
    case bold, italic, strike, highlight, code, codeBlock, link, wikilink
    case heading(Int?)          // nil cycles H1 → H2 → H3 → plain
    case bullet, numbered, task, quote

    /// ⌘B ⌘I ⌘⇧X ⌘⇧H ⌘E ⌘⇧C ⌘K ⌘1-3 ⌘⇧8 ⌘⇧7 ⌘L ⌘' (by key code, so they work with any layout/IME).
    static func shortcut(for e: NSEvent) -> MarkdownCommand? {
        let m = e.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (m, e.keyCode) {
        case (.command, 11): return .bold
        case (.command, 34): return .italic
        case ([.command, .shift], 7): return .strike
        case ([.command, .shift], 4): return .highlight
        case (.command, 14): return .code
        case ([.command, .shift], 8): return .codeBlock
        case (.command, 40): return .link
        case (.command, 18): return .heading(1)
        case (.command, 19): return .heading(2)
        case (.command, 20): return .heading(3)
        case ([.command, .shift], 28): return .bullet
        case ([.command, .shift], 26): return .numbered
        case (.command, 37): return .task
        case (.command, 39): return .quote
        default: return nil
        }
    }
}

// MARK: - Live styling

/// Styles Markdown in place (Bear / iA Writer style): syntax stays editable, markers are dimmed.
enum MarkdownStyler {
    static let size: CGFloat = 17

    private static func re(_ p: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: [.anchorsMatchLines])
    }
    private static let heading = re(#"^(#{1,6})[ \t]+(.+)$"#)
    private static let quote = re(#"^(>[ \t]?)(.*)$"#)
    private static let list = re(#"^([ \t]*)([-*+]|\d+\.)[ \t]+(\[[ xX]\][ \t]+)?"#)
    private static let doneTask = re(#"^[ \t]*[-*+][ \t]+\[[xX]\][ \t]+(.+)$"#)
    private static let bold = re(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    // ASCII-only word boundary: CJK counts as \w, which would block *斜体* next to Chinese text.
    private static let italic = re(#"(?<![*A-Za-z0-9])([*_])(?=[^\s*_])(.+?)(?<=[^\s*_])\1(?![*A-Za-z0-9])"#)
    private static let strike = re(#"(~~)(?=\S)(.+?)(?<=\S)~~"#)
    private static let highlight = re(#"(==)(?=\S)(.+?)(?<=\S)=="#)
    private static let inlineCode = re(#"`[^`\n]+`"#)
    private static let fence = re(#"^```[^\n]*\n(?:.*\n)*?(?:```[ \t]*$|.*\z)"#)
    private static let link = re(#"(\[)([^\]\n]+)(\]\()([^)\n]+)(\))"#)
    private static let wikilink = re(#"(\[\[)([^\]\n]+)(\]\])"#)
    private static let url = re(#"(?<![(\[<])\bhttps?://[^\s)\]>]+"#)
    private static let tag = re(#"(?<![\w/&#])#[^\s#\[\]()]+"#)

    static var baseAttributes: [NSAttributedString.Key: Any] { attributes(size: size) }

    static func attributes(size: CGFloat) -> [NSAttributedString.Key: Any] {
        let para = NSMutableParagraphStyle(); para.lineSpacing = size * 0.24
        return [.font: Theme.nsFont(size), .foregroundColor: Theme.nsText, .paragraphStyle: para]
    }

    static func apply(to storage: NSTextStorage, size: CGFloat = MarkdownStyler.size) {
        let baseAttributes = attributes(size: size)
        let s = storage.string
        let full = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        defer { storage.endEditing() }
        storage.setAttributes(baseAttributes, range: full)

        func each(_ r: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            r.enumerateMatches(in: s, range: full) { m, _, _ in if let m { body(m) } }
        }
        func add(_ key: NSAttributedString.Key, _ value: Any, _ r: NSRange) {
            if r.location != NSNotFound, r.length > 0 { storage.addAttribute(key, value: value, range: r) }
        }
        func dim(_ r: NSRange) { add(.foregroundColor, Theme.nsMarker, r) }
        /// Inline pair like **x**: style the inner text, dim both markers.
        func pair(_ r: NSRegularExpression, _ style: (NSRange) -> Void) {
            each(r) { m in
                let open = m.range(at: 1)
                style(m.range(at: 2))
                dim(open)
                dim(NSRange(location: NSMaxRange(m.range) - open.length, length: open.length))
            }
        }

        each(heading) { m in
            let level = m.range(at: 1).length
            let scale: CGFloat = [1.45, 1.25, 1.1][min(level, 3) - 1]
            add(.font, Theme.nsFont(size * scale, .semibold), m.range)
            dim(m.range(at: 1))
        }
        each(quote) { m in add(.foregroundColor, Theme.nsMuted, m.range(at: 2)); dim(m.range(at: 1)) }
        each(list) { m in add(.foregroundColor, Theme.nsMuted, m.range(at: 2)); add(.foregroundColor, Theme.nsMuted, m.range(at: 3)) }
        each(doneTask) { m in
            add(.strikethroughStyle, NSUnderlineStyle.single.rawValue, m.range(at: 1))
            add(.foregroundColor, Theme.nsPlaceholder, m.range(at: 1))
        }
        pair(bold) { add(.font, Theme.nsFont(size, .semibold), $0) }
        pair(italic) { add(.obliqueness, 0.16, $0) }
        pair(strike) { add(.strikethroughStyle, NSUnderlineStyle.single.rawValue, $0); add(.foregroundColor, Theme.nsMuted, $0) }
        pair(highlight) { add(.backgroundColor, Theme.nsHighlight, $0) }
        each(link) { m in
            add(.underlineStyle, NSUnderlineStyle.single.rawValue, m.range(at: 2))
            add(.underlineColor, Theme.nsMarker, m.range(at: 2))
            for i in [1, 3, 4, 5] { dim(m.range(at: i)) }
        }
        each(wikilink) { m in
            add(.underlineStyle, NSUnderlineStyle.single.rawValue, m.range(at: 2))
            add(.underlineColor, Theme.nsMarker, m.range(at: 2))
            dim(m.range(at: 1)); dim(m.range(at: 3))
        }
        each(url) { m in
            add(.underlineStyle, NSUnderlineStyle.single.rawValue, m.range)
            add(.underlineColor, Theme.nsMarker, m.range)
        }
        each(tag) { m in
            add(.font, Theme.nsFont(size, .medium), m.range)
            add(.foregroundColor, Theme.nsMuted, m.range)
        }
        // Code last: it overrides every other style inside it.
        let codeFont = Theme.nsMono(size * 0.86)
        each(inlineCode) { m in
            storage.setAttributes(baseAttributes, range: m.range)
            add(.font, codeFont, m.range); add(.backgroundColor, Theme.nsCode, m.range)
            dim(NSRange(location: m.range.location, length: 1))
            dim(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        each(fence) { m in
            storage.setAttributes(baseAttributes, range: m.range)
            add(.font, codeFont, m.range); add(.backgroundColor, Theme.nsCode, m.range)
            let ns = s as NSString
            dim(ns.lineRange(for: NSRange(location: m.range.location, length: 0)))
            let last = ns.lineRange(for: NSRange(location: max(NSMaxRange(m.range) - 1, m.range.location), length: 0))
            if ns.substring(with: last).hasPrefix("```"), last.location != m.range.location { dim(last) }
        }
    }
}

// MARK: - Editing

extension NSTextView {
    private var ns: NSString { string as NSString }

    private func replace(_ range: NSRange, with text: String, select sel: NSRange) {
        insertText(text, replacementRange: range)       // goes through undo + delegate
        setSelectedRange(sel)
    }

    func perform(_ cmd: MarkdownCommand) {
        switch cmd {
        case .bold: wrap("**", "**")
        case .italic: wrap("*", "*")
        case .strike: wrap("~~", "~~")
        case .highlight: wrap("==", "==")
        case .wikilink: wrap("[[", "]]")
        case .code:
            if ns.substring(with: selectedRange()).contains("\n") { codeBlock() } else { wrap("`", "`") }
        case .codeBlock: codeBlock()
        case .link: insertLink()
        case .heading(let level): toggleHeading(level)
        case .bullet: toggleLinePrefix { _ in "- " }
        case .numbered: toggleLinePrefix { "\($0 + 1). " }
        case .task: toggleLinePrefix { _ in "- [ ] " }
        case .quote: toggleLinePrefix { _ in "> " }
        }
        window?.makeFirstResponder(self)
    }

    /// Wraps the selection in markers, or unwraps it when it's already wrapped.
    private func wrap(_ open: String, _ close: String) {
        let sel = selectedRange()
        let o = (open as NSString).length, c = (close as NSString).length
        let inner = ns.substring(with: sel)
        if sel.location >= o, NSMaxRange(sel) + c <= ns.length,
           ns.substring(with: NSRange(location: sel.location - o, length: o)) == open,
           ns.substring(with: NSRange(location: NSMaxRange(sel), length: c)) == close {
            replace(NSRange(location: sel.location - o, length: sel.length + o + c), with: inner,
                    select: NSRange(location: sel.location - o, length: sel.length))
            return
        }
        let innerNS = inner as NSString
        if sel.length >= o + c, inner.hasPrefix(open), inner.hasSuffix(close) {
            let stripped = innerNS.substring(with: NSRange(location: o, length: sel.length - o - c))
            replace(sel, with: stripped, select: NSRange(location: sel.location, length: (stripped as NSString).length))
            return
        }
        replace(sel, with: open + inner + close, select: NSRange(location: sel.location + o, length: sel.length))
    }

    private func insertLink() {
        let sel = selectedRange()
        let text = ns.substring(with: sel)
        func isURL(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !t.contains(" ") && (URL(string: t)?.scheme?.hasPrefix("http") ?? false)
        }
        if isURL(text) {
            replace(sel, with: "[](\(text))", select: NSRange(location: sel.location + 1, length: 0))
        } else if let clip = NSPasteboard.general.string(forType: .string), isURL(clip), !text.isEmpty {
            let s = "[\(text)](\(clip.trimmingCharacters(in: .whitespacesAndNewlines)))"
            replace(sel, with: s, select: NSRange(location: sel.location + (s as NSString).length, length: 0))
        } else {
            let s = "[\(text)]()"
            let caret = text.isEmpty ? sel.location + 1 : sel.location + (s as NSString).length - 1
            replace(sel, with: s, select: NSRange(location: caret, length: 0))
        }
    }

    private func codeBlock() {
        let pr = ns.paragraphRange(for: selectedRange())
        var block = ns.substring(with: pr)
        let trailing = block.hasSuffix("\n")
        if trailing { block.removeLast() }
        if block.hasPrefix("```") && block.hasSuffix("```") && block.count >= 6 {   // unwrap
            var lines = block.components(separatedBy: "\n")
            lines.removeFirst(); if !lines.isEmpty { lines.removeLast() }
            let s = lines.joined(separator: "\n") + (trailing ? "\n" : "")
            replace(pr, with: s, select: NSRange(location: pr.location, length: 0))
            return
        }
        let s = "```\n" + block + "\n```" + (trailing ? "\n" : "")
        // Caret after the opening fence so a language can be typed; on an empty line, inside the block.
        let caret = block.isEmpty ? pr.location + 4 : pr.location + 3
        replace(pr, with: s, select: NSRange(location: caret, length: 0))
    }

    private static let anyPrefix = try! NSRegularExpression(pattern: #"^([ \t]*)(?:[-*+] \[[ xX]\] |[-*+] |\d+\. |> ?|#{1,6} )?"#)

    /// Splits a line into (indent, existing block prefix, content).
    private func parts(_ line: String) -> (String, String, String) {
        let l = line as NSString
        guard let m = Self.anyPrefix.firstMatch(in: line, range: NSRange(location: 0, length: l.length)) else { return ("", "", line) }
        let indent = l.substring(with: m.range(at: 1))
        let prefix = l.substring(with: NSRange(location: m.range(at: 1).length, length: m.range.length - m.range(at: 1).length))
        return (indent, prefix, l.substring(from: m.range.length))
    }

    private func editLines(_ transform: ([String]) -> [String]) {
        let sel = selectedRange()
        let pr = ns.paragraphRange(for: sel)
        var block = ns.substring(with: pr)
        let trailing = block.hasSuffix("\n")
        if trailing { block.removeLast() }
        let out = transform(block.components(separatedBy: "\n")).joined(separator: "\n")
        let caret = pr.location + (out as NSString).length
        replace(pr, with: out + (trailing ? "\n" : ""),
                select: sel.length > 0 ? NSRange(location: pr.location, length: (out as NSString).length)
                                       : NSRange(location: caret, length: 0))
    }

    /// Applies a list/quote prefix to every selected line, or removes it if all lines already have it.
    private func toggleLinePrefix(_ make: @escaping (Int) -> String) {
        editLines { lines in
            let probe = make(0)
            let numbered = probe.first?.isNumber == true
            let has: (String) -> Bool = { line in
                let p = self.parts(line).1
                return numbered ? p.first?.isNumber == true : p == probe
            }
            let all = lines.contains { !$0.isEmpty } && lines.filter { !$0.isEmpty }.allSatisfy(has)
            var n = 0
            return lines.map { line in
                let (indent, _, content) = self.parts(line)
                if all { return indent + content }
                if line.isEmpty && lines.count > 1 { return line }
                defer { n += 1 }
                return indent + make(n) + content
            }
        }
    }

    private func toggleHeading(_ level: Int?) {
        editLines { lines in
            lines.map { line in
                let (indent, prefix, content) = self.parts(line)
                let current = prefix.hasPrefix("#") ? prefix.filter { $0 == "#" }.count : 0
                let next = level.map { $0 == current ? 0 : $0 } ?? (current >= 3 ? 0 : current + 1)
                return indent + (next == 0 ? "" : String(repeating: "#", count: next) + " ") + content
            }
        }
    }

    // MARK: Smart keys

    private static let listLine = try! NSRegularExpression(pattern: #"^([ \t]*)(?:([-*+]) \[[ xX]\] |([-*+]) |(\d+)\. |(>) ?)"#)

    private func currentLine() -> (range: NSRange, text: String) {
        var r = ns.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        var t = ns.substring(with: r)
        if t.hasSuffix("\n") { t.removeLast(); r.length -= 1 }
        return (r, t)
    }

    /// Return inside a list/quote continues it; on an empty item it ends the list.
    func continueList() -> Bool {
        let sel = selectedRange()
        guard sel.length == 0, !hasMarkedText() else { return false }
        let (lr, line) = currentLine()
        let l = line as NSString
        guard let m = Self.listLine.firstMatch(in: line, range: NSRange(location: 0, length: l.length)) else { return false }
        let content = l.substring(from: m.range.length).trimmingCharacters(in: .whitespaces)
        if content.isEmpty {
            replace(lr, with: "", select: NSRange(location: lr.location, length: 0))
            return true
        }
        let indent = l.substring(with: m.range(at: 1))
        let next: String
        if m.range(at: 2).location != NSNotFound { next = l.substring(with: m.range(at: 2)) + " [ ] " }
        else if m.range(at: 3).location != NSNotFound { next = l.substring(with: m.range(at: 3)) + " " }
        else if m.range(at: 4).location != NSNotFound { next = "\((Int(l.substring(with: m.range(at: 4))) ?? 0) + 1). " }
        else { next = "> " }
        let s = "\n" + indent + next
        replace(sel, with: s, select: NSRange(location: sel.location + (s as NSString).length, length: 0))
        return true
    }

    /// Tab / ⇧Tab nest list items.
    func indentListItem(_ outdent: Bool) -> Bool {
        let (lr, line) = currentLine()
        let l = line as NSString
        guard Self.listLine.firstMatch(in: line, range: NSRange(location: 0, length: l.length)) != nil,
              !line.hasPrefix(">") else { return false }
        let sel = selectedRange()
        if outdent {
            let cut = line.hasPrefix("\t") ? 1 : line.hasPrefix("  ") ? 2 : 0
            guard cut > 0 else { return true }
            replace(NSRange(location: lr.location, length: cut), with: "",
                    select: NSRange(location: max(sel.location - cut, lr.location), length: 0))
        } else {
            replace(NSRange(location: lr.location, length: 0), with: "\t",
                    select: NSRange(location: sel.location + 1, length: 0))
        }
        return true
    }
}
