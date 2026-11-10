import SwiftUI
import AppKit
import KeyboardShortcuts
import UserNotifications

private let pageWidth: CGFloat = 560

// MARK: - AI 模型

/// One active engine at a time: either a cloud service (with a key) or a CLI signed in on this Mac.
struct AISettings: View {
    @State private var mode = AIStore.mode
    @State private var providers = AIStore.providers
    @State private var apiID = AIStore.apiProvider?.id ?? ""
    @State private var cli = AIStore.cliTool
    @State private var installed = LocalCLI.installed
    @State private var sheet: ProviderSheet.Start?
    @State private var cliTests: [LocalCLI.Tool: CLITest] = [:]

    enum CLITest: Equatable { case running, ok(Int), failed(String) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "AI 模型", detail: "每日回顾和以后的 AI 功能，都用这里选中的模型。")
                HStack(spacing: 12) {
                    ModeCard(title: "云端模型", detail: "填一个 API Key，几秒出结果", symbol: "cloud",
                             selected: mode == .api) { setMode(.api) }
                    ModeCard(title: "本机 AI 工具", detail: "用已登录的 Claude Code 等，免 Key", symbol: "terminal",
                             selected: mode == .cli) { setMode(.cli) }
                }
                if mode == .api { apiSection.transition(.opacity) } else { cliSection.transition(.opacity) }
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 28)
            .animation(.easeOut(duration: 0.16), value: mode)
        }
        .frame(width: pageWidth, height: 600)
        .background(Theme.canvas)
        .sheet(item: $sheet) { start in ProviderSheet(start: start) { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .aiChanged)) { _ in reload() }
        .onAppear { installed = LocalCLI.installed; reload() }
    }

    private func setMode(_ m: AIMode) { mode = m; AIStore.mode = m }

    private func reload() {
        providers = AIStore.providers
        apiID = AIStore.apiProvider?.id ?? ""
        cli = AIStore.cliTool
        if AIStore.mode != mode { mode = AIStore.mode }
    }

    // MARK: Cloud

    @ViewBuilder private var apiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupLabel("服务", trailing: providers.isEmpty ? nil : AnyView(
                Button { sheet = .gallery } label: { Label("添加服务", systemImage: "plus") }.buttonStyle(QuietButton())))
            if providers.isEmpty {
                recommend
            } else {
                Card {
                    ForEach(Array(providers.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { CardDivider(inset: 74) }
                        ProviderRow(provider: p, selected: p.id == apiID) {
                            if p.ready { apiID = p.id; AIStore.apiID = p.id } else { sheet = .edit(p) }
                        } edit: { sheet = .edit(p) }
                    }
                }
            }
            Caption("Key 只保存在这台 Mac 的钥匙串里。费用由服务商按用量直接收取，每天一次总结通常花不到一分钱。")
        }
    }

    private var recommend: some View {
        let ds = AIPreset.find("deepseek")!
        return Card {
            HStack(alignment: .top, spacing: 14) {
                BrandMark(icon: ds.icon, name: ds.name, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("从 DeepSeek 开始").font(Theme.text(14, .semibold)).foregroundStyle(Theme.text)
                        Badge("推荐")
                    }
                    Text("便宜、中文好、国内直连。注册后复制 API Key，粘贴进来就能用。")
                        .font(Theme.text(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("添加 DeepSeek") { sheet = .new(ds) }.buttonStyle(PrimaryButton())
                        Button("其他服务…") { sheet = .gallery }.buttonStyle(PillButton())
                    }
                    .padding(.top, 8)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    // MARK: Local tools

    private var cliSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupLabel("本机工具")
            Card {
                ForEach(Array(LocalCLI.Tool.allCases.enumerated()), id: \.element) { i, t in
                    if i > 0 { CardDivider(inset: 74) }
                    cliRow(t)
                }
            }
            Caption("用你在这台 Mac 上已经登录的账号，不需要 Key。以只读方式运行，不会改动任何文件。比云端慢一些，一次总结约 10–30 秒。")
        }
    }

    private func cliRow(_ t: LocalCLI.Tool) -> some View {
        let ok = installed.contains(t)
        let selected = ok && cli == t
        return HStack(spacing: 12) {
            RadioDot(on: selected).opacity(ok ? 1 : 0.35)
            BrandMark(icon: t.icon, name: t.name, size: 30).opacity(ok ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).font(Theme.text(13, .medium)).foregroundStyle(ok ? Theme.text : Theme.muted)
                Group {
                    switch cliTests[t] {
                    case .running: Text("正在测试…").foregroundStyle(Theme.muted)
                    case .ok(let ms): Text("可用 · 用时 \(String(format: "%.1f", Double(ms) / 1000)) 秒").foregroundStyle(Theme.success)
                    case .failed(let e): Text(e).foregroundStyle(Theme.danger).lineLimit(2)
                    case nil:
                        Text(ok ? t.vendor + " · " + ((LocalCLI.path(t) ?? "") as NSString).abbreviatingWithTildeInPath : "未安装")
                            .foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    }
                }
                .font(Theme.text(11.5))
            }
            Spacer(minLength: 8)
            if ok {
                if cliTests[t] == .running { ProgressView().controlSize(.small) }
                else { Button("测试") { test(t) }.buttonStyle(QuietButton()) }
            } else {
                Link(destination: t.installURL) { Text("安装说明 ↗") }.buttonStyle(QuietButton())
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 60)
        .contentShape(Rectangle())
        .onTapGesture { if ok { cli = t; AIStore.cliTool = t } }
    }

    private func test(_ t: LocalCLI.Tool) {
        cliTests[t] = .running
        let t0 = Date()
        Task {
            do {
                _ = try await LocalCLI.run(t, prompt: "Reply with the single word OK.", timeout: 90)
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                await MainActor.run { cliTests[t] = .ok(ms) }
            } catch {
                await MainActor.run { cliTests[t] = .failed(error.localizedDescription) }
            }
        }
    }
}

struct PageHeader: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.text(18, .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(Theme.text(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.text(11.5)).foregroundStyle(Theme.muted).lineSpacing(2)
            .padding(.horizontal, 2).fixedSize(horizontal: false, vertical: true)
    }
}

struct Badge: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.text(10.5, .medium)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 6).frame(height: 18)
            .background(Capsule().fill(Theme.hover))
    }
}

private struct ModeCard: View {
    let title: String
    let detail: String
    let symbol: String
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(Theme.text)
                    Spacer()
                    RadioDot(on: selected)
                }
                Spacer(minLength: 10)
                Text(title).font(Theme.text(13.5, .semibold)).foregroundStyle(Theme.text)
                Text(detail).font(Theme.text(11.5)).foregroundStyle(Theme.muted).padding(.top, 3).lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.text : (hover ? Theme.subtle.opacity(0.6) : Theme.border), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

private struct ProviderRow: View {
    let provider: AIProvider
    let selected: Bool
    let choose: () -> Void
    let edit: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            RadioDot(on: selected)
            BrandMark(icon: provider.presetInfo?.icon, name: provider.name, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name).font(Theme.text(13, .medium)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    Text(provider.model.isEmpty ? "未选模型" : provider.model)
                    if let m = KeyStore.masked(provider.id) { Text("·"); Text(m) }
                }
                .font(.custom("GeistMono-Regular", size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !provider.ready {
                Text("未完成").font(Theme.text(11.5, .medium)).foregroundStyle(Theme.danger)
            }
            Button("编辑", action: edit).buttonStyle(QuietButton())
        }
        .padding(.horizontal, 16).frame(minHeight: 60)
        .background(hover ? Theme.hover.opacity(0.5) : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: choose)
    }
}

// MARK: - Add / edit a service

struct ProviderSheet: View {
    enum Start: Identifiable {
        case gallery, new(AIPreset), edit(AIProvider)
        var id: String {
            switch self { case .gallery: return "gallery"; case .new(let p): return "new-\(p.id)"; case .edit(let p): return "edit-\(p.id)" }
        }
    }

    let start: Start
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: AIProvider?
    @State private var fromGallery = false

    init(start: Start, onDone: @escaping () -> Void) {
        self.start = start
        self.onDone = onDone
        switch start {
        case .gallery: _fromGallery = State(initialValue: true)
        case .new(let p): _editing = State(initialValue: .new(p))
        case .edit(let p): _editing = State(initialValue: p)
        }
    }

    var body: some View {
        Group {
            if let p = editing {
                ProviderEditor(provider: p, isNew: !AIStore.providers.contains { $0.id == p.id },
                               back: fromGallery ? { withAnimation(.easeOut(duration: 0.15)) { editing = nil } } : nil,
                               onDone: { onDone(); dismiss() }, onCancel: { dismiss() })
                    .id(p.id)
            } else {
                gallery
            }
        }
        .frame(width: 560)
        .background(Theme.canvas)
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "添加模型服务", detail: "选一家服务商，粘贴它的 API Key。绿点为推荐；请求直接发给服务商。")
                .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tiles("国内", ["deepseek", "moonshot", "qwen", "zhipu", "doubao", "minimax"])
                    tiles("海外", ["openai", "anthropic", "gemini"])
                    tiles("聚合 · 本地 · 自定义", ["siliconflow", "openrouter", "magpie", "ollama", "custom"])
                }
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
            .frame(height: 440)
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(PillButton()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    private func tiles(_ title: String, _ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ids.compactMap(AIPreset.find)) { p in
                    PresetTile(preset: p) { withAnimation(.easeOut(duration: 0.15)) { editing = .new(p) } }
                }
            }
        }
    }
}

private struct PresetTile: View {
    let preset: AIPreset
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                BrandMark(icon: preset.icon, name: preset.name, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(preset.group == .custom ? "自定义接口" : preset.name)
                            .font(Theme.text(12.5, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        if preset.id == "deepseek" {
                            Circle().fill(Theme.success).frame(width: 6, height: 6).help("推荐")
                        }
                    }
                    Text(preset.blurb).font(Theme.text(10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hover ? Theme.hover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(hover ? Theme.subtle.opacity(0.6) : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(preset.blurb)
    }
}

/// Saving always tests first and keeps nothing that fails.
struct ProviderEditor: View {
    @State var provider: AIProvider
    let isNew: Bool
    var back: (() -> Void)?
    var onDone: () -> Void
    var onCancel: () -> Void
    @State private var key = ""
    @State private var customAddress = false
    @State private var models: [String] = []
    @State private var status: Status?
    @State private var busy = false
    @State private var fetching = false
    @State private var confirmDelete = false

    struct Status: Equatable { var ok: Bool; var text: String }

    private var preset: AIPreset? { provider.presetInfo }
    private var keyRequired: Bool { preset?.keyRequired != false }
    private var isCustom: Bool { preset?.group == .custom }
    private var showsAddress: Bool { preset?.showsAddress == true || customAddress }
    private var suggestions: [String] { models.isEmpty ? (preset?.models ?? []) : models }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            Rectangle().fill(Theme.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 18) {
                if isCustom {
                    HStack(alignment: .top, spacing: 12) {
                        FieldRow(label: "名称") { JotField(placeholder: "例如：公司网关", text: $provider.name) }
                        FieldRow(label: "接口格式") {
                            Picker("", selection: $provider.proto) {
                                ForEach(AIProtocol.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(height: 32)
                        }
                    }
                }
                if showsAddress {
                    FieldRow(label: "接口地址", hint: "填到 /v1 为止即可，完整的 …/chat/completions 也能识别。") {
                        JotField(placeholder: "https://api.example.com/v1", text: $provider.baseURL, mono: true)
                    }
                }
                FieldRow(label: "API Key", hint: keyRequired ? nil : "本地服务通常不需要 Key，可以留空。") {
                    HStack(spacing: 8) {
                        JotField(placeholder: keyPlaceholder, text: $key, secure: true, mono: true)
                        Button("粘贴") {
                            if let s = NSPasteboard.general.string(forType: .string) { key = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }
                        .buttonStyle(PillButton())
                    }
                }
                FieldRow(label: "模型") {
                    HStack(spacing: 8) {
                        ZStack(alignment: .trailing) {
                            JotField(placeholder: preset?.models.first ?? "模型名", text: $provider.model, mono: true)
                            Menu {
                                if suggestions.isEmpty { Text("点「读取列表」获取可用模型") }
                                ForEach(suggestions.prefix(80), id: \.self) { m in Button(m) { provider.model = m } }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.muted)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .padding(.trailing, 8).help("常用模型")
                        }
                        Button(fetching ? "读取中…" : "读取列表") { fetchModels() }
                            .buttonStyle(PillButton()).disabled(fetching || busy)
                    }
                }
                if let status { StatusLine(ok: status.ok, text: status.text) }
            }
            .padding(24)
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.15), value: showsAddress)
        .onChange(of: provider) { _ in if status?.ok == true { status = nil }; confirmDelete = false }
        .onChange(of: key) { _ in if status?.ok == true { status = nil } }
    }

    private var head: some View {
        HStack(spacing: 12) {
            if let back {
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).frame(width: 18, height: 18) }
                    .buttonStyle(QuietButton(color: Theme.text)).help("返回")
            }
            BrandMark(icon: preset?.icon, name: provider.name, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(isCustom && provider.name.isEmpty ? "自定义接口" : provider.name)
                    .font(Theme.text(15, .semibold)).foregroundStyle(Theme.text)
                Text(preset?.blurb ?? "").font(Theme.text(12)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let u = preset?.keyURL.flatMap(URL.init(string:)) {
                Link(destination: u) { Text(preset?.group == .local ? "使用说明 ↗" : "获取 Key ↗") }
                    .buttonStyle(PillButton())
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if !isNew {
                Button(confirmDelete ? "确认删除？" : "删除") {
                    if confirmDelete { AIStore.remove(provider.id); onDone() } else { confirmDelete = true }
                }
                .buttonStyle(QuietButton(color: Theme.danger))
            }
            if preset?.showsAddress == false {
                Button(customAddress ? "恢复默认地址" : "自定义地址") {
                    customAddress.toggle()
                    if !customAddress, let p = preset { provider.baseURL = p.baseURL }
                }
                .buttonStyle(QuietButton())
            }
            Spacer()
            Button("取消", action: onCancel).buttonStyle(PillButton()).keyboardShortcut(.cancelAction)
                .padding(.trailing, 4)
            Button {
                testAndSave()
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().controlSize(.mini).tint(Theme.inverse) }
                    Text(busy ? "正在测试" : "测试并保存")
                }
            }
            .buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction).disabled(busy)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private var keyPlaceholder: String {
        if let m = KeyStore.masked(provider.id) { return "已保存 \(m)，留空则不修改" }
        return keyRequired ? "sk-…" : "可选"
    }

    private var typedKey: String? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return k.isEmpty ? nil : k
    }

    private var normalized: AIProvider {
        var p = provider
        p.baseURL = LLMClient.normalize(p.baseURL)
        p.model = p.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = p.name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            p.name = isCustom ? (URL(string: p.baseURL)?.host ?? "自定义接口") : (preset?.name ?? "")
        } else { p.name = name }
        return p
    }

    private func fetchModels() {
        fetching = true; status = nil
        Task {
            do {
                let list = try await LLMClient.models(normalized, key: typedKey)
                await MainActor.run {
                    models = list; fetching = false
                    status = list.isEmpty ? Status(ok: false, text: "服务没有返回模型列表，请直接填写模型名")
                        : Status(ok: true, text: "Key 可用，找到 \(list.count) 个模型，点输入框右侧选择")
                    if provider.model.isEmpty, let first = list.first { provider.model = first }
                }
            } catch {
                await MainActor.run { fetching = false; status = Status(ok: false, text: error.localizedDescription) }
            }
        }
    }

    private func testAndSave() {
        let p = normalized
        if p.baseURL.isEmpty { status = Status(ok: false, text: "请填写接口地址"); return }
        if p.model.isEmpty { status = Status(ok: false, text: "请填写模型名，或点「读取列表」"); return }
        if keyRequired, typedKey == nil, KeyStore.get(p.id) == nil { status = Status(ok: false, text: "请粘贴 API Key"); return }
        busy = true; status = nil
        Task {
            do {
                let ms = try await LLMClient.test(p, key: typedKey)
                await MainActor.run {
                    if let k = typedKey { KeyStore.set(k, for: p.id) }
                    var saved = p; saved.verified = true
                    AIStore.save(saved)
                    AIStore.apiID = saved.id
                    AIStore.mode = .api
                    busy = false
                    status = Status(ok: true, text: "连接成功 · \(ms) ms")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onDone() }
                }
            } catch {
                await MainActor.run { busy = false; status = Status(ok: false, text: error.localizedDescription) }
            }
        }
    }
}

// MARK: - 回顾

struct ReviewSettings: View {
    @ObservedObject var prefs = Prefs.shared
    @State private var notificationsOff = false
    @State private var engine = AIStore.current?.label

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: prefs.reviewMinutes / 60, minute: prefs.reviewMinutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            prefs.reviewMinutes = (c.hour ?? 21) * 60 + (c.minute ?? 30)
        })
    }

    @State private var editingPrompt = false
    private var on: Bool { prefs.reviewEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                PageHeader(title: "每日回顾", detail: "到点提醒你看看这一天记了什么。")
                Spacer()
                Button { (NSApp.delegate as? AppDelegate)?.reviewToday() } label: {
                    Label("现在回顾", systemImage: "sparkles").labelStyle(.titleAndIcon)
                }
                .buttonStyle(PillButton())
            }

            Card {
                SettingRow(title: "每天提醒", detail: "有记录才提醒，错过了下次开机补上。") {
                    HStack(spacing: 10) {
                        DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.stepperField).fixedSize()
                            .disabled(!on).opacity(on ? 1 : 0.4)
                        Toggle("", isOn: $prefs.reviewEnabled).labelsHidden()
                    }
                }
                CardDivider(inset: 16)
                SettingRow(title: "先写好 AI 总结", detail: "你确认后才写入日记。") {
                    Toggle("", isOn: $prefs.reviewAI).labelsHidden().disabled(!on)
                }
                CardDivider(inset: 16)
                LinkRow(title: "模型", value: engine ?? "去配置", strong: engine == nil) {
                    (NSApp.delegate as? AppDelegate)?.showAISettings()
                }
                CardDivider(inset: 16)
                LinkRow(title: "总结方式", value: DailyReview.tone(for: prefs.reviewPrompt)?.name ?? "自定义") {
                    editingPrompt = true
                }
                if notificationsOff {
                    CardDivider(inset: 16)
                    SettingRow(title: "系统通知已关闭", detail: "打开后才收得到提醒。") {
                        Button("去打开") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                        }
                        .buttonStyle(PillButton())
                    }
                }
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.text)

            Card {
                SettingRow(title: "「记录」窗口快捷键", detail: nil) {
                    KeyboardShortcuts.Recorder("", name: .records)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24)
        .frame(width: pageWidth, height: notificationsOff ? 446 : 386, alignment: .top)
        .background(Theme.canvas)
        .sheet(isPresented: $editingPrompt) { PromptSheet() }
        .onAppear {
            engine = AIStore.current?.label
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async { notificationsOff = s.authorizationStatus == .denied }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiChanged)) { _ in engine = AIStore.current?.label }
    }
}

/// A row whose whole width opens something: title, current value, chevron.
struct LinkRow: View {
    let title: String
    let value: String
    var strong = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(Theme.text(13, .medium)).foregroundStyle(Theme.text)
                Spacer(minLength: 12)
                Text(value).font(Theme.text(12.5)).foregroundStyle(strong ? Theme.text : Theme.muted).lineLimit(1)
                Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.subtle)
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(hover ? Theme.hover.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Picking how the day is summed up: a few presets, or the user's own prompt.
struct PromptSheet: View {
    @ObservedObject var prefs = Prefs.shared
    @Environment(\.dismiss) private var dismiss
    private var selected: String { DailyReview.tone(for: prefs.reviewPrompt)?.id ?? "custom" }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("总结方式").font(Theme.text(15, .semibold)).foregroundStyle(Theme.text)
                Text("选一种，或者在下面改成你自己的要求。").font(Theme.text(12)).foregroundStyle(Theme.muted)
            }
            Card {
                ForEach(Array(DailyReview.tones.enumerated()), id: \.element.id) { i, t in
                    if i > 0 { CardDivider(inset: 42) }
                    ToneRow(name: t.name, blurb: t.blurb, on: selected == t.id) { prefs.reviewPrompt = t.prompt }
                }
                CardDivider(inset: 42)
                ToneRow(name: "自定义", blurb: "按你自己写的要求", on: selected == "custom") {
                    let c = prefs.reviewCustomPrompt
                    if !c.isEmpty, DailyReview.tone(for: c) == nil { prefs.reviewPrompt = c }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(selected == "custom" ? "你的要求" : "这种方式的要求（改动后即为自定义）")
                    .font(Theme.text(12, .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 2)
                TextEditor(text: $prefs.reviewPrompt)
                    .font(Theme.text(12.5)).lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border))
                    .frame(height: 150)
            }
            HStack {
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(PrimaryButton()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
        .background(Theme.canvas)
        .onChange(of: prefs.reviewPrompt) { p in
            if DailyReview.tone(for: p) == nil, !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefs.reviewCustomPrompt = p
            }
        }
    }
}

private struct ToneRow: View {
    let name: String
    let blurb: String
    let on: Bool
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RadioDot(on: on)
                Text(name).font(Theme.text(13, .medium)).foregroundStyle(Theme.text)
                Text(blurb).font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).frame(height: 38)
            .background(hover ? Theme.hover.opacity(0.6) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Switch the summary style from the records window; the choice sticks.
struct ToneMenu: View {
    @ObservedObject var prefs = Prefs.shared
    var onPick: () -> Void = {}
    var body: some View {
        let current = DailyReview.tone(for: prefs.reviewPrompt)
        Menu {
            ForEach(DailyReview.tones) { t in
                Button { prefs.reviewPrompt = t.prompt; onPick() } label: {
                    if current?.id == t.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                }
            }
            if !prefs.reviewCustomPrompt.isEmpty, DailyReview.tone(for: prefs.reviewCustomPrompt) == nil {
                Button { prefs.reviewPrompt = prefs.reviewCustomPrompt; onPick() } label: {
                    if current == nil { Label("自定义", systemImage: "checkmark") } else { Text("自定义") }
                }
            }
        } label: {
            (Text(current?.name ?? "自定义") + Text("  ") + Text(Image(systemName: "chevron.down")).font(.system(size: 8, weight: .bold)))
                .font(Theme.text(12, .medium)).foregroundColor(Theme.muted)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("总结方式")
    }
}

/// Title and explanation on the left, a control on the right.
struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var control: Control
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.text(13, .medium)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(Theme.text(11.5)).foregroundStyle(Theme.muted).lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}
