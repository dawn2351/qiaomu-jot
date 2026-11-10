import Foundation

/// An index of what was captured, when and where — the note stays the source of truth.
/// Each item points into its note (an anchor plus a length); the text is read back from the note,
/// so edits and deletions made in Obsidian show up here. One JSON Lines file per month.
enum CaptureLog {
    struct Item: Codable, Identifiable, Equatable {
        var id: String
        var date: Date
        var notePath: String
        /// Today's daily note at capture time (vs. a scene's note or folder).
        var daily: Bool
        /// The capture made the whole note (folder destination).
        var createdFile: Bool
        /// The start of the entry, used to find it in the note again.
        var anchor: String
        var length: Int
        var files: [String]
        var summary: String
        var sourceApp: String?
        var sourceBundle: String?
        var sourceKind: SourceKind?
        var sourceTitle: String?
        var sourceURL: String?
        var sourceMarkdown: String?

        var noteURL: URL { URL(fileURLWithPath: notePath) }
        var source: SourceInfo? {
            guard let app = sourceApp else { return nil }
            return SourceInfo(app: app, bundleID: sourceBundle ?? "", kind: sourceKind ?? .other,
                              title: sourceTitle, url: sourceURL.flatMap(URL.init(string:)))
        }

        /// The entry as it reads in the note now; nil when it was deleted there.
        func text() -> String? {
            guard let s = try? String(contentsOf: noteURL, encoding: .utf8) else { return nil }
            if createdFile { return s }
            guard let r = s.range(of: anchor, options: .backwards) else { return nil }
            let end = s.index(r.lowerBound, offsetBy: length, limitedBy: s.endIndex) ?? s.endIndex
            return String(s[r.lowerBound..<end])
        }
    }

    /// Off during --selftest unless a test turns it on with its own folder.
    static var enabled = true
    static var directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jot/captures", isDirectory: true)

    private static func file(for date: Date) -> URL {
        directory.appendingPathComponent(MomentFormat.string(date, format: "YYYY-MM") + ".jsonl")
    }

    private static func load(_ url: URL) -> [Item] {
        guard let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return s.split(separator: "\n").compactMap { try? dec.decode(Item.self, from: Data($0.utf8)) }
    }

    private static func save(_ items: [Item], to url: URL) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let lines = items.compactMap { (try? enc.encode($0)).flatMap { String(data: $0, encoding: .utf8) } }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func anchor(_ entry: String) -> String { String(entry.prefix(200)) }

    /// Called for every write. An amend (same note, entry grown from the previous one) updates that item.
    static func record(_ e: History.Entry, previous: History.Entry?, date: Date = Date()) {
        guard enabled else { return }
        let url = file(for: date)
        var items = load(url)
        if let prev = previous, prev.note == e.note, e.entry.hasPrefix(prev.entry),
           let i = items.lastIndex(where: { $0.notePath == prev.note.path && $0.anchor == anchor(prev.entry) }) {
            items[i].anchor = anchor(e.entry)
            items[i].length = e.entry.count
            items[i].files = e.files.map(\.path)
            save(items, to: url)
            return
        }
        let daily = Prefs.shared.vaultURL.map { DailyNoteWriter(vault: $0, attachmentOverride: "").noteURL(for: date).standardizedFileURL.path == e.note.standardizedFileURL.path } ?? false
        let s = e.source
        items.append(Item(id: UUID().uuidString, date: date, notePath: e.note.path, daily: daily, createdFile: e.createdFile,
                          anchor: anchor(e.entry), length: e.entry.count, files: e.files.map(\.path), summary: e.summary,
                          sourceApp: s?.app, sourceBundle: s?.bundleID, sourceKind: s?.kind, sourceTitle: s?.title,
                          sourceURL: s?.url?.absoluteString, sourceMarkdown: s?.markdown))
        save(items, to: url)
    }

    static func remove(_ e: History.Entry) {
        guard enabled else { return }
        let a = anchor(e.entry)
        for url in [file(for: Date()), file(for: Date().addingTimeInterval(-86400 * 31))] {
            var items = load(url)
            guard let i = items.lastIndex(where: { $0.notePath == e.note.path && $0.anchor == a }) else { continue }
            items.remove(at: i)
            save(items, to: url)
            return
        }
    }

    /// Captures made on that calendar day that are still in their notes, oldest first.
    static func items(on day: Date) -> [Item] {
        let cal = Calendar.current
        return load(file(for: day))
            .filter { cal.isDate($0.date, inSameDayAs: day) && $0.text() != nil }
            .sorted { $0.date < $1.date }
    }
}
