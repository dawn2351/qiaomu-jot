import Foundation

/// Where a capture is saved: today's daily note (default), an existing note, or a new note in a folder.
struct Destination: Codable, Hashable {
    enum Kind: String, Codable { case daily, note, folder }
    var kind: Kind
    /// Vault-relative path: the note file (with .md) or the folder ("" = vault root).
    var path: String

    static let daily = Destination(kind: .daily, path: "")

    var name: String {
        switch kind {
        case .daily: return "今日日记"
        case .note: return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        case .folder: return path.isEmpty ? "仓库根目录" : (path as NSString).lastPathComponent
        }
    }
    /// Parent folder shown in grey next to the name.
    var parent: String {
        let p = (path as NSString).deletingLastPathComponent
        return kind == .daily || p.isEmpty ? "" : p
    }
    var symbol: String {
        switch kind {
        case .daily: return "calendar"
        case .note: return "doc.text"
        case .folder: return "folder"
        }
    }
}

enum VaultIndex {
    /// Folders and Markdown notes in the vault (hidden folders such as .obsidian/.trash skipped).
    static func scan(_ vault: URL, limit: Int = 30_000) -> [Destination] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: vault, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let root = vault.standardizedFileURL.path
        var out = [Destination(kind: .folder, path: "")]
        for case let url as URL in en {
            if out.count >= limit { break }
            let full = url.standardizedFileURL.path
            guard full.count > root.count + 1 else { continue }
            let rel = String(full.dropFirst(root.count + 1))
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                out.append(Destination(kind: .folder, path: rel))
            } else if url.pathExtension.lowercased() == "md" {
                out.append(Destination(kind: .note, path: rel))
            }
        }
        return out
    }

    /// Every query word must appear in the path; file-name prefix matches rank first, then shorter paths.
    static func search(_ items: [Destination], _ query: String, limit: Int = 50) -> [Destination] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let scored: [(Destination, Int)] = items.compactMap { d in
            let path = d.path.lowercased()
            guard words.allSatisfy({ path.contains($0) }) else { return nil }
            let name = d.name.lowercased()
            var score = d.path.count
            if name.hasPrefix(words[0]) { score -= 1000 } else if name.contains(words[0]) { score -= 500 }
            return (d, score)
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
    }
}

enum NoteNaming {
    /// Obsidian-safe file name: no path separators or link-breaking characters.
    static func sanitize(_ title: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]").union(.newlines).union(.controlCharacters)
        var s = title.components(separatedBy: bad).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".")))
        if s.count > 80 { s = String(s.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return s
    }

    /// Title for a new note: the first meaningful line of text, else a timestamp.
    static func autoTitle(from text: String, date: Date = Date()) -> String {
        for line in text.components(separatedBy: "\n") {
            let t = line.replacingOccurrences(of: #"^\s*(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+\.\s+|[-—]\s+)"#,
                                              with: "", options: .regularExpression)
                .replacingOccurrences(of: #"[*_=~`]"#, with: "", options: .regularExpression)
            let s = sanitize(t)
            if !s.isEmpty && !s.hasPrefix("!") { return s.count > 40 ? String(s.prefix(40)) : s }
        }
        return "随记 " + MomentFormat.string(date, format: "YYYY-MM-DD HHmm")
    }
}

struct RecentDestination: Codable, Equatable {
    var destination: Destination
    var date: Date
}

extension Prefs {
    private static let recentsKey = "recentDestinations.v2"

    private var allRecents: [String: [RecentDestination]] {
        UserDefaults.standard.data(forKey: Self.recentsKey)
            .flatMap { try? JSONDecoder().decode([String: [RecentDestination]].self, from: $0) } ?? [:]
    }

    /// Destinations chosen in the picker for the current vault (daily note excluded), newest first.
    var recentDestinations: [RecentDestination] { allRecents[vaultPath] ?? [] }

    func remember(_ d: Destination) {
        guard d.kind != .daily else { return }
        var all = allRecents
        var list = all[vaultPath] ?? []
        list.removeAll { $0.destination == d }
        list.insert(RecentDestination(destination: d, date: Date()), at: 0)
        all[vaultPath] = Array(list.prefix(12))
        UserDefaults.standard.set(try? JSONEncoder().encode(all), forKey: Self.recentsKey)
    }

    /// Recently used folders plus the notes captures were recently written to (any note,
    /// including ones created here), excluding daily notes, newest first.
    func recentPlaces(vault: URL, limit: Int = 8) -> [RecentDestination] {
        let root = vault.standardizedFileURL.path
        let dailyFolder = DailyNoteConfig.load(vault: vault).folder
        var out = recentDestinations
        for item in RecentCaptures.items {
            let path = URL(fileURLWithPath: item.notePath).standardizedFileURL.path
            guard path.hasPrefix(root + "/"), FileManager.default.fileExists(atPath: path) else { continue }
            let rel = String(path.dropFirst(root.count + 1))
            let folder = (rel as NSString).deletingLastPathComponent
            if !dailyFolder.isEmpty && (folder == dailyFolder || folder.hasPrefix(dailyFolder + "/")) { continue }
            let d = Destination(kind: .note, path: rel)
            if let i = out.firstIndex(where: { $0.destination == d }) {
                if out[i].date < item.date { out[i].date = item.date }
            } else {
                out.append(RecentDestination(destination: d, date: item.date))
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(limit))
    }

    var lastDestination: Destination {
        get {
            UserDefaults.standard.data(forKey: "lastDestination")
                .flatMap { try? JSONDecoder().decode(Destination.self, from: $0) } ?? .daily
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "lastDestination") }
    }
}
