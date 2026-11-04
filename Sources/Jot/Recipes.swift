import Foundation
import KeyboardShortcuts

/// A capture scene ("场景"): a shortcut that opens the panel aimed at a place, or saves the selection there
/// directly. Kept deliberately small (QuickAdd-like, minus the configuration).
struct Recipe: Codable, Identifiable, Hashable {
    enum Mode: String, Codable { case panel, capture }

    var id = UUID().uuidString
    var name: String
    var symbol: String
    var destination: Destination
    var mode: Mode = .panel
    var asTask = false

    var shortcutName: KeyboardShortcuts.Name { .init("recipe-\(id)") }

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "未命名场景" : n
    }

    /// Who else already uses this shortcut (⌘⇧J, ⌘⇧K or another scene)?
    static func conflict(_ shortcut: KeyboardShortcuts.Shortcut, excluding id: String) -> String? {
        if KeyboardShortcuts.getShortcut(for: .capture) == shortcut { return "打开输入框" }
        if KeyboardShortcuts.getShortcut(for: .quickSave) == shortcut { return "收录选中内容" }
        return Prefs.shared.recipes.first { $0.id != id && KeyboardShortcuts.getShortcut(for: $0.shortcutName) == shortcut }?.displayName
    }

    /// Suggestions offered in "添加场景": plain notes at the vault root, so they work in any vault or folder
    /// without assuming a folder structure. Created on first use.
    static let presets: [Recipe] = [
        Recipe(name: "灵感", symbol: "lightbulb", destination: Destination(kind: .note, path: "灵感.md")),
        Recipe(name: "待办", symbol: "checklist", destination: Destination(kind: .note, path: "待办.md"), asTask: true),
        Recipe(name: "读书摘录", symbol: "book", destination: Destination(kind: .note, path: "读书摘录.md"), mode: .capture),
        Recipe(name: "稍后读", symbol: "bookmark", destination: Destination(kind: .note, path: "稍后读.md"), mode: .capture),
        Recipe(name: "工作日志", symbol: "briefcase", destination: Destination(kind: .note, path: "工作日志.md")),
    ]

    static let symbols = ["lightbulb", "checklist", "book", "bookmark", "briefcase", "quote.opening",
                          "star", "heart", "flag", "tag", "folder", "doc.text"]
    static let maxCount = 6

    /// "Inbox/灵感.md", "读书/（新笔记）", "今日日记"
    var destinationLabel: String { Self.label(destination) }

    static func label(_ d: Destination) -> String {
        switch d.kind {
        case .daily: return "今日日记"
        case .note: return d.path
        case .folder: return (d.path.isEmpty ? "仓库根目录" : d.path) + "/（新笔记）"
        }
    }

    /// Typed text → destination: "a/b.md" or "a/b" → note, "a/b/" → new note in folder, "今日日记" → daily.
    static func parse(_ text: String) -> Destination? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.contains("..") { return nil }
        if t == "今日日记" { return .daily }
        if t.hasSuffix("/（新笔记）") { return Destination(kind: .folder, path: String(t.dropLast("/（新笔记）".count))) }
        if t.hasSuffix("/") { return Destination(kind: .folder, path: String(t.dropLast()).trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
        let path = t.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return Destination(kind: .note, path: path.lowercased().hasSuffix(".md") ? path : path + ".md")
    }
}

extension Notification.Name {
    static let recipesChanged = Notification.Name("ai.qiaomu.jot.recipesChanged")
}

extension Prefs {
    var recipes: [Recipe] {
        get {
            UserDefaults.standard.data(forKey: "recipes").flatMap { try? JSONDecoder().decode([Recipe].self, from: $0) } ?? []
        }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "recipes")
            NotificationCenter.default.post(name: .recipesChanged, object: nil)
        }
    }
}
