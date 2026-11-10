import SwiftUI
import AppKit
import KeyboardShortcuts

/// 「记录」: look back over a day — what was captured, and a friendly summary to preview before it goes into the note.
final class RecordsModel: ObservableObject {
    struct Row: Identifiable {
        let item: CaptureLog.Item
        let text: String
        var id: String { item.id }
    }

    @Published var day: Date
    @Published var rows: [Row] = []
    /// The day's note when the capture log has nothing for it (days before 1.6, or typed in Obsidian).
    @Published var noteText: String?
    /// Parts of the daily note the log doesn't cover (written before 1.6, or typed in Obsidian).
    @Published var otherText: String?
    @Published var summary: String?
    @Published var editing = false
    @Published var summarizing = false
    @Published var error: String?
    @Published var written = false
    /// Static rows for design snapshots.
    var preview = false

    init(day: Date = Date()) { self.day = Calendar.current.startOfDay(for: day) }

    var isToday: Bool { Calendar.current.isDateInToday(day) }
    var engine: AIEngine? { AIStore.current }
    var hasContent: Bool { !rows.isEmpty || noteText != nil }

    func load() {
        guard !preview else { return }
        let items = CaptureLog.items(on: day)
        rows = items.compactMap(Self.row)
        noteText = nil; otherText = nil
        if let note = DailyReview.dailyNote(for: day), let s = try? String(contentsOf: note, encoding: .utf8) {
            let body = DailyReview.removeBlock(from: s).trimmingCharacters(in: .whitespacesAndNewlines)
            if rows.isEmpty {
                noteText = body.isEmpty ? nil : body
            } else {
                let rest = Self.remainder(of: body, without: items.filter(\.daily).compactMap { $0.text() })
                otherText = rest.isEmpty ? nil : rest
            }
        }
        summary = ReviewDrafts.get(day)
        written = DailyReview.isWritten(day: day)
        error = nil
        editing = false
    }

    static func row(_ i: CaptureLog.Item) -> Row? {
        guard let raw = i.text() else { return nil }
        return Row(item: i, text: displayText(raw, source: i.sourceMarkdown))
    }

    /// The note minus the logged entries.
    static func remainder(of body: String, without entries: [String]) -> String {
        var rest = body
        for e in entries {
            let t = e.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, let r = rest.range(of: t) { rest.removeSubrange(r) }
        }
        return rest.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The entry without the time · source line the row already shows.
    static func displayText(_ raw: String, source: String?) -> String {
        var out: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let source, !source.isEmpty, t.contains(source), t.hasPrefix(">") || t.hasPrefix("—") { continue }
            if t.range(of: #"^(>\s*)?(\*\*)?\d{1,2}:\d{2}(\*\*)?$"#, options: .regularExpression) != nil { continue }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func go(_ delta: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: delta, to: day), d <= Date() else { return }
        day = d
        load()
    }
    func goToday() { day = Calendar.current.startOfDay(for: Date()); load() }

    func summarize() {
        guard let engine, !summarizing else { return }
        summarizing = true; error = nil; editing = false
        let d = day
        Task {
            do {
                let s = try await DailyReview.summarize(day: d, engine: engine)
                await MainActor.run {
                    ReviewDrafts.set(s, d)
                    if self.day == d { self.summary = s; self.written = false }
                    self.summarizing = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; self.summarizing = false }
            }
        }
    }

    func write() {
        guard let s = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        do {
            try DailyReview.write(s, day: day)
            ReviewDrafts.set(s, day)
            written = true; editing = false
        } catch { self.error = error.localizedDescription }
    }

    func unwrite() {
        do { try DailyReview.unwrite(day: day); written = false } catch { self.error = error.localizedDescription }
    }

    func setSummary(_ s: String) { summary = s; ReviewDrafts.set(s, day) }

    func discard() { summary = nil; ReviewDrafts.set(nil, day); editing = false; error = nil }

    func openNote(_ path: String? = nil) {
        guard let vault = Prefs.shared.vaultURL else { return }
        let url = path.map(URL.init(fileURLWithPath:)) ?? DailyReview.dailyNote(for: day)
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        if url.path.hasPrefix(vault.path) { CaptureModel.open(note: url, vault: vault) } else { NSWorkspace.shared.open(url) }
    }

    /// A [[wikilink]] clicked in the window.
    func openLink(_ name: String) {
        guard let vault = Prefs.shared.vaultURL else { return }
        if FolderMode.isObsidianVault(vault), FolderMode.obsidianInstalled {
            var c = URLComponents(string: "obsidian://open")!
            c.queryItems = [.init(name: "vault", value: vault.lastPathComponent), .init(name: "file", value: name)]
            if let u = c.url { NSWorkspace.shared.open(u) }
        } else {
            let u = vault.appendingPathComponent(name.hasSuffix(".md") ? name : name + ".md")
            if FileManager.default.fileExists(atPath: u.path) { NSWorkspace.shared.open(u) }
        }
    }
}

struct RecordsView: View {
    @ObservedObject var model: RecordsModel
    var openAISettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    reviewCard
                    content
                }
                .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 40)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.background)
        .frame(minWidth: 540, minHeight: 480)
        .onAppear { model.load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(DailyReview.dayTitle(model.day)).font(Theme.text(22, .semibold)).foregroundStyle(Theme.text)
                Text(subtitle).font(Theme.text(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            DayNav(isToday: model.isToday, prev: { model.go(-1) }, today: { model.goToday() }, next: { model.go(1) })
        }
        .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 18)
    }

    private var subtitle: String {
        let when = model.isToday ? "今天" : Calendar.current.isDateInYesterday(model.day) ? "昨天" : DailyReview.dayKey(model.day)
        if !model.rows.isEmpty { return "\(when) · \(model.rows.count) 条记录" }
        return model.noteText != nil ? "\(when) · 当天日记" : "\(when) · 没有记录"
    }

    // MARK: Review card

    @ViewBuilder private var reviewCard: some View {
        if model.hasContent || model.summary != nil {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                    Text(model.isToday ? "今日回顾" : "这天的回顾").font(Theme.text(13.5, .semibold))
                    if model.summary != nil { Badge(model.written ? "已写入日记" : "预览") }
                    Spacer()
                    if let e = model.engine, model.summary != nil || model.summarizing {
                        Text(e.label).font(Theme.text(11.5)).foregroundStyle(Theme.subtle).lineLimit(1)
                    }
                }
                .foregroundStyle(Theme.text)
                reviewBody
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border))
        }
    }

    @ViewBuilder private var reviewBody: some View {
        if model.summarizing {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.rows.isEmpty ? "正在读这一天的日记…" : "正在读这 \(model.rows.count) 条记录…")
                        .font(Theme.text(13)).foregroundStyle(Theme.muted)
                }
                SkeletonLines()
            }
        } else if let s = model.summary {
            if model.editing {
                TextEditor(text: Binding(get: { model.summary ?? "" }, set: { model.setSummary($0) }))
                    .font(Theme.text(13.5)).lineSpacing(4)
                    .scrollContentBackground(.hidden)
                    .padding(8).frame(minHeight: 180)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.background))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.text.opacity(0.4)))
            } else {
                MarkdownBody(s, size: 14, onOpenNote: model.openLink)
            }
            if let e = model.error { StatusLine(ok: false, text: e) }
            HStack(spacing: 8) {
                if model.written {
                    Button("打开日记") { model.openNote() }.buttonStyle(PrimaryButton())
                    Button("撤销写入") { model.unwrite() }.buttonStyle(PillButton())
                } else if model.editing {
                    Button("完成") { model.editing = false }.buttonStyle(PrimaryButton())
                        .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button("写入日记") { model.write() }.buttonStyle(PrimaryButton())
                        .keyboardShortcut(.return, modifiers: .command).help("写到当天日记末尾的「今日回顾」（⌘↩）")
                    Button("编辑") { model.editing = true }.buttonStyle(PillButton())
                }
                Spacer()
                ToneMenu { model.summarize() }.disabled(model.engine == nil)
                ToolIconButton(symbol: "arrow.clockwise", help: "重新生成") { model.summarize() }.disabled(model.engine == nil)
                ToolIconButton(symbol: "doc.on.doc", help: "复制") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string)
                }
                if !model.written { ToolIconButton(symbol: "trash", help: "丢弃这份总结") { model.discard() } }
            }
        } else if model.engine != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("让 AI 陪你把这一天翻一遍。先预览，满意了再写进日记。")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if let e = model.error { StatusLine(ok: false, text: e) }
                HStack(spacing: 10) {
                    Button(model.error == nil ? "总结这一天" : "再试一次") { model.summarize() }.buttonStyle(PrimaryButton())
                    ToneMenu()
                    Spacer(minLength: 0)
                    Text(model.engine?.label ?? "").font(Theme.text(11.5)).foregroundStyle(Theme.subtle).lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("配好一个 AI 模型，就能一键总结这一天。可以用 DeepSeek 等云端服务，也可以用本机已登录的 Claude Code、Codex。")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("配置 AI 模型", action: openAISettings).buttonStyle(PrimaryButton())
            }
        }
    }

    // MARK: Entries

    @ViewBuilder private var content: some View {
        if !model.rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                    EntryRow(row: row, last: i == model.rows.count - 1, open: { model.openNote(row.item.notePath) },
                             openLink: model.openLink)
                }
            }
            if let other = model.otherText {
                OtherNoteText(text: other, note: DailyReview.dailyNote(for: model.day), open: { model.openNote() },
                              openLink: model.openLink)
            }
        } else if let text = model.noteText {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("这天的日记").font(Theme.text(12, .medium)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("在笔记中打开") { model.openNote() }.buttonStyle(QuietButton())
                }
                let note = DailyReview.dailyNote(for: model.day)
                MarkdownBody(text, size: 14, resolve: { Attachments.resolve($0, near: note) }, onOpenNote: model.openLink)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 26, weight: .light)).foregroundStyle(Theme.subtle)
                Text(model.isToday ? "今天还没有记录" : "这一天没有记录").font(Theme.text(13.5, .medium)).foregroundStyle(Theme.text)
                if model.isToday {
                    Text("在任何地方按 \(KeyboardShortcutsLabel.capture) 随手记一条").font(Theme.text(12)).foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity).padding(.top, 70)
        }
    }
}

/// One capture on the timeline: time on the left, the entry as Markdown, where it came from and went.
private struct EntryRow: View {
    let row: RecordsModel.Row
    let last: Bool
    let open: () -> Void
    let openLink: (String) -> Void
    @State private var hover = false
    @State private var expanded = false

    private var blocks: [MD.Block] { MD.parse(row.text) }
    private var long: Bool { blocks.count > 6 || row.text.count > 600 }

    var body: some View {
        let i = row.item
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                Text(MomentFormat.string(i.date, format: "HH:mm"))
                    .font(.custom("GeistMono-Regular", size: 11.5)).foregroundStyle(Theme.subtle)
                    .padding(.top, 2)
                if !last { Rectangle().fill(Theme.border).frame(width: 1).frame(maxHeight: .infinity) }
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 10) {
                if !row.text.isEmpty {
                    MarkdownBody(blocks: expanded || !long ? blocks : Array(blocks.prefix(4)), size: 14,
                                 resolve: { Attachments.resolve($0, near: i.noteURL, files: i.files) }, onOpenNote: openLink)
                    if long {
                        Button(expanded ? "收起" : "展开全部") { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } }
                            .buttonStyle(QuietButton())
                            .padding(.leading, -6)
                    }
                }
                meta(i)
            }
            .padding(.bottom, last ? 0 : 26)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .overlay(alignment: .topTrailing) {
            if hover {
                Button(action: open) { Label("打开", systemImage: "arrow.up.right") }
                    .buttonStyle(PillButton()).transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    @ViewBuilder private func meta(_ i: CaptureLog.Item) -> some View {
        let dest = i.daily ? nil : ((i.notePath as NSString).lastPathComponent as NSString).deletingPathExtension
        if i.source != nil || dest != nil {
            HStack(spacing: 6) {
                if let s = i.source {
                    SourceGlyph(bundleID: s.bundleID, kind: s.kind, size: 11, color: Theme.muted)
                    if let u = s.url {
                        Link(destination: u) { Text(s.label).lineLimit(1).truncationMode(.middle) }
                            .foregroundStyle(Theme.muted)
                    } else {
                        Text(s.label).lineLimit(1).truncationMode(.middle)
                    }
                }
                if let dest {
                    if i.source != nil { Text("·").foregroundStyle(Theme.subtle) }
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9, weight: .semibold))
                    Text(dest).lineLimit(1)
                }
            }
            .font(Theme.text(11.5)).foregroundStyle(Theme.muted)
        }
    }
}

/// What else is in the day's note, folded by default.
private struct OtherNoteText: View {
    let text: String
    let note: URL?
    let open: () -> Void
    let openLink: (String) -> Void
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Button { withAnimation(.easeOut(duration: 0.15)) { shown.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(shown ? 90 : 0))
                        Text("日记里的其他内容").font(Theme.text(12, .medium))
                        Text("不是用乔木闪记记的，或是更早的").font(Theme.text(11.5)).foregroundStyle(Theme.subtle)
                    }
                    .foregroundStyle(Theme.muted).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button("在笔记中打开", action: open).buttonStyle(QuietButton())
            }
            if shown {
                MarkdownBody(text, size: 14, resolve: { Attachments.resolve($0, near: note) }, onOpenNote: openLink)
                    .padding(.leading, 15)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}

/// ‹ 今天 › as one joined control.
private struct DayNav: View {
    let isToday: Bool
    let prev: () -> Void
    let today: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            seg(Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)), help: "前一天 ⌘←", action: prev)
                .keyboardShortcut(.leftArrow, modifiers: .command)
            divider
            seg(Text("今天").font(Theme.text(12.5, .medium)), help: "回到今天 ⌘T", action: today)
                .keyboardShortcut("t", modifiers: .command).disabled(isToday)
            divider
            seg(Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)), help: "后一天 ⌘→", action: next)
                .keyboardShortcut(.rightArrow, modifiers: .command).disabled(isToday)
        }
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var divider: some View { Rectangle().fill(Theme.border).frame(width: 1) }

    private func seg<L: View>(_ label: L, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label.frame(minWidth: 34).padding(.horizontal, 8).frame(maxHeight: .infinity) }
            .buttonStyle(SegmentStyle()).help(help)
    }
}

private struct SegmentStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(Theme.text)
            .background(configuration.isPressed || hover ? Theme.hover : .clear)
            .opacity(enabled ? 1 : 0.3)
            .contentShape(Rectangle())
            .onHover { hover = $0 && enabled }
    }
}

struct ToolIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 14, height: 14) }
            .buttonStyle(PillButton()).help(help)
    }
}

/// Placeholder lines while the summary is being written.
private struct SkeletonLines: View {
    @State private var on = false
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach([1.0, 0.92, 0.97, 0.6], id: \.self) { w in
                GeometryReader { g in
                    RoundedRectangle(cornerRadius: 3).fill(Theme.hover).frame(width: g.size.width * w, height: 9)
                }
                .frame(height: 9)
            }
        }
        .opacity(on ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
        .onAppear { on = true }
    }
}

@MainActor enum KeyboardShortcutsLabel {
    static var capture: String { KeyboardShortcuts.getShortcut(for: .capture)?.description ?? "⌘⇧J" }
}

enum RecordsWindow {
    static func make(model: RecordsModel, openAISettings: @escaping () -> Void) -> NSWindow {
        let host = NSHostingController(rootView: RecordsView(model: model, openAISettings: openAISettings))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "\(AppInfo.name) · 记录"
        w.setContentSize(NSSize(width: 680, height: 760))
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("JotRecords")
        w.center()
        return w
    }
}
