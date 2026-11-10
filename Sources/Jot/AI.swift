import Foundation
import Security

// MARK: - Catalog

/// The two wire formats Jot speaks. Almost every vendor and gateway offers one of them.
enum AIProtocol: String, Codable, CaseIterable {
    case openai, anthropic
    var label: String { self == .openai ? "OpenAI 兼容" : "Anthropic" }
}

/// A built-in service: where to send requests, where to get a key, which models to suggest.
struct AIPreset: Identifiable {
    enum Group: String { case provider = "厂商", relay = "中转", local = "本地", custom = "自定义" }
    let id: String
    let name: String
    let group: Group
    let proto: AIProtocol
    let baseURL: String
    let keyURL: String?
    let models: [String]
    var keyRequired = true

    /// DeepSeek first (cheap, good Chinese, reachable from China), then the rest of the Chinese vendors.
    static let all: [AIPreset] = [
        .init(id: "deepseek", name: "DeepSeek", group: .provider, proto: .openai, baseURL: "https://api.deepseek.com/v1",
              keyURL: "https://platform.deepseek.com/api_keys", models: ["deepseek-chat", "deepseek-reasoner"]),
        .init(id: "moonshot", name: "Kimi", group: .provider, proto: .openai, baseURL: "https://api.moonshot.cn/v1",
              keyURL: "https://platform.moonshot.cn/console/api-keys", models: ["kimi-k3", "kimi-k2.6"]),
        .init(id: "qwen", name: "通义千问", group: .provider, proto: .openai, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
              keyURL: "https://bailian.console.aliyun.com/?apiKey=1", models: ["qwen-plus", "qwen-max"]),
        .init(id: "zhipu", name: "智谱 GLM", group: .provider, proto: .openai, baseURL: "https://open.bigmodel.cn/api/paas/v4",
              keyURL: "https://open.bigmodel.cn/usercenter/apikeys", models: []),
        .init(id: "doubao", name: "豆包", group: .provider, proto: .openai, baseURL: "https://ark.cn-beijing.volces.com/api/v3",
              keyURL: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey", models: []),
        .init(id: "minimax", name: "MiniMax", group: .provider, proto: .openai, baseURL: "https://api.minimaxi.com/v1",
              keyURL: "https://platform.minimaxi.com/user-center/basic-information/interface-key", models: []),
        .init(id: "openai", name: "OpenAI", group: .provider, proto: .openai, baseURL: "https://api.openai.com/v1",
              keyURL: "https://platform.openai.com/api-keys", models: ["gpt-5.6-luna", "gpt-5.6-terra"]),
        .init(id: "anthropic", name: "Anthropic", group: .provider, proto: .anthropic, baseURL: "https://api.anthropic.com/v1",
              keyURL: "https://console.anthropic.com/settings/keys", models: ["claude-haiku-4-5", "claude-sonnet-5"]),
        .init(id: "gemini", name: "Google Gemini", group: .provider, proto: .openai,
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
              keyURL: "https://aistudio.google.com/app/apikey", models: ["gemini-3.5-flash"]),
        .init(id: "siliconflow", name: "硅基流动", group: .relay, proto: .openai, baseURL: "https://api.siliconflow.cn/v1",
              keyURL: "https://cloud.siliconflow.cn/account/ak", models: ["deepseek-ai/deepseek-v4-flash"]),
        .init(id: "openrouter", name: "OpenRouter", group: .relay, proto: .openai, baseURL: "https://openrouter.ai/api/v1",
              keyURL: "https://openrouter.ai/settings/keys", models: []),
        .init(id: "magpie", name: "Magpie", group: .local, proto: .openai, baseURL: "http://127.0.0.1:3425/v1",
              keyURL: "https://github.com/yetone/magpie", models: [], keyRequired: false),
        .init(id: "ollama", name: "Ollama", group: .local, proto: .openai, baseURL: "http://127.0.0.1:11434/v1",
              keyURL: nil, models: [], keyRequired: false),
        .init(id: "custom", name: "自定义", group: .custom, proto: .openai, baseURL: "", keyURL: nil, models: [], keyRequired: false),
    ]

    static func find(_ id: String) -> AIPreset? { all.first { $0.id == id } }

    /// Lobe Icons mark (Resources/Icons/ai), nil = monogram.
    var icon: String? {
        ["deepseek": "deepseek", "moonshot": "kimi", "qwen": "qwen", "zhipu": "zhipu", "doubao": "doubao", "minimax": "minimax",
         "openai": "openai", "anthropic": "anthropic", "gemini": "gemini", "siliconflow": "siliconcloud",
         "openrouter": "openrouter", "ollama": "ollama"][id]
    }
    /// One line under the name in the gallery.
    var blurb: String {
        switch id {
        case "deepseek": return "便宜，中文好"
        case "moonshot": return "月之暗面"
        case "qwen": return "阿里云百炼"
        case "zhipu": return "智谱开放平台"
        case "doubao": return "火山方舟"
        case "minimax": return "MiniMax 开放平台"
        case "openai": return "GPT 系列"
        case "anthropic": return "Claude 系列"
        case "gemini": return "Google AI Studio"
        case "siliconflow": return "多家开源模型"
        case "openrouter": return "数百个模型"
        case "magpie": return "自建或本机网关"
        case "ollama": return "本机运行开源模型"
        default: return "兼容 OpenAI 的接口"
        }
    }
    /// Address field always visible: the user has to supply or often changes it.
    var showsAddress: Bool { group == .local || group == .custom }
}

/// A service the user added. The key lives in the Keychain under `id`.
struct AIProvider: Codable, Identifiable, Equatable {
    var id: String
    var preset: String
    var name: String
    var proto: AIProtocol
    var baseURL: String
    var model: String
    /// Set by the last successful test; any edit clears it.
    var verified: Bool = false

    var presetInfo: AIPreset? { AIPreset.find(preset) }
    var hasKey: Bool { KeyStore.get(id) != nil }
    var ready: Bool { !model.isEmpty && !baseURL.isEmpty && (hasKey || presetInfo?.keyRequired == false) }
    var label: String { "\(name) · \(model)" }

    static func new(_ p: AIPreset) -> AIProvider {
        let taken = Set(AIStore.providers.map(\.id))
        var id = p.id, n = 2
        while taken.contains(id) { id = "\(p.id)-\(n)"; n += 1 }
        return AIProvider(id: id, preset: p.id, name: p.group == .custom ? "" : p.name, proto: p.proto, baseURL: p.baseURL, model: p.models.first ?? "")
    }
}

/// Two mutually exclusive ways to run AI: a cloud service with a key, or a coding CLI already signed in on this Mac.
/// Each mode remembers its own choice, so switching back and forth loses nothing.
enum AIMode: String { case api, cli }

enum AIStore {
    private static let providersKey = "aiProviders", apiKey = "aiDefault", cliKey = "aiCLI", modeKey = "aiMode"
    private static var d: UserDefaults { .standard }

    static var providers: [AIProvider] {
        get { d.data(forKey: providersKey).flatMap { try? JSONDecoder().decode([AIProvider].self, from: $0) } ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: providersKey); changed() }
    }

    static var mode: AIMode {
        get {
            migrate()
            return AIMode(rawValue: d.string(forKey: modeKey) ?? "") ?? .api
        }
        set { d.set(newValue.rawValue, forKey: modeKey); changed() }
    }
    /// The chosen cloud service.
    static var apiID: String {
        get { migrate(); return d.string(forKey: apiKey) ?? "" }
        set { d.set(newValue, forKey: apiKey); changed() }
    }
    /// The chosen CLI; defaults to the first one installed.
    static var cliTool: LocalCLI.Tool? {
        get { migrate(); return LocalCLI.Tool(rawValue: d.string(forKey: cliKey) ?? "") ?? LocalCLI.installed.first }
        set { d.set(newValue?.rawValue, forKey: cliKey); changed() }
    }

    /// 1.6.0 builds kept "cli:<tool>" in the API slot.
    private static func migrate() {
        guard let v = d.string(forKey: apiKey), v.hasPrefix("cli:") else { return }
        d.set(String(v.dropFirst(4)), forKey: cliKey)
        d.set(AIMode.cli.rawValue, forKey: modeKey)
        d.set("", forKey: apiKey)
    }

    private static func changed() { NotificationCenter.default.post(name: .aiChanged, object: nil) }

    static func save(_ p: AIProvider) {
        var list = providers
        if let i = list.firstIndex(where: { $0.id == p.id }) { list[i] = p } else { list.append(p) }
        providers = list
        if !list.contains(where: { $0.id == apiID && $0.ready }) { apiID = p.id }
    }

    static func remove(_ id: String) {
        providers = providers.filter { $0.id != id }
        KeyStore.set(nil, for: id)
        if apiID == id { apiID = providers.first(where: \.ready)?.id ?? "" }
    }

    /// The service the API mode would use (its choice, else the first ready one).
    static var apiProvider: AIProvider? {
        let list = providers
        return list.first { $0.id == apiID && $0.ready } ?? list.first(where: \.ready)
    }

    /// What to call for AI work, or nil when the chosen mode isn't set up.
    static var current: AIEngine? {
        switch mode {
        case .api: return apiProvider.map { .http($0) }
        case .cli: return cliTool.flatMap { LocalCLI.path($0) != nil ? .cli($0) : nil }
        }
    }
}

extension Notification.Name {
    static let aiChanged = Notification.Name("aiChanged")
}

enum AIEngine {
    case http(AIProvider)
    case cli(LocalCLI.Tool)

    var label: String {
        switch self {
        case .http(let p): return p.label
        case .cli(let t): return "本机 \(t.name)"
        }
    }

    func complete(system: String, user: String) async throws -> String {
        switch self {
        case .http(let p): return try await LLMClient.chat(p, system: system, user: user)
        case .cli(let t): return try await LocalCLI.run(t, prompt: system + "\n\n---\n\n" + user)
        }
    }
}

// MARK: - Keychain

enum KeyStore {
    private static let service = "ai.qiaomu.jot.llm"
    private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    static func get(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[account] { return hit }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        let value = SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
            ? (out as? Data).flatMap { String(data: $0, encoding: .utf8) } : nil
        cache[account] = value
        return value
    }

    static func set(_ value: String?, for account: String) {
        lock.lock(); defer { lock.unlock() }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        cache[account] = .some(nil)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrLabel as String] = "乔木闪记 · AI Key"
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess { cache[account] = value }
    }

    /// "••••1234" for the settings field.
    static func masked(_ account: String) -> String? {
        guard let k = get(account), k.count > 4 else { return nil }
        return "••••" + k.suffix(4)
    }
}

// MARK: - HTTP

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum LLMClient {
    /// Accepts a pasted base URL or a full endpoint ("…/v1/chat/completions") and keeps the base.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/chat/completions", "/messages", "/models"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private static func request(_ p: AIProvider, key override: String?, path: String, body: [String: Any]?,
                                timeout: TimeInterval) throws -> URLRequest {
        let base = normalize(p.baseURL)
        guard let url = URL(string: base + path), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            throw AIError(message: "地址格式不对，应类似 https://api.example.com/v1")
        }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = body == nil ? "GET" : "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Local gateways (Magpie) accept any bearer token but still want one.
        let key = override ?? KeyStore.get(p.id) ?? (p.presetInfo?.keyRequired == false ? "jot" : "")
        if p.proto == .anthropic {
            r.setValue(key, forHTTPHeaderField: "x-api-key")
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let body { r.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return r
    }

    private static func send(_ r: URLRequest) async throws -> [String: Any] {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: r) } catch let e as URLError {
            switch e.code {
            case .timedOut: throw AIError(message: "请求超时，服务可能太忙，稍后再试")
            case .notConnectedToInternet, .networkConnectionLost: throw AIError(message: "网络未连接")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                throw AIError(message: "连不上 \(r.url?.host ?? "服务器")，检查地址或网络（本地服务是否已启动）")
            case .appTransportSecurityRequiresSecureConnection: throw AIError(message: "只支持 https 地址（本机地址除外）")
            default: throw AIError(message: e.localizedDescription)
            }
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else { throw describe(status: status, obj: obj, data: data) }
        guard let obj else { throw AIError(message: "返回的不是 JSON，地址可能不对") }
        return obj
    }

    static func describe(status: Int, obj: [String: Any]?, data: Data) -> AIError {
        let err = obj?["error"]
        let detail = (err as? [String: Any])?["message"] as? String ?? err as? String ?? obj?["message"] as? String
            ?? String(String(data: data, encoding: .utf8)?.prefix(160) ?? "")
        let lower = detail.lowercased()
        let reason: String
        switch status {
        case 401, 403: reason = "Key 无效或没有权限"
        case 402: reason = "余额不足"
        case 404: reason = "地址或模型名不对"
        case 429 where lower.contains("quota") || lower.contains("insufficient"): reason = "额度用完了"
        case 429: reason = "请求太频繁，稍后再试"
        case 500...599: reason = "服务暂时不可用"
        default: reason = lower.contains("insufficient") || lower.contains("balance") ? "余额不足" : "请求失败（\(status)）"
        }
        return AIError(message: detail.isEmpty ? reason : "\(reason)：\(detail)")
    }

    /// `key` tests a key the user typed before it is saved.
    static func chat(_ p: AIProvider, key: String? = nil, system: String, user: String, maxTokens: Int = 2048,
                     timeout: TimeInterval = 120) async throws -> String {
        guard !p.model.isEmpty else { throw AIError(message: "还没有选模型") }
        if p.presetInfo?.keyRequired != false, (key ?? KeyStore.get(p.id)) == nil { throw AIError(message: "还没有填 Key") }
        let obj: [String: Any]
        if p.proto == .anthropic {
            obj = try await send(request(p, key: key, path: "/messages", body: [
                "model": p.model, "max_tokens": maxTokens, "system": system,
                "messages": [["role": "user", "content": user]],
            ], timeout: timeout))
            let text = (obj["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
            if !text.isEmpty { return text }
        } else {
            obj = try await send(request(p, key: key, path: "/chat/completions", body: [
                "model": p.model, "max_tokens": maxTokens, "stream": false,
                "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            ], timeout: timeout))
            let msg = ((obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])
            if let text = msg?["content"] as? String, !text.isEmpty { return Self.stripThinking(text) }
        }
        throw AIError(message: "模型没有返回内容")
    }

    /// Some reasoning models put <think>…</think> before the answer.
    static func stripThinking(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?s)^\s*<think>.*?</think>\s*"#, with: "", options: .regularExpression)
    }

    /// One short round trip; returns the elapsed milliseconds.
    static func test(_ p: AIProvider, key: String? = nil) async throws -> Int {
        let t0 = Date()
        _ = try await chat(p, key: key, system: "You are a connectivity check.", user: "Reply with the single word OK.",
                           maxTokens: 16, timeout: 30)
        return Int(Date().timeIntervalSince(t0) * 1000)
    }

    /// GET /models: doubles as a key check when the user hasn't picked a model yet.
    static func models(_ p: AIProvider, key: String? = nil) async throws -> [String] {
        let obj = try await send(request(p, key: key, path: "/models", body: nil, timeout: 15))
        let ids = (obj["data"] as? [[String: Any]] ?? obj["models"] as? [[String: Any]] ?? [])
            .compactMap { $0["id"] as? String ?? $0["name"] as? String }
        return Array(Set(ids)).sorted().prefix(500).map { $0 }
    }
}

// MARK: - Local CLIs

/// Coding-agent CLIs already signed in on this Mac. No key needed; text in, text out.
enum LocalCLI {
    enum Tool: String, CaseIterable, Identifiable {
        case claude, codex, gemini
        var id: String { rawValue }
        var name: String {
            switch self { case .claude: return "Claude Code"; case .codex: return "Codex"; case .gemini: return "Gemini CLI" }
        }
        var icon: String { self == .gemini ? "gemini" : rawValue }
        var vendor: String {
            switch self { case .claude: return "Anthropic"; case .codex: return "OpenAI"; case .gemini: return "Google" }
        }
        var installURL: URL {
            switch self {
            case .claude: return URL(string: "https://docs.anthropic.com/en/docs/claude-code/overview")!
            case .codex: return URL(string: "https://github.com/openai/codex")!
            case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")!
            }
        }
    }

    /// A GUI app gets a bare PATH; look where installers put these tools.
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        dirs += ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.bun/bin",
                 "\(home)/.volta/bin", "\(home)/.npm-global/bin", "\(home)/Library/pnpm", "\(home)/.cargo/bin"]
        let nvm = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm) {
            dirs += versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }.map { "\(nvm)/\($0)/bin" }
        }
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }

    static func path(_ tool: Tool) -> String? {
        searchPaths.map { "\($0)/\(tool.rawValue)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var installed: [Tool] { Tool.allCases.filter { path($0) != nil } }

    /// Runs the tool read-only in a scratch folder with the prompt on stdin.
    static func run(_ tool: Tool, prompt: String, timeout: TimeInterval = 180) async throws -> String {
        guard let exe = path(tool) else { throw AIError(message: "没找到 \(tool.name)") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jot-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let lastMessage = dir.appendingPathComponent("answer.txt")
        let args: [String]
        switch tool {
        case .claude: args = ["-p", "--output-format", "text", "--disallowedTools", "Bash,Edit,Write,WebFetch,WebSearch"]
        case .codex: args = ["exec", "--skip-git-repo-check", "-s", "read-only", "-o", lastMessage.path, "-"]
        case .gemini: args = ["--approval-mode", "plan", "-p", " "]
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = searchPaths.joined(separator: ":")
        env["NO_COLOR"] = "1"
        p.environment = env
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global().async {
                do { try p.run() } catch { cont.resume(throwing: AIError(message: "启动 \(tool.name) 失败：\(error.localizedDescription)")); return }
                let kill = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: kill)
                stdin.fileHandleForWriting.write(Data(prompt.utf8))
                try? stdin.fileHandleForWriting.close()
                // Read both pipes before waiting so a chatty tool can't fill a buffer and stall.
                var errData = Data()
                let errDone = DispatchGroup()
                errDone.enter()
                DispatchQueue.global().async { errData = stderr.fileHandleForReading.readDataToEndOfFile(); errDone.leave() }
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                errDone.wait()
                kill.cancel()
                var text = String(data: out, encoding: .utf8) ?? ""
                if tool == .codex, let last = try? String(contentsOf: lastMessage, encoding: .utf8) { text = last }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if p.terminationReason == .uncaughtSignal { cont.resume(throwing: AIError(message: "\(tool.name) 超时")); return }
                if p.terminationStatus != 0 || text.isEmpty {
                    let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let tail = err.split(separator: "\n").suffix(3).joined(separator: " ")
                    cont.resume(throwing: AIError(message: "\(tool.name) 出错" + (tail.isEmpty ? "" : "：\(tail.prefix(200))")))
                    return
                }
                cont.resume(returning: LLMClient.stripThinking(text))
            }
        }
    }
}
