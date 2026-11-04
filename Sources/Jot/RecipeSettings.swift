import SwiftUI
import AppKit
import KeyboardShortcuts

/// Settings → 场景: a few named shortcuts, each aimed at a note or folder.
struct RecipeSettings: View {
    @State private var recipes = Prefs.shared.recipes
    @State private var index: [IndexEntry] = []
    /// Last deleted scene, restorable for a few seconds.
    @State private var deleted: (recipe: Recipe, position: Int, shortcut: KeyboardShortcuts.Shortcut?)?
    @State private var undoWork: DispatchWorkItem?

    var body: some View {
        Form {
            Section {
                Text("给常用的记录场景配一个快捷键，按一下就记到对应的笔记或文件夹。⌘⇧J / ⌘⇧K 仍然记到今日日记。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if recipes.isEmpty {
                    HStack(spacing: 8) {
                        Text("试试：").font(.system(size: 12)).foregroundStyle(.secondary)
                        ForEach(Recipe.presets, id: \.name) { p in
                            Button { add(p) } label: { Label(p.name, systemImage: p.symbol) }
                                .controlSize(.small)
                        }
                    }
                }
            }
            if let d = deleted {
                Section {
                    HStack {
                        Image(systemName: "trash").foregroundStyle(.secondary)
                        Text("已删除「\(d.recipe.displayName)」").font(.system(size: 12))
                        Spacer()
                        Button("撤销", action: undoDelete).controlSize(.small)
                    }
                }
            }
            ForEach(recipes) { r in
                RecipeCard(recipe: binding(r.id), index: index) { remove(r) }
            }
            if !recipes.isEmpty && recipes.count < Recipe.maxCount {
                Section {
                    Menu {
                        ForEach(Recipe.presets.filter { p in !recipes.contains { $0.name == p.name } }, id: \.name) { p in
                            Button { add(p) } label: { Label(p.name, systemImage: p.symbol) }
                        }
                        Divider()
                        Button("空白场景") {
                            add(Recipe(name: "新场景", symbol: "star", destination: Destination(kind: .note, path: "随记.md")))
                        }
                    } label: { Label("添加场景", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: (recipes.isEmpty ? 200 : min(640, 170 + CGFloat(recipes.count) * 214)) + (deleted == nil ? 0 : 50))
        .onChange(of: recipes) { Prefs.shared.recipes = $0 }
        .onAppear(perform: loadIndex)
    }

    private func loadIndex() {
        guard let vault = Prefs.shared.vaultURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let idx = VaultIndex.scan(vault)
            DispatchQueue.main.async { index = idx }
        }
    }

    /// New scenes get a free ⌃⌥1…6 right away so they work without any setup; change it any time.
    private func add(_ preset: Recipe) {
        guard recipes.count < Recipe.maxCount else { return }
        var r = preset
        r.id = UUID().uuidString
        let keys: [KeyboardShortcuts.Key] = [.one, .two, .three, .four, .five, .six]
        let used = Set(recipes.compactMap { KeyboardShortcuts.getShortcut(for: $0.shortcutName) })
        if let key = keys.map({ KeyboardShortcuts.Shortcut($0, modifiers: [.control, .option]) }).first(where: { !used.contains($0) }) {
            KeyboardShortcuts.setShortcut(key, for: r.shortcutName)
        }
        recipes.append(r)
    }

    /// Looks the scene up by id on every access: positional bindings crash when a scene is deleted.
    private func binding(_ id: String) -> Binding<Recipe> {
        Binding(get: { recipes.first { $0.id == id } ?? Recipe(name: "", symbol: "star", destination: .daily) },
                set: { v in if let i = recipes.firstIndex(where: { $0.id == id }) { recipes[i] = v } })
    }

    private func remove(_ r: Recipe) {
        NSApp.keyWindow?.makeFirstResponder(nil)       // end any edit inside the card first
        DispatchQueue.main.async {
            guard let i = recipes.firstIndex(where: { $0.id == r.id }) else { return }
            deleted = (r, i, KeyboardShortcuts.getShortcut(for: r.shortcutName))
            KeyboardShortcuts.reset(r.shortcutName)
            withAnimation(.easeOut(duration: 0.15)) { recipes.removeAll { $0.id == r.id } }
            undoWork?.cancel()
            let w = DispatchWorkItem { withAnimation { deleted = nil } }
            undoWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: w)
        }
    }

    private func undoDelete() {
        guard let d = deleted, recipes.count < Recipe.maxCount else { return }
        undoWork?.cancel()
        if let s = d.shortcut, Recipe.conflict(s, excluding: d.recipe.id) == nil { KeyboardShortcuts.setShortcut(s, for: d.recipe.shortcutName) }
        withAnimation(.easeOut(duration: 0.15)) {
            recipes.insert(d.recipe, at: min(d.position, recipes.count))
            deleted = nil
        }
    }
}

private struct RecipeCard: View {
    @Binding var recipe: Recipe
    let index: [IndexEntry]
    let onDelete: () -> Void

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Menu {
                    ForEach(Recipe.symbols, id: \.self) { s in
                        Button { recipe.symbol = s } label: { Image(systemName: s) }
                    }
                } label: {
                    Image(systemName: recipe.symbol).font(.system(size: 14, weight: .medium)).frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("换个图标")
                TextField("", text: $recipe.name, prompt: Text("场景名称"))
                    .labelsHidden().textFieldStyle(.plain).multilineTextAlignment(.leading)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("删除这个场景")
            }
            KeyboardShortcuts.Recorder("快捷键", name: recipe.shortcutName) { shortcut in
                guard let shortcut, let other = Recipe.conflict(shortcut, excluding: recipe.id) else { return }
                KeyboardShortcuts.setShortcut(nil, for: recipe.shortcutName)
                let alert = NSAlert()
                alert.messageText = "这个快捷键已被「\(other)」使用"
                alert.informativeText = "请换一个组合。"
                alert.runModal()
            }
            Picker("按下后", selection: $recipe.mode) {
                Text("打开输入框").tag(Recipe.Mode.panel)
                Text("直接收录").tag(Recipe.Mode.capture)
            }
            .pickerStyle(.segmented)
            .help("直接收录：像 ⌘⇧K 一样不弹窗，收选中内容、剪贴板或刚截的屏")
            LabeledContent("保存到") {
                DestinationField(destination: $recipe.destination, index: index)
            }
            Toggle("存为待办（- [ ]）", isOn: $recipe.asTask)
        }
    }
}

/// One field: type to get suggestions from the whole vault (fuzzy / pinyin), or browse.
/// A path that doesn't exist yet is fine; it's created on first use.
struct DestinationField: View {
    @Binding var destination: Destination
    let index: [IndexEntry]
    @State private var text = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    private var suggestions: [Destination] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard editing, !q.isEmpty, q != Recipe.label(destination) else { return [] }
        var out = Array(VaultIndex.search(index, q, limit: 6))
        if "今日日记 daily jrrj".contains(q.lowercased()) { out.insert(.daily, at: 0) }
        return out
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("笔记或文件夹，如 Inbox/灵感.md"))
                    .multilineTextAlignment(.trailing)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: text) { _ in if focused { editing = true } }
                    .onChange(of: focused) { f in if !f { commit() } }
                Button("浏览…", action: browse).controlSize(.small)
            }
            if let status, suggestions.isEmpty {
                Label(status.text, systemImage: status.warn ? "plus.circle" : "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { d in
                        Button { pick(d) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: d.symbol).frame(width: 14)
                                Text(Recipe.label(d)).lineLimit(1).truncationMode(.head)
                                Spacer()
                                Text(d.kind == .folder ? "新建笔记" : d.kind == .daily ? "" : "追加").foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
        }
        .onAppear { text = Recipe.label(destination) }
    }

    /// What will happen on save, so a typo shows up now rather than as a stray file later.
    private var status: (text: String, warn: Bool)? {
        guard !editing, let vault = Prefs.shared.vaultURL else { return nil }
        switch destination.kind {
        case .daily: return ("记到当天的日记", false)
        case .folder:
            let exists = FileManager.default.fileExists(atPath: vault.appendingPathComponent(destination.path).path)
            return (exists ? "在这个文件夹里新建笔记" : "文件夹还不存在，第一次保存时创建", !exists)
        case .note:
            if destination.path.contains("..") { return ("路径不能跳出仓库", true) }
            let exists = FileManager.default.fileExists(atPath: vault.appendingPathComponent(destination.path).path)
            return (exists ? "追加到这篇笔记末尾" : "笔记还不存在，第一次保存时创建", !exists)
        }
    }

    private func pick(_ d: Destination) {
        destination = d
        text = Recipe.label(d)
        editing = false
    }

    private func commit() {
        editing = false
        if let d = Recipe.parse(text) { destination = d }
        text = Recipe.label(destination)
    }

    private func browse() {
        guard let vault = Prefs.shared.vaultURL else { return }
        let p = NSOpenPanel()
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.canCreateDirectories = true
        p.allowedContentTypes = [.init(filenameExtension: "md")!, .folder]
        p.directoryURL = vault
        p.message = "选择一篇笔记（追加到末尾）或一个文件夹（新建笔记）"
        guard p.runModal() == .OK, let u = p.url else { return }
        let root = vault.standardizedFileURL.path, path = u.standardizedFileURL.path
        guard path == root || path.hasPrefix(root + "/") else { NSSound.beep(); return }
        let rel = path == root ? "" : String(path.dropFirst(root.count + 1))
        let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        pick(Destination(kind: isDir ? .folder : .note, path: rel))
    }
}
