import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import AVFoundation

// MARK: - Model

final class CaptureModel: ObservableObject {
    @Published var text = ""
    @Published var attachments: [URL] = []
    @Published var error: String?
    @Published var saved = false
    /// The editor was prefilled with an unsent draft from last time.
    @Published var restoredDraft = false
    var savedTo: String?
    @Published var vaultPath = Prefs.shared.vaultPath
    @Published var todayCount = 0
    @Published var editorHeight: CGFloat = 76
    @Published var tagQuery: String?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?
    var completeTag: ((String) -> Void)?
    var focusEditor: (() -> Void)?
    var onPreview: ((Int) -> Void)?
    var format: ((MarkdownCommand) -> Void)?
    /// Set when adding a follow-up thought to the entry just saved.
    var amend: History.Entry?
    /// Where the capture came from; shown as a chip and written per the entry format when included.
    @Published var source: SourceInfo?
    @Published var includeSource = false
    @Published var dropTargeted = false

    struct ClipOffer {
        let label: String
        let apply: () -> Void
    }
    /// A just-copied image / file / video, attachable with one click.
    @Published var clipOffer: ClipOffer?
    var dropHandler: MediaDropHandler?

    // Save destination
    @Published var destination: Destination = Prefs.shared.rememberDestination ? Prefs.shared.lastDestination : .daily
    @Published var noteTitle = ""
    /// The scene this panel was opened for (shown in the bar; its todo setting applies).
    @Published var recipe: Recipe?

    func apply(_ r: Recipe?) {
        guard let r, amend == nil else { return }
        recipe = r
        destination = r.destination
    }
    @Published var picking = false
    @Published var pickerQuery = "" { didSet { pickerSelection = 0; scheduleContentSearch() } }
    /// Notes whose contents match the query (Spotlight), with the matching line.
    @Published var contentHits: [(Destination, String)] = []
    private let contentSearch = ContentSearch()
    private var contentWork: DispatchWorkItem?
    @Published var pickerSelection = 0
    @Published var indexLoaded = false
    var vaultIndex: [IndexEntry] = []
    /// Design snapshots only.
    var previewRecents: [RecentDestination]?
    private static var indexCache: [String: [IndexEntry]] = [:]
    @Published var showFormatBar = Prefs.shared.showFormatBar {
        didSet { Prefs.shared.showFormatBar = showFormatBar }
    }
    private var tempFiles: [URL] = []

    init() {
        refreshCount()
        dropHandler = MediaDropHandler(model: self)
        checkVault()
    }

    /// A moved, renamed or deleted save folder is reported up front instead of failing on save.
    func checkVault() {
        let p = Prefs.shared
        error = p.vaultPath.isEmpty ? "还没选择保存位置" : (p.vaultExists ? nil : "保存位置不存在了")
    }

    private func refreshCount() { todayCount = Prefs.shared.dailyCount() }

    // MARK: Vault switching

    func switchVault(_ path: String) {
        Prefs.shared.vaultPath = path
        if !FolderMode.isObsidianVault(URL(fileURLWithPath: path)) { Prefs.shared.rememberFolder(path) }
        vaultPath = path
        checkVault()
        destination = .daily
        vaultIndex = []
        indexLoaded = false
        refreshCount()
    }

    // MARK: Destination picker

    struct PickerRow: Identifiable {
        enum Kind { case header(String), item(Int, PickerItem) }
        let id: String
        let kind: Kind
    }

    struct PickerItem {
        let destination: Destination
        var date: Date? = nil
        var snippet: String? = nil
    }

    /// Flat, keyboard-navigable list: daily note, recents and top-level folders; or search results
    /// (fuzzy names / pinyin / aliases across the whole vault, then notes whose contents match).
    var pickerItems: [(section: String, items: [PickerItem])] {
        let q = pickerQuery.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            let recents = previewRecents ?? Prefs.shared.vaultURL.map { Prefs.shared.recentPlaces(vault: $0) } ?? []
            let used = Set(recents.map(\.destination))
            let folders = vaultIndex.map(\.destination).filter { $0.kind == .folder && !$0.path.isEmpty && !$0.path.contains("/") && !used.contains($0) }
            let scenes = Prefs.shared.recipes.map { PickerItem(destination: $0.destination, snippet: "场景 · \($0.displayName)") }
            return [("默认", [PickerItem(destination: .daily)]),
                    ("场景", scenes),
                    ("最近", recents.map { PickerItem(destination: $0.destination, date: $0.date) }),
                    ("文件夹", [PickerItem(destination: Destination(kind: .folder, path: ""))]
                        + folders.prefix(30).map { PickerItem(destination: $0) })].filter { !$0.items.isEmpty }
        }
        var results = VaultIndex.search(vaultIndex, q)
        if "今日日记 daily today jrrj".contains(q.lowercased()) { results.insert(.daily, at: 0) }
        let named = Set(results)
        let content = contentHits.filter { !named.contains($0.0) }.map { PickerItem(destination: $0.0, snippet: $0.1) }
        return [("笔记与文件夹", results.map { PickerItem(destination: $0) }), ("内容", content)].filter { !$0.items.isEmpty }
    }

    private func scheduleContentSearch() {
        contentWork?.cancel()
        contentSearch.cancel()
        let q = VaultIndex.normalize(pickerQuery)
        let long = q.count >= (q.allSatisfy(\.isASCII) ? 3 : 2)
        guard picking, long, let vault = Prefs.shared.vaultURL else { contentHits = []; return }
        let work = DispatchWorkItem { [weak self] in
            self?.contentSearch.run(q, in: vault) { hits in
                guard let self, VaultIndex.normalize(self.pickerQuery) == q else { return }
                self.contentHits = hits
            }
        }
        contentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    var pickerRows: [PickerRow] {
        var rows: [PickerRow] = [], i = 0
        for (section, items) in pickerItems {
            rows.append(PickerRow(id: "h-" + section, kind: .header(section)))
            for item in items {
                let d = item.destination
                rows.append(PickerRow(id: "\(section)-\(d.kind.rawValue)-\(d.path)", kind: .item(i, item)))
                i += 1
            }
        }
        return rows
    }

    private var pickerFlat: [Destination] { pickerItems.flatMap { $0.items.map(\.destination) } }

    func openPicker() {
        guard amend == nil else { return }
        pickerQuery = ""
        picking = true
        let path = vaultPath
        if let cached = Self.indexCache[path] { vaultIndex = cached; indexLoaded = true }
        guard let vault = Prefs.shared.vaultURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let idx = VaultIndex.scan(vault)
            DispatchQueue.main.async {
                Self.indexCache[path] = idx
                guard self.vaultPath == path else { return }
                self.vaultIndex = idx
                self.indexLoaded = true
            }
        }
    }

    func closePicker() {
        picking = false
        contentSearch.cancel()
        focusEditor?()
    }

    func movePicker(_ delta: Int) {
        let n = pickerFlat.count
        guard n > 0 else { return }
        pickerSelection = (pickerSelection + delta + n) % n
    }

    func choosePicked() {
        let flat = pickerFlat
        guard flat.indices.contains(pickerSelection) else { return }
        choose(flat[pickerSelection])
    }

    func choose(_ d: Destination) {
        destination = d
        if recipe?.destination != d { recipe = Prefs.shared.recipes.first { $0.destination == d } }
        picking = false
        error = nil
        DispatchQueue.main.async { self.focusEditor?() }
    }

    var autoTitle: String { NoteNaming.autoTitle(from: text) }

    var destinationLabel: String {
        if let recipe, recipe.destination == destination { return recipe.displayName }
        return destination.kind == .daily ? (Self.todayNote?.deletingPathExtension().lastPathComponent ?? "今日日记") : destination.name
    }

    func appendText(_ s: String) {
        let t = text.trimmingCharacters(in: .newlines)
        text = t.isEmpty ? s : t + "\n" + s
        focusEditor?()
    }

    func showVaultMenu() {
        let menu = NSMenu()
        let folders = Prefs.shared.knownFolders
        for v in folders {
            let item = MenuAction.item((v as NSString).lastPathComponent) { [weak self] in self?.switchVault(v) }
            item.state = v == vaultPath ? .on : .off
            item.toolTip = (v as NSString).abbreviatingWithTildeInPath
            let glyph = FolderMode.isObsidianVault(URL(fileURLWithPath: v)) ? "brands/obsidian" : "lucide/folder"
            if let img = SourceIcons.image(named: glyph)?.copy() as? NSImage {
                img.size = NSSize(width: 14, height: 14)
                item.image = img
            }
            menu.addItem(item)
        }
        if !folders.isEmpty { menu.addItem(.separator()) }
        menu.addItem(MenuAction.item("选择文件夹…") { [weak self] in
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
            p.message = "选择 Obsidian 仓库，或任意用来保存 Markdown 的文件夹"
            NSApp.activate(ignoringOtherApps: true)
            if p.runModal() == .OK, let u = p.url { self?.switchVault(u.path) }
        })
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        focusEditor?()
    }

    static var todayNote: URL? {
        Prefs.shared.vaultURL.map { DailyNoteWriter(vault: $0, attachmentOverride: "").noteURL(for: Date()) }
    }

    func adoptTemp(_ dirs: [URL]) { tempFiles += dirs }

    func discardTemp() {
        for t in tempFiles { try? FileManager.default.removeItem(at: t) }
        tempFiles = []
    }


    func add(urls: [URL]) {
        for u in urls where !attachments.contains(u) { attachments.append(u) }
    }

    /// Pasteboard / drag types we keep byte-for-byte (GIFs stay animated), most specific first.
    static let mediaTypes: [(type: UTType, ext: String)] = [
        (.gif, "gif"), (.png, "png"), (.jpeg, "jpg"), (.heic, "heic"), (.webP, "webp"),
        (.mpeg4Movie, "mp4"), (.quickTimeMovie, "mov"),
    ]

    /// Media bytes (clipboard / dragged from a browser) -> temp file named like Obsidian's own pastes.
    func add(imageData data: Data, ext: String) {
        let f = DateFormatter(); f.dateFormat = "yyyyMMddHHmmss"
        let kind = UTType(filenameExtension: ext)?.conforms(to: .movie) == true ? "video" : "image"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = dir.appendingPathComponent("Pasted \(kind) \(f.string(from: Date())).\(ext)")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url)
            tempFiles.append(dir); attachments.append(url)
        } catch { self.error = "无法读取图片" }
    }

    func add(image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        add(imageData: png, ext: "png")
    }

    /// Consumes files or images on the pasteboard. Text (including rich text that also carries a
    /// picture of itself, e.g. from Word or Keynote) is left for the text view.
    func pasteIfMedia() -> Bool {
        let pb = NSPasteboard.general
        if let files = PasteboardFiles.usable(pb) { add(urls: files); return true }
        let types = Self.mediaTypes.map { NSPasteboard.PasteboardType($0.type.identifier) } + [.tiff]
        guard let type = pb.availableType(from: types) else { return false }
        let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let textIsIncidental = s.isEmpty || (!s.contains(where: \.isWhitespace) && URL(string: s)?.scheme != nil)
        guard textIsIncidental, let data = pb.data(forType: type) else { return false }
        if let ext = Self.mediaTypes.first(where: { $0.type.identifier == type.rawValue })?.ext {
            add(imageData: data, ext: ext)
        } else {
            guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else { return false }
            add(imageData: png, ext: "png")
        }
        return true
    }

    func chooseFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        if p.runModal() == .OK { add(urls: p.urls) }
        focusEditor?()
    }

    private static let taskPrefix = try! NSRegularExpression(pattern: #"^\s*(?:- )?(?:\[ ?\]|【 ?】)\s*"#)

    /// Typing `[] ` (or `【】` with Chinese punctuation) at the start turns the entry into a todo.
    var isTask: Bool {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first,
              Self.taskPrefix.firstMatch(in: first, range: NSRange(location: 0, length: (first as NSString).length)) != nil
        else { return false }
        return !lines.dropFirst().contains { Self.taskPrefix.firstMatch(in: $0, range: NSRange(location: 0, length: ($0 as NSString).length)) != nil }
    }

    private var bodyText: String {
        guard isTask else { return text }
        return Self.taskPrefix.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length),
                                                        withTemplate: "")
    }

    private var savedSource: SourceInfo? { includeSource ? source : nil }

    var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }

    var recentTags: [String] { Prefs.shared.recentTags.split(separator: " ").map(String.init) }

    var tagSuggestions: [String] {
        guard let q = tagQuery?.lowercased() else { return [] }
        return Array(recentTags.filter { $0.lowercased().hasPrefix(q) && $0.lowercased() != q }.prefix(5))
    }

    private func rememberTags() {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\w/])#[^\s#]+"#) else { return }
        let ns = text as NSString
        let found = re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
        guard !found.isEmpty else { return }
        var seen = Set<String>()
        let all = (found + recentTags).filter { seen.insert($0).inserted }
        Prefs.shared.recentTags = all.prefix(12).joined(separator: " ")
    }

    @Published var saving = false

    func save() {
        guard Prefs.shared.vaultURL != nil else { error = CaptureError.noVault.localizedDescription; return }
        guard canSave, !saved, !saving else { return }
        guard Prefs.shared.ocrImages, attachments.contains(where: { MediaKind($0) == .image }) else { write(ocr: [:]); return }
        saving = true
        OCR.recognize(attachments) { [weak self] map in
            self?.saving = false
            self?.write(ocr: map)
        }
    }

    private func write(ocr: [String: String]) {
        let prefs = Prefs.shared
        guard let vault = prefs.vaultURL else { return }
        let writer = DailyNoteWriter(vault: vault, attachmentOverride: prefs.attachmentFolder)
        History.skipped = []
        do {
            let note: URL
            if let amend {
                try writer.amend(amend, text: text, attachments: attachments, ocr: ocr)
                note = amend.note
            } else {
                switch destination.kind {
                case .daily:
                    note = try writer.append(content: bodyText, attachments: attachments, ocr: ocr, source: savedSource,
                                             asTask: isTask || recipe?.asTask == true, heading: prefs.insertHeading)
                    _ = prefs.dailyCount(1)
                case .note:
                    note = try writer.append(content: bodyText, attachments: attachments, ocr: ocr, source: savedSource,
                                             asTask: isTask || recipe?.asTask == true, to: vault.appendingPathComponent(destination.path))
                case .folder:
                    let title = noteTitle.trimmingCharacters(in: .whitespaces).isEmpty ? autoTitle : NoteNaming.sanitize(noteTitle)
                    note = try writer.createNote(folder: destination.path, title: title.isEmpty ? autoTitle : title,
                                                 content: text, attachments: attachments, ocr: ocr, source: savedSource)
                }
                prefs.remember(destination)
                if prefs.rememberDestination { prefs.lastDestination = destination }
                prefs.draft = ""
            }
            savedTo = amend == nil && destination.kind != .daily
                ? (destination.kind == .folder ? note.deletingPathExtension().lastPathComponent : destination.name) : nil
            rememberTags()
            discardTemp()
            prefs.didFirstCapture = true
            if prefs.openAfterSave { Self.open(note: note, vault: vault) }
            if !History.skipped.isEmpty {
                Toast.show("已保存，但有 \(History.skipped.count) 个文件读不到", detail: AppDelegate.protectedHint, style: .warning, duration: 6)
            }
            SaveSound.play(prefs.saveSound)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            withAnimation(.easeOut(duration: 0.18)) { saved = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.onDone?() }
        } catch {
            self.error = "保存失败：\(error.localizedDescription)"
        }
    }

    /// Obsidian vault + Obsidian installed → open in Obsidian; otherwise the default Markdown app.
    static func open(note: URL, vault: URL) {
        guard FolderMode.isObsidianVault(vault), FolderMode.obsidianInstalled else {
            NSWorkspace.shared.open(note); return
        }
        let rel = String(note.path.dropFirst(vault.path.count + 1))
        var c = URLComponents(string: "obsidian://open")!
        c.queryItems = [.init(name: "vault", value: vault.lastPathComponent),
                        .init(name: "file", value: rel)]
        if let u = c.url { NSWorkspace.shared.open(u) }
    }
}

// MARK: - Theme (Vercel / Geist)

enum Theme {
    private static func dyn(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }
    private static func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(v >> 16 & 0xff) / 255, green: CGFloat(v >> 8 & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255, alpha: a)
    }
    static let nsBackground = dyn(hex(0xFFFFFF), hex(0x0A0A0A))
    static let nsText = dyn(hex(0x0A0A0A), hex(0xEDEDED))
    static let nsPlaceholder = dyn(hex(0xA8A8A8), hex(0x5C5C5C))
    static let nsMuted = dyn(hex(0x666666), hex(0xA1A1A1))
    static let nsMarker = dyn(hex(0xC2C2C2), hex(0x4F4F4F))
    static let nsCode = dyn(hex(0xF4F4F4), hex(0x1A1A1A))
    static let nsHighlight = dyn(hex(0xFFF0B3), hex(0x4A3C00))

    static let background = Color(nsColor: nsBackground)
    static let bar = Color(nsColor: dyn(hex(0xFAFAFA), hex(0x111111)))
    static let border = Color(nsColor: dyn(hex(0xEAEAEA), hex(0x262626)))
    static let text = Color(nsColor: nsText)
    static let muted = Color(nsColor: nsMuted)
    static let subtle = Color(nsColor: dyn(hex(0x8F8F8F), hex(0x6E6E6E)))
    static let hover = Color(nsColor: dyn(hex(0x000000, 0.05), hex(0xFFFFFF, 0.07)))
    static let inverse = Color(nsColor: nsBackground)
    static let radius: CGFloat = 12

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .semibold ? "Geist-SemiBold" : weight == .medium ? "Geist-Medium" : "Geist-Regular"
        return .custom(name, size: size)
    }
    static func mono(_ size: CGFloat) -> Font { .custom("GeistMono-Medium", size: size) }
    /// Geist for Latin, PingFang at the matching weight for CJK.
    static func nsFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let (latin, cjk) = weight >= .semibold ? ("Geist-SemiBold", "PingFangSC-Semibold")
            : weight >= .medium ? ("Geist-Medium", "PingFangSC-Medium") : ("Geist-Regular", "PingFangSC-Regular")
        guard NSFont(name: latin, size: size) != nil else { return .systemFont(ofSize: size, weight: weight) }
        let d = NSFontDescriptor(name: latin, size: size)
            .addingAttributes([.cascadeList: [NSFontDescriptor(name: cjk, size: size)]])
        return NSFont(descriptor: d, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }
    static func nsMono(_ size: CGFloat) -> NSFont {
        guard NSFont(name: "GeistMono-Regular", size: size) != nil else { return .monospacedSystemFont(ofSize: size, weight: .regular) }
        let d = NSFontDescriptor(name: "GeistMono-Regular", size: size)
            .addingAttributes([.cascadeList: [NSFontDescriptor(name: "PingFangSC-Regular", size: size)]])
        return NSFont(descriptor: d, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Registers the bundled Geist fonts (SIL OFL) for this process.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(f as CFURL, .process, nil)
        }
    }
}

// MARK: - View

struct CaptureView: View {
    @ObservedObject var model: CaptureModel

    var body: some View {
        VStack(spacing: 0) {
            if model.picking {
                DestinationPicker(model: model)
            } else {
                content
            }
            if model.showFormatBar && !model.picking {
                formatBar.transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            bar
        }
        .frame(width: 600)
        .background(WindowDragArea())          // drag the panel by any empty area
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            if !model.picking && !model.saved {
                CloseButton { model.onCancel?() }.padding(.top, 12).padding(.trailing, 12)
            }
        }
        .overlay { if model.dropTargeted { dropOverlay } }
        .overlay { if model.saved { savedOverlay } }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: model.dropTargeted)
        .animation(.easeOut(duration: 0.2), value: model.attachments)
        .animation(.easeOut(duration: 0.12), value: model.tagSuggestions)
        .animation(.easeOut(duration: 0.12), value: model.isTask)
        .animation(.easeOut(duration: 0.16), value: model.showFormatBar)
        .animation(.easeOut(duration: 0.14), value: model.picking)
        .animation(.easeOut(duration: 0.14), value: model.destination)
        .animation(.easeOut(duration: 0.12), value: model.includeSource)
    }

    private var content: some View {
            VStack(alignment: .leading, spacing: 12) {
                if model.destination.kind == .folder && model.amend == nil { titleField }
                CaptureTextView(model: model)
                    .frame(height: model.editorHeight)
                if model.restoredDraft && !model.text.isEmpty { draftNotice }
                if !model.tagSuggestions.isEmpty { tagRow }
                if model.clipOffer != nil || (model.source != nil && Prefs.shared.showSource) {
                    HStack(spacing: 8) {
                        if let source = model.source, Prefs.shared.showSource { sourceChip(source) }
                        if let offer = model.clipOffer { offerChip(offer) }
                    }
                }
                if !model.attachments.isEmpty { attachmentRow }
            }
            .padding(.leading, 20).padding(.trailing, 44).padding(.top, 18).padding(.bottom, 14)
    }

    private var draftNotice: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
            Text("已恢复上次未保存的草稿")
            Button("清空") {
                model.text = ""
                Prefs.shared.draft = ""
                model.restoredDraft = false
                model.focusEditor?()
            }
            .buttonStyle(.plain).foregroundStyle(Theme.text)
        }
        .font(Theme.sans(11, .medium)).foregroundStyle(Theme.subtle)
        .transition(.opacity)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 10, weight: .semibold))
                Text("新笔记 · \(model.destination.path.isEmpty ? "仓库根目录" : model.destination.path)")
            }
            .font(Theme.sans(11, .medium)).foregroundStyle(Theme.subtle)
            TextField("", text: $model.noteTitle, prompt: Text(model.autoTitle).foregroundColor(Theme.subtle))
                .textFieldStyle(.plain)
                .font(Theme.sans(20, .semibold))
                .foregroundStyle(Theme.text)
                .onSubmit { model.focusEditor?() }
        }
    }

    // MARK: Rows

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.tagSuggestions.enumerated()), id: \.element) { i, tag in
                Button { model.completeTag?(tag) } label: {
                    Text(tag).font(Theme.sans(12, .medium))
                        .foregroundStyle(i == 0 ? Theme.text : Theme.muted)
                        .padding(.horizontal, 8).frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(i == 0 ? Theme.hover : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
            }
            Kbd("Tab").padding(.leading, 4)
            Text("补全").font(Theme.sans(11)).foregroundStyle(Theme.subtle)
        }
        .transition(.opacity)
    }

    /// Source chip: app glyph + page title / file. Included: solid with ×. Suggested: dashed, click to include.
    private func sourceChip(_ source: SourceInfo) -> some View {
        HStack(spacing: 7) {
            SourceGlyph(bundleID: source.bundleID, kind: source.kind, size: 12,
                        color: model.includeSource ? Theme.text : Theme.subtle)
            if !model.includeSource {
                Text("附上来源").font(Theme.sans(12, .medium)).foregroundStyle(Theme.muted)
            }
            Text(source.label).font(Theme.sans(12)).foregroundStyle(model.includeSource ? Theme.muted : Theme.subtle)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 320, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            if model.includeSource {
                Button { model.includeSource = false } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.subtle)
                        .frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("这条不记录来源")
            }
        }
        .padding(.leading, 8).padding(.trailing, model.includeSource ? 4 : 9).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(model.includeSource ? Theme.hover : .clear))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border,
                 style: StrokeStyle(lineWidth: 1, dash: model.includeSource ? [] : [3, 3])))
        .contentShape(Rectangle())
        .onTapGesture { if !model.includeSource { model.includeSource = true } }
        .help(source.url?.absoluteString ?? source.app)
        .transition(.opacity)
    }

    private func offerChip(_ offer: CaptureModel.ClipOffer) -> some View {
        Button {
            offer.apply()
            model.clipOffer = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 11, weight: .medium))
                Text(offer.label).font(Theme.sans(12, .medium))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 9).frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.opacity)
    }

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(model.attachments.enumerated()), id: \.element) { i, url in
                    AttachmentCard(url: url, open: { model.onPreview?(i) }) { model.attachments.removeAll { $0 == url } }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Bar

    private var bar: some View {
        HStack(spacing: 2) {
            destination
            Spacer(minLength: 12)
            if model.isTask {
                Text("待办").font(Theme.sans(11, .medium)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7).frame(height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
            FormatToggle(active: model.showFormatBar) { model.showFormatBar.toggle() }
                .keyboardShortcut("/", modifiers: .command)
            IconButton(symbol: "paperclip", active: false, help: "添加附件 ⌘O") { model.chooseFiles() }
                .keyboardShortcut("o", modifiers: .command)
            saveButton.padding(.leading, 10)
        }
        .padding(.leading, 20).padding(.trailing, 12)
        .frame(height: 52)
        // The bar's colour would cover the root drag area, so it carries its own.
        .background { ZStack { Theme.bar; WindowDragArea() } }
    }

    private var destination: some View {
        HStack(spacing: 6) {
            if let e = model.error {
                Circle().fill(Color.red).frame(width: 6, height: 6)
                Text(e).font(Theme.sans(12)).foregroundStyle(Color.red).lineLimit(1)
                if !Prefs.shared.vaultExists {
                    Button("重新选择…") { model.showVaultMenu() }
                        .buttonStyle(.plain).font(Theme.sans(12, .medium)).foregroundStyle(Theme.text)
                }
            } else if let amend = model.amend {
                Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text("补充到").foregroundStyle(Theme.muted)
                Text(amend.summary).foregroundStyle(Theme.text).lineLimit(1)
            } else {
                SourceGlyph(bundleID: Prefs.shared.isObsidianVault ? "md.obsidian" : "", kind: .finder, size: 13, color: Theme.text)
                    .padding(.trailing, 1)
                    .help(Prefs.shared.isObsidianVault ? "Obsidian 仓库" : "普通文件夹 · 标准 Markdown")
                VaultButton(name: model.vaultPath.isEmpty ? "选择保存位置" : (model.vaultPath as NSString).lastPathComponent) {
                    model.showVaultMenu()
                }
                Text("/").foregroundStyle(Theme.subtle.opacity(0.6))
                DestinationButton(destination: model.destination, label: model.destinationLabel) {
                    model.picking ? model.closePicker() : model.openPicker()
                }
                .keyboardShortcut("p", modifiers: .command)
                if model.destination.kind == .daily && model.todayCount > 0 {
                    Text("· 已记 \(model.todayCount) 条").foregroundStyle(Theme.subtle)
                }
            }
        }
        .font(Theme.sans(12, .medium))
        .animation(.easeOut(duration: 0.12), value: model.vaultPath)
    }

    private var saveButton: some View {
        Button { model.save() } label: {
            HStack(spacing: 8) {
                if model.saving { ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12) }
                Text(model.saving ? "识别中" : "保存").font(Theme.sans(13, .medium))
                Text("⌘↩").font(.system(size: 12, weight: .medium)).opacity(0.5)
            }
        }
        .keyboardShortcut(.return, modifiers: .command)
        .buttonStyle(PrimaryStyle(enabled: model.canSave))
        .disabled(!model.canSave)
    }

    private var formatBar: some View {
        HStack(spacing: 0) {
            FormatButton(text: "H", "标题（再点切换级别）  ⌘1/2/3") { model.format?(.heading(nil)) }
            FormatButton("bold", "粗体", "⌘B") { model.format?(.bold) }
            FormatButton("italic", "斜体", "⌘I") { model.format?(.italic) }
            FormatButton("strikethrough", "删除线", "⌘⇧X") { model.format?(.strike) }
            FormatButton("highlighter", "高亮", "⌘⇧H") { model.format?(.highlight) }
            FormatDivider()
            FormatButton("list.bullet", "无序列表", "⌘⇧8") { model.format?(.bullet) }
            FormatButton("list.number", "有序列表", "⌘⇧7") { model.format?(.numbered) }
            FormatButton("checklist", "待办", "⌘L") { model.format?(.task) }
            FormatButton("text.quote", "引用", "⌘'") { model.format?(.quote) }
            FormatDivider()
            FormatButton("chevron.left.forwardslash.chevron.right", "行内代码", "⌘E") { model.format?(.code) }
            FormatButton("curlybraces", "代码块", "⌘⇧C") { model.format?(.codeBlock) }
            FormatButton("link", "链接", "⌘K") { model.format?(.link) }
            FormatButton(text: "[[", "双向链接") { model.format?(.wikilink) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 40)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    // MARK: Overlays

    private var dropOverlay: some View {
        ZStack {
            Theme.background.opacity(0.94)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.text.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .padding(10)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .regular))
                Text("松开以添加到今日日记").font(Theme.sans(13, .medium))
            }.foregroundStyle(Theme.text)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private var savedOverlay: some View {
        ZStack {
            Theme.background
            HStack(spacing: 10) {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inverse)
                    .frame(width: 22, height: 22).background(Circle().fill(Theme.text))
                Text(model.savedTo.map { "已保存到「\($0)」" } ?? "已记录到今日日记")
                    .font(Theme.sans(15, .medium)).foregroundStyle(Theme.text)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Components

struct Kbd: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key).font(Theme.mono(10)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 5).frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hover ? Theme.text : Theme.subtle)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hover ? Theme.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("关闭（Esc）· 未保存的文字会留作草稿")
    }
}

struct FormatButton: View {
    let symbol: String?
    let text: String?
    let help: String
    let action: () -> Void
    @State private var hover = false

    init(_ symbol: String, _ title: String, _ shortcut: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.text = nil; self.help = "\(title)  \(shortcut)"; self.action = action
    }
    init(text: String, _ title: String, action: @escaping () -> Void) {
        self.symbol = nil; self.text = text; self.help = title; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .regular)) }
                else if let text { Text(text).font(text == "H" ? Theme.sans(14, .semibold) : Theme.mono(12)) }
            }
            .foregroundStyle(hover ? Theme.text : Theme.muted)
            .frame(width: 30, height: 28)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

/// "Aa" toggle for the format bar (SF Symbol `textformat` is localized to 格式 in Chinese).
struct FormatToggle: View {
    let active: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text("Aa").font(Theme.sans(13, .semibold))
                .foregroundStyle(active || hover ? Theme.text : Theme.muted)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(active ? Theme.hover.opacity(1.6) : hover ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(active ? "收起格式栏  ⌘/" : "格式  ⌘/")
    }
}

struct FormatDivider: View {
    var body: some View { Rectangle().fill(Theme.border).frame(width: 1, height: 16).padding(.horizontal, 6) }
}

struct VaultButton: View {
    let name: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(name).lineLimit(1).truncationMode(.middle).frame(maxWidth: 170, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(hover ? Theme.text : Theme.muted)
            .padding(.horizontal, 6).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.hover : .clear))
            .padding(.horizontal, -6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("切换保存位置")
    }
}

/// NSMenuItem whose action is a closure (the item retains it via representedObject).
final class MenuAction: NSObject {
    private let handler: () -> Void
    private init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc private func run() { handler() }

    static func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        return item
    }
}

struct IconButton: View {
    let symbol: String
    let active: Bool
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(active || hover ? Theme.text : Theme.muted)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hover ? Theme.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct PrimaryStyle: ButtonStyle {
    let enabled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Theme.inverse : Theme.subtle)
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(enabled ? Theme.text : Theme.background))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(enabled ? Color.clear : Theme.border))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: enabled)
    }
}

/// An empty view that lets the user drag the borderless panel.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// QuickLook thumbnail (first frame for videos/GIFs), falling back to the file icon.
struct Thumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(size * 0.16) }
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear(perform: load)
    }

    private func load() {
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                               scale: NSScreen.main?.backingScaleFactor ?? 2,
                                               representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            if let img = rep?.nsImage { DispatchQueue.main.async { image = img } }
        }
    }
}

enum MediaKind {
    case image, gif, video, other
    init(_ url: URL) {
        let t = UTType(filenameExtension: url.pathExtension)
        if t?.conforms(to: .gif) == true { self = .gif }
        else if t?.conforms(to: .image) == true { self = .image }
        else if t?.conforms(to: .movie) == true { self = .video }
        else { self = .other }
    }
}

struct AttachmentCard: View {
    let url: URL
    let open: () -> Void
    let remove: () -> Void
    @State private var hover = false
    @State private var duration: String?

    private var kind: MediaKind { MediaKind(url) }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) {
                ZStack(alignment: .bottomLeading) {
                    Thumbnail(url: url, size: 80).background(Theme.bar)
                    if let badge {
                        HStack(spacing: 3) {
                            if kind == .video { Image(systemName: "play.fill").font(.system(size: 7, weight: .bold)) }
                            Text(badge).font(Theme.mono(9))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(height: 16)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .padding(5)
                    }
                    if kind == .other {
                        Text(url.pathExtension.uppercased()).font(Theme.mono(9)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.bottom, 6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(hover ? Theme.text.opacity(0.35) : Theme.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.inverse)
                    .frame(width: 18, height: 18).background(Theme.text, in: Circle())
            }
            .buttonStyle(.plain).offset(x: 6, y: -6).opacity(hover ? 1 : 0)
        }
        .padding(.top, 6).padding(.trailing, 6)
        .help("\(url.lastPathComponent) · 点击预览")
        .onHover { hover = $0 }
        .task { await loadDuration() }
    }

    private var badge: String? {
        switch kind {
        case .gif: return "GIF"
        case .video: return duration ?? ""
        default: return nil
        }
    }

    private func loadDuration() async {
        guard kind == .video, let d = try? await AVURLAsset(url: url).load(.duration), d.seconds.isFinite else { return }
        let s = Int(d.seconds.rounded())
        duration = String(format: "%d:%02d", s / 60, s % 60)
    }
}
