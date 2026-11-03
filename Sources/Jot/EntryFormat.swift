import AppKit
import SwiftUI

// MARK: - Source

/// Where a capture came from, kept apart from the content so the entry format decides how (or whether) to show it.
struct SourceInfo: Equatable {
    var app: String
    var bundleID: String
    var kind: SourceKind
    var title: String?
    var url: URL?
    /// Non-web reference in Markdown: 《file》 p.3, 《书名》 作者, `main.swift` · Cursor.
    var detail: String?

    /// What `{{source}}` renders to.
    var markdown: String {
        if let url {
            let t = (title?.isEmpty == false ? title! : url.host ?? url.absoluteString)
                .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
            return "[\(t)](\(url.absoluteString))"
        }
        return detail ?? app
    }

    /// Short text for the UI chip next to the app glyph.
    var label: String {
        if let title, !title.isEmpty { return title }
        if let detail { return detail.replacingOccurrences(of: "`", with: "") }
        return app
    }

    init(app: String, bundleID: String, kind: SourceKind, title: String? = nil, url: URL? = nil, detail: String? = nil) {
        self.app = app; self.bundleID = bundleID; self.kind = kind
        self.title = title; self.url = url; self.detail = detail
    }

    init(_ ctx: SourceContext) {
        self.init(app: ctx.appName, bundleID: ctx.bundleID, kind: ctx.kind)
        switch ctx.kind {
        case .browser:
            url = ctx.url
            title = ctx.pageTitle
        case .mail:
            url = ctx.mailLink
            title = ctx.mailSubject ?? "邮件"
        case .pdf:
            if let f = ctx.fileName {
                detail = "《\((f as NSString).deletingPathExtension)》" + (ctx.pdfPage.map { " p.\($0)" } ?? "")
            }
        case .code:
            if let f = ctx.fileName { detail = "`\(f)` · \(ctx.appName)" }
        default:
            break
        }
    }
}

// MARK: - App glyphs (simple-icons CC0, Lucide ISC)

enum SourceIcons {
    private static let brands: [String: String] = [
        "com.google.Chrome": "googlechrome", "com.google.Chrome.canary": "googlechrome",
        "com.apple.Safari": "safari", "com.apple.SafariTechnologyPreview": "safari",
        "org.mozilla.firefox": "firefoxbrowser", "company.thebrowser.Browser": "arc", "company.thebrowser.dia": "arc",
        "com.brave.Browser": "brave", "com.operasoftware.Opera": "opera", "com.vivaldi.Vivaldi": "vivaldi",
        "app.zen-browser.zen": "zenbrowser", "com.kagi.kagimacOS": "kagi",
        "ai.perplexity.comet": "perplexity", "ai.perplexity.mac": "perplexity",
        "com.anthropic.claudefordesktop": "claude", "md.obsidian": "obsidian", "notion.id": "notion",
        "com.tencent.xinWeChat": "wechat", "ru.keepcoder.Telegram": "telegram", "org.telegram.desktop": "telegram",
        "com.hnc.Discord": "discord", "com.apple.dt.Xcode": "xcode", "com.todesktop.230313mzl4w4u92": "cursor",
        "com.exafunction.windsurf": "windsurf", "dev.zed.Zed": "zedindustries", "dev.zed.Zed-Preview": "zedindustries",
        "com.sublimetext.4": "sublimetext", "com.sublimetext.3": "sublimetext", "com.googlecode.iterm2": "iterm2",
        "dev.warp.Warp-Stable": "warp", "com.mitchellh.ghostty": "ghostty", "com.evernote.Evernote": "evernote",
        "com.figma.Desktop": "figma", "com.linear": "linear", "com.raycast.macos": "raycast",
        "com.github.GitHubClient": "github", "com.tencent.qq": "qq",
    ]

    private static func fallback(_ kind: SourceKind, _ id: String) -> String {
        if id == "com.openai.chat" { return "sparkles" }
        switch kind {
        case .browser: return "globe"
        case .mail: return "mail"
        case .notes: return "notebook-text"
        case .pdf: return "file-text"
        case .book: return "book-open"
        case .code: return "code"
        case .terminal: return "square-terminal"
        case .finder: return "folder"
        case .other: return "app-window"
        }
    }

    private static var cache: [String: NSImage] = [:]

    static func image(named path: String) -> NSImage? {
        if let img = cache[path] { return img }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Icons/\(path).svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        img.isTemplate = true
        cache[path] = img
        return img
    }

    static func image(bundleID: String, kind: SourceKind) -> NSImage? {
        if let slug = brands[bundleID] ?? (bundleID.hasPrefix("com.jetbrains.") ? "jetbrains" : nil),
           let img = image(named: "brands/" + slug) { return img }
        return image(named: "lucide/" + fallback(kind, bundleID))
    }
}

/// Monochrome app glyph that follows the theme colour.
struct SourceGlyph: View {
    let bundleID: String
    let kind: SourceKind
    var size: CGFloat = 13
    var color: Color = Theme.text

    var body: some View {
        if let img = SourceIcons.image(bundleID: bundleID, kind: kind) {
            Image(nsImage: img).renderingMode(.template).resizable().scaledToFit()
                .frame(width: size, height: size).foregroundStyle(color)
        }
    }
}

// MARK: - Entry format

enum EntryStyle: String, CaseIterable, Identifiable {
    case plain, timeFirst, list, quote, callout, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain: return "原样（推荐）"
        case .timeFirst: return "时间在前"
        case .list: return "列表项"
        case .quote: return "引用块"
        case .callout: return "Callout"
        case .custom: return "自定义模板"
        }
    }

    var template: String {
        switch self {
        // Time and source go on a quote line: real Markdown, and visibly apart from the content.
        case .plain, .custom: return "{{content}}\n{{attachments}}\n> {{time}} · {{source}}"
        case .timeFirst: return "**{{time}}** · {{source}}\n{{content}}\n{{attachments}}"
        case .list: return "- {{time}} {{content}}\n  {{attachments}}\n  > {{source}}"
        case .quote: return "> {{content}}\n> {{attachments}}\n>\n> {{time}} · {{source}}"
        case .callout: return "> [!quote] {{time}} · {{source}}\n> {{content}}\n> {{attachments}}"
        }
    }
}

struct EntryFormat {
    var template: String
    var showTime: Bool
    var timeFormat: String
    var showSource: Bool

    static var current: EntryFormat {
        let p = Prefs.shared
        let style = EntryStyle(rawValue: p.entryStyle) ?? .plain
        return EntryFormat(template: style == .custom ? p.customTemplate : style.template,
                           showTime: p.timestamp, timeFormat: p.timeFormat, showSource: p.showSource)
    }

    /// List entries sit on consecutive lines; everything else is a paragraph separated by a blank line.
    var isList: Bool { template.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("- ") }

    private static let variable = try! NSRegularExpression(pattern: #"\{\{(\w+)(?::([^}]*))?\}\}"#)

    func render(content: String, attachments: [String], source: SourceInfo?, task: Bool = false,
                date: Date = Date()) -> String {
        var template = self.template
        var content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if task {
            if isList, let r = template.range(of: "- ") { template.replaceSubrange(r, with: "- [ ] ") }
            else { content = "- [ ] " + content }
        }
        func value(_ name: String, _ arg: String?) -> String {
            switch name {
            case "content": return content
            case "attachments": return attachments.joined(separator: "\n")
            case "time": return showTime ? MomentFormat.string(date, format: arg ?? timeFormat) : ""
            case "date": return MomentFormat.string(date, format: arg ?? "YYYY-MM-DD")
            case "source": return showSource ? (source?.markdown ?? "") : ""
            case "app": return showSource ? (source?.app ?? "") : ""
            case "title": return showSource ? (source?.title ?? "") : ""
            case "url": return showSource ? (source?.url?.absoluteString ?? "") : ""
            default: return "{{\(name)}}"
            }
        }

        var out: [String] = []
        for line in template.components(separatedBy: "\n") {
            let ns = line as NSString
            let matches = Self.variable.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else { out.append(line); continue }
            // Multi-line values (content, attachments) continue with the line's block prefix.
            let lead = ns.substring(to: matches[0].range.location)
            let cont = lead.hasPrefix(">") ? "> "
                : lead.range(of: #"^\s*([-*+]|\d+\.)\s"#, options: .regularExpression) != nil ? "  "
                : String(lead.prefix { $0 == " " || $0 == "\t" })
            var rendered = ""
            var last = 0
            for m in matches {
                rendered += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let name = ns.substring(with: m.range(at: 1))
                let arg = m.range(at: 2).location == NSNotFound ? nil : ns.substring(with: m.range(at: 2))
                rendered += value(name, arg).components(separatedBy: "\n")
                    .enumerated().map { $0.offset == 0 ? $0.element : (cont + $0.element) }.joined(separator: "\n")
                last = NSMaxRange(m.range)
            }
            rendered += ns.substring(from: last)
            // Tidy separators left by empty variables ("— 14:32 · " → "— 14:32").
            rendered = rendered.replacingOccurrences(of: #"(\s*·\s*)+"#, with: " · ", options: .regularExpression)
                .replacingOccurrences(of: #"^(\s*(?:[-*+>]\s*)*(?:\[![\w-]+\]\s*)?(?:—\s*)?)·\s*"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: #"(\s*·)?\s*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\*\*\s*\*\*\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(\s*(?:[-*+>])(?: \[[ xX]\])?) {2,}"#, with: "$1 ", options: .regularExpression)
            // Drop lines left with nothing but markup.
            let meaningful = rendered.replacingOccurrences(of: #"[\s\-—·>*#_|+]|\[!?[\w-]*\]"#, with: "", options: .regularExpression)
            if meaningful.isEmpty && !(line.contains("{{content}}") && isList) { continue }
            out.append(rendered)
        }
        // A quote spacer (">") left at the end when time and source are off.
        while let last = out.last, last.trimmingCharacters(in: .whitespaces) == ">" { out.removeLast() }
        return out.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}

extension Prefs {
    static let sampleSource = SourceInfo(app: "Google Chrome", bundleID: "com.google.Chrome", kind: .browser,
                                         title: "置身事内 - 读书笔记", url: URL(string: "https://example.com/book"))
}
