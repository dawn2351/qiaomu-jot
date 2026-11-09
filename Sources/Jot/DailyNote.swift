import Foundation

/// Reads the vault's Daily Notes config and appends captured entries to today's note.
struct DailyNoteConfig {
    var folder: String      // relative to the vault root, "" = root
    var format: String      // Moment.js format, e.g. YYYY-MM-DD
    var template: String?   // template path relative to vault (no extension required)

    static func load(vault: URL) -> DailyNoteConfig {
        // Plain Markdown folder (no Obsidian): the app's own settings.
        guard FolderMode.isObsidianVault(vault) else {
            let p = Prefs.shared
            return DailyNoteConfig(folder: p.plainDailyFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")),
                                   format: p.plainDailyFormat.isEmpty ? "YYYY-MM-DD" : p.plainDailyFormat, template: nil)
        }
        let url = vault.appendingPathComponent(".obsidian/daily-notes.json")
        var cfg = DailyNoteConfig(folder: "", format: "YYYY-MM-DD", template: nil)
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let f = obj["folder"] as? String { cfg.folder = f.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            if let f = obj["format"] as? String, !f.isEmpty { cfg.format = f }
            if let t = obj["template"] as? String, !t.isEmpty { cfg.template = t }
        }
        return cfg
    }
}

enum MomentFormat {
    /// Converts a Moment.js date format into a DateFormatter pattern.
    static func toDateFormatter(_ m: String) -> String {
        var out = ""
        let chars = Array(m)
        var i = 0
        func run(_ c: Character) -> Int {
            var n = 0
            while i + n < chars.count && chars[i + n] == c { n += 1 }
            return n
        }
        while i < chars.count {
            let c = chars[i]
            if c == "[" {
                var lit = ""
                i += 1
                while i < chars.count && chars[i] != "]" { lit.append(chars[i]); i += 1 }
                i += 1
                out += "'" + lit.replacingOccurrences(of: "'", with: "''") + "'"
                continue
            }
            switch c {
            case "Y": let n = run(c); out += n >= 4 ? "yyyy" : "yy"; i += n
            case "D": let n = run(c); out += n >= 2 ? "dd" : "d"; i += n
            case "d": let n = run(c); out += n >= 4 ? "EEEE" : (n == 3 ? "EEE" : "e"); i += n
            case "M", "H", "h", "m", "s":
                let n = run(c); out += String(repeating: c, count: n); i += n
            case "A", "a": let n = run(c); _ = n; out += "a"; i += n
            case "W": let n = run(c); out += n >= 2 ? "ww" : "w"; i += n
            case "Q": let n = run(c); out += "Q"; i += n
            default:
                if c.isLetter { out += "'\(c)'" } else { out.append(c) }
                i += 1
            }
        }
        return out
    }

    static func string(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = toDateFormatter(format)
        return f.string(from: date)
    }
}

enum CaptureError: LocalizedError {
    case noVault, entryMissing
    var errorDescription: String? {
        switch self {
        case .noVault: return "请先选择 Obsidian 仓库"
        case .entryMissing: return "上一条记录已被修改或删除"
        }
    }
}

struct DailyNoteWriter {
    let vault: URL
    let attachmentOverride: String   // "" = follow Obsidian's setting
    var format: EntryFormat = .current
    var prependsEntries = false

    private var fm: FileManager { .default }
    /// Obsidian vault → ![[embeds]] and callouts; plain folder → standard Markdown links and <details>.
    var obsidian: Bool { FolderMode.isObsidianVault(vault) }

    func noteURL(for date: Date) -> URL {
        let cfg = DailyNoteConfig.load(vault: vault)
        var name = MomentFormat.string(date, format: cfg.format)
        // Formats like "YYYY/MM/YYYY-MM-DD" create sub folders.
        if !name.hasSuffix(".md") { name += ".md" }
        var dir = vault
        if !cfg.folder.isEmpty { dir = dir.appendingPathComponent(cfg.folder, isDirectory: true) }
        return dir.appendingPathComponent(name)
    }

    private func attachmentDir(noteDir: URL) -> URL {
        var setting = attachmentOverride.trimmingCharacters(in: .whitespaces)
        if setting.isEmpty && !obsidian { setting = "附件" }
        if setting.isEmpty {
            let app = vault.appendingPathComponent(".obsidian/app.json")
            if let data = try? Data(contentsOf: app),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let p = obj["attachmentFolderPath"] as? String { setting = p }
        }
        if setting.isEmpty || setting == "/" { return vault }
        if setting == "./" || setting == "." { return noteDir }
        if setting.hasPrefix("./") {
            return noteDir.appendingPathComponent(String(setting.dropFirst(2)), isDirectory: true)
        }
        return vault.appendingPathComponent(setting, isDirectory: true)
    }

    private func uniqueDestination(_ dir: URL, name: String) -> URL {
        var dest = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 1
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        return dest
    }

    private func templateContent(_ cfg: DailyNoteConfig, date: Date) -> String {
        guard var t = cfg.template else { return "" }
        if !t.hasSuffix(".md") { t += ".md" }
        guard var s = try? String(contentsOf: vault.appendingPathComponent(t), encoding: .utf8) else { return "" }
        // {{date:FORMAT}} / {{time:FORMAT}} / {{date}} / {{time}} / {{title}}
        let title = MomentFormat.string(date, format: cfg.format)
        s = s.replacingOccurrences(of: "{{title}}", with: title)
        if let re = try? NSRegularExpression(pattern: #"\{\{(date|time)(?::([^}]*))?\}\}"#) {
            let ns = s as NSString
            var result = ""
            var last = 0
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                let kind = ns.substring(with: m.range(at: 1))
                let fmt = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : (kind == "date" ? "YYYY-MM-DD" : "HH:mm")
                result += MomentFormat.string(date, format: fmt)
                last = m.range.location + m.range.length
            }
            result += ns.substring(from: last)
            s = result
        }
        return s
    }

    /// Saves a capture to today's daily note or an arbitrary note. Daily templates and named
    /// sections apply only to the daily note.
    @discardableResult
    func append(content: String, attachments: [URL], ocr: [String: String] = [:], source: SourceInfo? = nil, asTask: Bool = false,
                heading: String = "", to target: URL? = nil, date: Date = Date()) throws -> URL {
        let cfg = DailyNoteConfig.load(vault: vault)
        let note = target ?? noteURL(for: date)
        let h = target != nil ? "" : heading.trimmingCharacters(in: CharacterSet(charactersIn: "# ").union(.whitespaces))
        let exists = fm.fileExists(atPath: note.path)
        let topOriginal: String? = prependsEntries && h.isEmpty
            ? (exists ? try NoteTopInsertion.read(note) : (target == nil ? templateContent(cfg, date: date) : ""))
            : nil
        let noteDir = note.deletingLastPathComponent()
        try fm.createDirectory(at: noteDir, withIntermediateDirectories: true)
        let (embeds, copied) = try copyAttachments(attachments, noteDir: noteDir, ocr: ocr)
        var entry = format.render(content: content, attachments: embeds, source: source, task: asTask, date: date)
        let gap = format.isList ? "" : "\n"     // paragraph-style entries need a blank line between them

        var topInsertion: NoteTopInsertion?
        if var original = topOriginal {
            let insertion = NoteTopInsertion.plan(in: original, isList: format.isList)
            entry = insertion.normalize(entry)
            let index = String.Index(utf16Offset: insertion.offset, in: original)
            original.insert(contentsOf: insertion.wrapping(entry), at: index)
            try original.write(to: note, atomically: true, encoding: .utf8)
            topInsertion = insertion
        } else if h.isEmpty, exists {
            // Append in place instead of rewriting the file: friendlier to Obsidian and sync clients.
            let fh = try FileHandle(forUpdating: note)
            defer { try? fh.close() }
            let end = try fh.seekToEnd()
            var chunk = entry
            if end > 0 {
                let back = min(end, 2)
                try fh.seek(toOffset: end - back)
                let tail = try fh.read(upToCount: Int(back)) ?? Data()
                if tail != Data([0x0A, 0x0A]) { chunk = (tail.last == 0x0A ? gap : "\n" + gap) + chunk }
                try fh.seekToEnd()
            }
            try fh.write(contentsOf: Data(chunk.utf8))
        } else {
            var out = exists
                ? ((try? String(contentsOf: note, encoding: .utf8)) ?? "")
                : (target == nil ? templateContent(cfg, date: date) : "")
            if h.isEmpty {
                if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                if !out.isEmpty && !out.hasSuffix("\n\n") { out += gap }
                out += entry
            } else {
                out = Self.insert(entry: gap + entry, under: h, in: out)
            }
            try out.write(to: note, atomically: true, encoding: .utf8)
        }
        History.last = .init(note: note, entry: entry, files: copied, indent: format.isList ? "  " : "",
                             topInsertion: topInsertion)
        return note
    }

    /// Creates a new note `<folder>/<title>.md` (unique name) holding the text and attachment embeds.
    func createNote(folder: String, title: String, content text: String, attachments: [URL],
                    ocr: [String: String] = [:], source: SourceInfo? = nil) throws -> URL {
        let dir = folder.isEmpty ? vault : vault.appendingPathComponent(folder, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = NoteNaming.sanitize(title).isEmpty ? NoteNaming.autoTitle(from: "") : NoteNaming.sanitize(title)
        let note = uniqueDestination(dir, name: name + ".md")
        let (embeds, copied) = try copyAttachments(attachments, noteDir: dir, ocr: ocr)
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceLine = format.showSource ? source.map { "> " + $0.markdown } ?? "" : ""
        let content = ([body, embeds.joined(separator: "\n"), sourceLine].filter { !$0.isEmpty }
            .joined(separator: "\n\n")) + "\n"
        try content.write(to: note, atomically: true, encoding: .utf8)
        History.last = .init(note: note, entry: content, files: copied, indent: "", createdFile: true)
        return note
    }

    /// Copies attachments and returns their embeds (each followed by a folded block of recognised text).
    private func copyAttachments(_ attachments: [URL], noteDir: URL, ocr: [String: String] = [:]) throws
        -> (embeds: [String], copied: [URL]) {
        guard !attachments.isEmpty else { return ([], []) }
        let adir = attachmentDir(noteDir: noteDir)
        try fm.createDirectory(at: adir, withIntermediateDirectories: true)
        var embeds: [String] = [], copied: [URL] = []
        for src in attachments {
            let dest = uniqueDestination(adir, name: src.lastPathComponent)
            do { try fm.copyItem(at: src, to: dest) } catch {
                // Protected by macOS (e.g. inside another app's container): keep the rest of the capture.
                History.skipped.append(src.lastPathComponent)
                continue
            }
            copied.append(dest)
            var embed: String
            if obsidian {
                embed = "![[\(dest.lastPathComponent)]]"
            } else {
                let link = FolderMode.relativeLink(from: noteDir, to: dest)
                let isImage = [.image, .gif].contains(MediaKind(dest))
                embed = (isImage ? "!" : "") + "[\(dest.deletingPathExtension().lastPathComponent)](\(link))"
            }
            if let text = ocr[src.path] {
                let lines = text.components(separatedBy: "\n")
                embed += obsidian
                    ? "\n> [!note]- 图中文字\n" + lines.map { "> " + $0 }.joined(separator: "\n")
                    : "\n<details><summary>图中文字</summary>\n\n" + lines.joined(separator: "  \n") + "\n\n</details>"
            }
            embeds.append(embed)
        }
        return (embeds, copied)
    }

    /// Adds a follow-up thought (and attachments) underneath the last written entry.
    func amend(_ e: History.Entry, text: String, attachments: [URL], ocr: [String: String] = [:]) throws {
        var current = try e.readNote()
        guard let r = e.range(in: current) else { throw CaptureError.entryMissing }
        let (embeds, copied) = try copyAttachments(attachments, noteDir: e.note.deletingLastPathComponent(), ocr: ocr)
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = (t.isEmpty ? [] : t.components(separatedBy: "\n")) + embeds
        var added = ""
        if !lines.isEmpty {
            added = e.indent.isEmpty
                ? "\n" + lines.joined(separator: "\n") + "\n"                      // standalone note: new paragraph
                : lines.map { $0.isEmpty ? "" : e.indent + $0 }.joined(separator: "\n") + "\n"
        }
        let newEntry = e.entry + (e.topInsertion?.normalize(added) ?? added)
        current.replaceSubrange(r, with: e.topInsertion?.wrapping(newEntry) ?? newEntry)
        try current.write(to: e.note, atomically: true, encoding: .utf8)
        History.last = .init(note: e.note, entry: newEntry, files: e.files + copied, indent: e.indent,
                             createdFile: e.createdFile, topInsertion: e.topInsertion)
    }

    /// Inserts `entry` at the end of the section titled `heading` (creating it at the end if absent).
    static func insert(entry: String, under heading: String, in text: String) -> String {
        func level(_ line: String) -> Int? {
            let t = line.trimmingCharacters(in: .whitespaces)
            let n = t.prefix { $0 == "#" }.count
            guard n >= 1, n <= 6, t.dropFirst(n).first == " " else { return nil }
            return n
        }
        func title(_ line: String) -> String {
            line.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
        }
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let entryLines = entry.components(separatedBy: "\n").dropLast()
        guard let i = lines.firstIndex(where: { level($0) != nil && title($0) == heading }),
              let lv = level(lines[i]) else {
            var out = lines.joined(separator: "\n")
            if !out.isEmpty { out += "\n\n" }
            return out + "## \(heading)\n" + entry
        }
        var j = lines.count
        for k in (i + 1)..<max(i + 1, lines.count) { if let l = level(lines[k]), l <= lv { j = k; break } }
        while j - 1 > i && lines[j - 1].trimmingCharacters(in: .whitespaces).isEmpty { j -= 1 }
        let tail = j < lines.count
        lines.insert(contentsOf: entryLines, at: j)
        if tail, lines[j + entryLines.count].trimmingCharacters(in: .whitespaces).isEmpty == false {
            lines.insert("", at: j + entryLines.count)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Remembers the last written entry so it can be undone from the menu bar.
enum History {
    struct Entry {
        let note: URL
        let entry: String
        let files: [URL]
        /// Continuation indent: "  " under a list entry, "" for a note created by the capture.
        var indent = "  "
        var createdFile = false
        var topInsertion: NoteTopInsertion?

        func readNote() throws -> String {
            if topInsertion != nil { return try NoteTopInsertion.read(note) }
            return try String(contentsOf: note, encoding: .utf8)
        }

        func range(in text: String) -> Range<String.Index>? {
            if let topInsertion { return topInsertion.range(of: entry, in: text) }
            return text.range(of: entry, options: .backwards)
        }
        var summary: String {
            for line in entry.components(separatedBy: "\n") {
                let t = line.replacingOccurrences(of: #"^\s*(>\s*)?(\[![\w-]+\].*$)?(- (\[ \] )?)?(\*\*)?(\d{1,2}:\d{2}(\*\*)?( · .*$)?)?\s*(#{1,6}\s+)?(```\S*)?"#,
                                                  with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("— ") || t.hasPrefix("![") || t.hasPrefix("<details") { continue }
                return t.count > 18 ? String(t.prefix(18)) + "…" : t
            }
            return "附件"
        }
    }
    /// Attachments the last save couldn't read (reported in the toast, then cleared).
    static var skipped: [String] = []

    static var last: Entry? {
        didSet { if let e = last { RecentCaptures.record(e) } }
    }

    static func undoLast() throws {
        guard let e = last else { return }
        let text = try e.readNote()
        if e.createdFile, text == e.entry {      // the capture created this note: remove the whole file
            try FileManager.default.trashItem(at: e.note, resultingItemURL: nil)
            for f in e.files { try? FileManager.default.trashItem(at: f, resultingItemURL: nil) }
            last = nil
            return
        }
        if let r = e.range(in: text) {
            var out = text
            let atEnd = r.upperBound == text.endIndex
            out.removeSubrange(r)
            if atEnd && e.topInsertion == nil {      // drop the blank line that separated an appended entry
                while out.hasSuffix("\n\n") { out.removeLast() }
            }
            try out.write(to: e.note, atomically: true, encoding: .utf8)
        } else if e.topInsertion != nil { throw CaptureError.entryMissing }
        for f in e.files { try? FileManager.default.trashItem(at: f, resultingItemURL: nil) }
        RecentCaptures.remove(e)
        last = nil
    }
}

/// The last few captures, listed in the menu bar menu.
enum RecentCaptures {
    struct Item: Codable, Equatable {
        var summary: String
        var notePath: String
        var date: Date
        var key: String
    }
    private static let defaultsKey = "recentCaptures"
    /// Off during --selftest so test notes never reach the user's menu.
    static var enabled = true

    static var items: [Item] {
        let tmp = FileManager.default.temporaryDirectory.standardizedFileURL.path
        return (UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode([Item].self, from: $0) } ?? [])
            .filter { !URL(fileURLWithPath: $0.notePath).standardizedFileURL.path.hasPrefix(tmp) }
    }

    private static func key(_ e: History.Entry) -> String { e.note.path + "|" + String(e.entry.prefix(40)) }

    static func record(_ e: History.Entry) {
        guard enabled else { return }
        var list = items.filter { $0.key != key(e) }        // an amend updates the same capture
        list.insert(Item(summary: e.summary, notePath: e.note.path, date: Date(), key: key(e)), at: 0)
        save(Array(list.prefix(8)))
    }

    static func remove(_ e: History.Entry) { save(items.filter { $0.key != key(e) }) }

    private static func save(_ list: [Item]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(list), forKey: defaultsKey)
    }
}
