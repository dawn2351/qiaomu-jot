import SwiftUI
import AppKit

/// Read-only Markdown for 「记录」: Obsidian-flavoured blocks (headings, lists, tasks, quotes, callouts,
/// code, embeds, tables) with inline bold / italic / code / links / [[wikilinks]] / ==highlights== / #tags.
enum MD {
    indirect enum Block: Equatable {
        case heading(Int, String)
        case paragraph(String)
        case item(indent: Int, marker: Marker, text: String)
        case quote([Block])
        case callout(kind: String, title: String, folded: Bool, body: [Block])
        case code(lang: String, text: String)
        case embed(String)
        case table([[String]])
        case rule
    }
    enum Marker: Equatable { case bullet, number(String), task(Bool) }

    static func parse(_ text: String) -> [Block] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // YAML front matter.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }
        var blocks: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flush(); i += 1; continue }
            // Fenced code.
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flush()
                let fence = String(t.prefix(3)), lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { body.append(lines[i]); i += 1 }
                blocks.append(.code(lang: lang, text: body.joined(separator: "\n")))
                i += 1; continue
            }
            // <details><summary>…</summary> … </details> (plain-folder OCR text).
            if t.hasPrefix("<details") {
                flush()
                let title = t.range(of: #"(?<=<summary>).*?(?=</summary>)"#, options: .regularExpression).map { String(t[$0]) } ?? "详情"
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].contains("</details>") { body.append(lines[i]); i += 1 }
                blocks.append(.callout(kind: "note", title: title, folded: true, body: parse(body.joined(separator: "\n"))))
                i += 1; continue
            }
            // Quote / callout.
            if t.hasPrefix(">") {
                flush()
                var body: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    var s = String(q.dropFirst()); if s.hasPrefix(" ") { s.removeFirst() }
                    body.append(s); i += 1
                }
                if let first = body.first, let m = first.range(of: #"^\[!([\w-]+)\]([+-]?)\s*(.*)$"#, options: .regularExpression) {
                    let head = String(first[m])
                    let kind = head.range(of: #"(?<=\[!)[\w-]+"#, options: .regularExpression).map { String(head[$0]).lowercased() } ?? "note"
                    let folded = head.range(of: #"^\[![\w-]+\]-"#, options: .regularExpression) != nil
                    let title = head.replacingOccurrences(of: #"^\[![\w-]+\][+-]?\s*"#, with: "", options: .regularExpression)
                    blocks.append(.callout(kind: kind, title: title.isEmpty ? kind.capitalized : title, folded: folded,
                                           body: parse(body.dropFirst().joined(separator: "\n"))))
                } else {
                    blocks.append(.quote(parse(body.joined(separator: "\n"))))
                }
                continue
            }
            // Heading.
            if let m = t.range(of: #"^#{1,6} "#, options: .regularExpression) {
                flush()
                blocks.append(.heading(t[m].count - 1, String(t[m.upperBound...]).trimmingCharacters(in: .whitespaces)))
                i += 1; continue
            }
            // Rule.
            if t.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil {
                flush(); blocks.append(.rule); i += 1; continue
            }
            // Embed on its own line.
            if let target = embedTarget(t) { flush(); blocks.append(.embed(target)); i += 1; continue }
            // Table.
            if t.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) != nil {
                flush()
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    if r.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) == nil {
                        rows.append(r.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|")
                            .map { $0.trimmingCharacters(in: .whitespaces) })
                    }
                    i += 1
                }
                blocks.append(.table(rows)); continue
            }
            // List item.
            let indent = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
            if let m = t.range(of: #"^[-*+] \[( |x|X)\] "#, options: .regularExpression) {
                flush()
                blocks.append(.item(indent: indent, marker: .task(t[m].lowercased().contains("[x]")), text: String(t[m.upperBound...])))
                i += 1; continue
            }
            if let m = t.range(of: #"^[-*+] "#, options: .regularExpression) {
                flush(); blocks.append(.item(indent: indent, marker: .bullet, text: String(t[m.upperBound...]))); i += 1; continue
            }
            if let m = t.range(of: #"^\d{1,3}[.)] "#, options: .regularExpression) {
                flush()
                blocks.append(.item(indent: indent, marker: .number(String(t[m]).trimmingCharacters(in: .whitespaces)),
                                    text: String(t[m.upperBound...])))
                i += 1; continue
            }
            para.append(t)
            i += 1
        }
        flush()
        return blocks
    }

    /// `![[a.png|300]]` → a.png, `![alt](path)` → path.
    static func embedTarget(_ t: String) -> String? {
        if t.hasPrefix("![["), t.hasSuffix("]]") {
            return String(t.dropFirst(3).dropLast(2)).components(separatedBy: "|")[0].components(separatedBy: "#")[0]
        }
        if t.hasPrefix("!["), t.hasSuffix(")"), let open = t.range(of: "](") {
            let path = String(t[open.upperBound..<t.index(before: t.endIndex)])
            return (path.removingPercentEncoding ?? path).components(separatedBy: " \"")[0]
        }
        return nil
    }

    /// Inline Markdown → AttributedString, with Obsidian extras.
    static func inline(_ raw: String, size: CGFloat) -> AttributedString {
        var s = raw
        // [[target|alias]] / [[target]] → a link Jot opens in Obsidian.
        s = s.replacingOccurrences(of: #"(?<!!)\[\[([^\]|#]+)(?:#[^\]|]*)?\|([^\]]+)\]\]"#, with: "[$2](jot-note:$1)",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<!!)\[\[([^\]|#]+)(?:#[^\]]*)?\]\]"#, with: "[$1](jot-note:$1)", options: .regularExpression)
        // Wiki targets may contain spaces; percent-encode inside jot-note: links.
        if let re = try? NSRegularExpression(pattern: #"\(jot-note:([^)]+)\)"#) {
            let ns = s as NSString
            var out = "", last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let target = ns.substring(with: m.range(at: 1))
                out += "(jot-note:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target) + ")"
                last = m.range.location + m.range.length
            }
            s = out + ns.substring(from: last)
        }
        // **bold**: CommonMark won't open/close emphasis next to CJK punctuation (的**“运动员”**), so mark it ourselves.
        s = s.replacingOccurrences(of: #"\*\*([^*\n]+?)\*\*"#, with: "\u{E002}$1\u{E003}", options: .regularExpression)
        // ==highlight== → private-use markers, styled after parsing.
        s = s.replacingOccurrences(of: #"==([^=\n]+)=="#, with: "\u{E000}$1\u{E001}", options: .regularExpression)
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                                   failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(s)
        // Inline code.
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .custom("GeistMono-Regular", size: size - 1)
            a[run.range].backgroundColor = Theme.hover
        }
        // Links.
        for run in a.runs where run.link != nil {
            a[run.range].foregroundColor = Theme.text
            a[run.range].underlineStyle = .single
        }
        // Highlights.
        while let open = a.range(of: "\u{E000}"), let close = a[open.upperBound...].range(of: "\u{E001}") {
            a[open.upperBound..<close.lowerBound].backgroundColor = Theme.highlight
            a.removeSubrange(close)
            a.removeSubrange(open)
        }
        while let open = a.range(of: "\u{E002}"), let close = a[open.upperBound...].range(of: "\u{E003}") {
            a[open.upperBound..<close.lowerBound].inlinePresentationIntent =
                (a[open.upperBound..<close.lowerBound].inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            a.removeSubrange(close)
            a.removeSubrange(open)
        }
        // Geist ships as separate faces: apply weight and slant as real fonts, not traits.
        for run in a.runs {
            guard let intent = run.inlinePresentationIntent, !intent.contains(.code) else { continue }
            if intent.contains(.stronglyEmphasized) { a[run.range].font = Theme.text(size, .semibold) }
            else if intent.contains(.emphasized) { a[run.range].font = Theme.text(size).italic() }
        }
        // #tags.
        let plain = String(a.characters)
        if let re = try? NSRegularExpression(pattern: #"(?<![\w/#&])#[\p{L}\p{N}_/-]*\p{L}[\p{L}\p{N}_/-]*"#) {
            for m in re.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)).reversed() {
                guard let r = Range(m.range, in: plain),
                      let lo = AttributedString.Index(r.lowerBound, within: a),
                      let hi = AttributedString.Index(r.upperBound, within: a) else { continue }
                a[lo..<hi].foregroundColor = Theme.muted
                a[lo..<hi].backgroundColor = Theme.hover
            }
        }
        return a
    }
}

extension Theme {
    static let highlight = Color(nsColor: nsHighlight)
}

/// Renders parsed blocks. `resolve` maps an embed name to a file on disk.
struct MarkdownBody: View {
    let blocks: [MD.Block]
    var size: CGFloat = 13.5
    var resolve: (String) -> URL? = { _ in nil }
    var onOpenNote: (String) -> Void = { _ in }

    init(_ text: String, size: CGFloat = 13.5, resolve: @escaping (String) -> URL? = { _ in nil },
         onOpenNote: @escaping (String) -> Void = { _ in }) {
        self.blocks = MD.parse(text); self.size = size; self.resolve = resolve; self.onOpenNote = onOpenNote
    }
    init(blocks: [MD.Block], size: CGFloat, resolve: @escaping (String) -> URL?, onOpenNote: @escaping (String) -> Void) {
        self.blocks = blocks; self.size = size; self.resolve = resolve; self.onOpenNote = onOpenNote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, b in
                block(b).padding(.top, i == 0 ? 0 : gap(blocks[i - 1], b))
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "jot-note" {
                onOpenNote(url.absoluteString.dropFirst("jot-note:".count).removingPercentEncoding ?? "")
                return .handled
            }
            return .systemAction
        })
    }

    /// Paragraph rhythm: list items sit close together, everything else gets a full beat.
    private func gap(_ prev: MD.Block, _ b: MD.Block) -> CGFloat {
        if case .item = prev, case .item = b { return size * 0.38 }
        if case .heading = b { return size * 1.1 }
        return size * 0.8
    }

    private func text(_ s: String, _ weight: NSFont.Weight = .regular, scale: CGFloat = 1) -> some View {
        Text(MD.inline(s, size: size * scale))
            .font(Theme.text(size * scale, weight))
            .foregroundStyle(Theme.text)
            .lineSpacing(size * 0.32)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ b: MD.Block) -> some View {
        switch b {
        case .heading(let level, let s):
            text(s, .semibold, scale: [1.3, 1.18, 1.08, 1, 1, 1][min(level, 6) - 1])
                .padding(.top, level <= 2 ? 4 : 2)
        case .paragraph(let s):
            text(s)
        case .item(let indent, let marker, let s):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Group {
                    switch marker {
                    case .bullet:
                        Circle().fill(Theme.subtle).frame(width: 4.5, height: 4.5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + size * 0.22 }
                    case .number(let n):
                        Text(n).font(Theme.text(size)).foregroundStyle(Theme.muted).monospacedDigit()
                    case .task(let done):
                        Image(systemName: done ? "checkmark.square.fill" : "square")
                            .font(.system(size: size - 1)).foregroundStyle(done ? Theme.text : Theme.subtle)
                    }
                }
                .frame(width: 14, alignment: .center)
                if case .task(true) = marker {
                    text(s).strikethrough(color: Theme.subtle).opacity(0.55)
                } else {
                    text(s)
                }
            }
            .padding(.leading, CGFloat(indent) * 18)
        case .quote(let inner):
            HStack(alignment: .top, spacing: 0) {
                MarkdownBody(blocks: inner, size: size, resolve: resolve, onOpenNote: onOpenNote)
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover.opacity(0.6)))
        case .callout(let kind, let title, let folded, let inner):
            CalloutView(kind: kind, title: title, folded: folded) {
                MarkdownBody(blocks: inner, size: size - 0.5, resolve: resolve, onOpenNote: onOpenNote)
            }
        case .code(_, let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s).font(.custom("GeistMono-Regular", size: size - 1.5)).foregroundStyle(Theme.text)
                    .lineSpacing(3).textSelection(.enabled).fixedSize()
                    .padding(12)
            }
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover))
        case .embed(let name):
            EmbedView(name: name, url: resolve(name))
        case .table(let rows):
            TableView(rows: rows, size: size)
        case .rule:
            Rectangle().fill(Theme.border).frame(height: 1).padding(.vertical, 4)
        }
    }
}

private struct CalloutView<Content: View>: View {
    let kind: String
    let title: String
    @State var folded: Bool
    @ViewBuilder var content: Content

    init(kind: String, title: String, folded: Bool, @ViewBuilder content: () -> Content) {
        self.kind = kind; self.title = title; self._folded = State(initialValue: folded); self.content = content()
    }

    private var symbol: String {
        switch kind {
        case "tip", "hint", "important": return "flame"
        case "warning", "caution", "attention": return "exclamationmark.triangle"
        case "question", "help", "faq": return "questionmark.circle"
        case "quote", "cite": return "quote.opening"
        case "todo": return "checklist"
        case "success", "check", "done": return "checkmark.circle"
        case "abstract", "summary", "tldr": return "list.bullet.clipboard"
        default: return title == "图中文字" ? "text.viewfinder" : "info.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.15)) { folded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                    Text(title).font(Theme.text(12, .medium))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(folded ? 0 : 90))
                }
                .foregroundStyle(Theme.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !folded { content }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover.opacity(0.6)))
    }
}

private struct EmbedView: View {
    let name: String
    let url: URL?

    var body: some View {
        if let url, [.image, .gif].contains(MediaKind(url)), let img = NSImage(contentsOf: url) {
            let ratio = img.size.width > 0 ? img.size.height / img.size.width : 0.6
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                .frame(maxWidth: min(420, img.size.width), maxHeight: 280, alignment: .leading)
                .frame(height: min(280, min(420, img.size.width) * ratio))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
                .onTapGesture { Lightbox.show(urls: [url], index: 0, onRemove: { _ in }, onClose: {}) }
                .help(name)
        } else {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Text((name as NSString).lastPathComponent).font(Theme.text(12.5)).foregroundStyle(Theme.text).lineLimit(1)
                if url == nil { Text("未找到").font(Theme.text(11)).foregroundStyle(Theme.subtle) }
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.hover.opacity(0.6)))
            .onTapGesture { if let url { NSWorkspace.shared.open(url) } }
        }
    }

    private var icon: String {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "mp4", "mov", "m4v", "webm": return "play.rectangle"
        case "mp3", "m4a", "wav", "aac", "flac": return "waveform"
        case "pdf": return "doc.richtext"
        case "md": return "doc.text"
        default: return "paperclip"
        }
    }
}

private struct TableView: View {
    let rows: [[String]]
    let size: CGFloat
    var body: some View {
        let cols = rows.map(\.count).max() ?? 0
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(MD.inline(c < row.count ? row[c] : "", size: size - 1))
                            .font(Theme.text(size - 1, r == 0 ? .semibold : .regular))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(r == 0 ? Theme.hover.opacity(0.6) : .clear)
                if r < rows.count - 1 { Rectangle().fill(Theme.border).frame(height: 1).gridCellUnsizedAxes(.horizontal) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Finds attachments by name: the capture's own files first, then the vault (indexed once per minute).
enum Attachments {
    private static var index: [String: URL] = [:]
    private static var indexedAt: Date = .distantPast
    private static var indexedVault = ""

    static func resolve(_ name: String, near note: URL?, files: [String] = []) -> URL? {
        let base = (name as NSString).lastPathComponent
        if let f = files.first(where: { ($0 as NSString).lastPathComponent == base }) { return URL(fileURLWithPath: f) }
        if let note {
            let rel = note.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
            if FileManager.default.fileExists(atPath: rel.path) { return rel }
        }
        guard let vault = Prefs.shared.vaultURL else { return nil }
        let direct = vault.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if indexedVault != vault.path || Date().timeIntervalSince(indexedAt) > 60 { build(vault) }
        return index[base.lowercased()]
    }

    private static func build(_ vault: URL) {
        index = [:]; indexedVault = vault.path; indexedAt = Date()
        let media: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "mp4", "mov", "m4a", "mp3", "wav", "pdf"]
        guard let e = FileManager.default.enumerator(at: vault, includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        var n = 0
        for case let u as URL in e {
            n += 1; if n > 60_000 { break }
            if media.contains(u.pathExtension.lowercased()) { index[u.lastPathComponent.lowercased()] = u }
        }
    }
}
