import Foundation
import AppKit
import UserNotifications

/// Summing up a day: what to feed the model, and writing the result back under 「今日回顾」.
enum DailyReview {
    static let heading = "今日回顾"
    /// The block Jot writes is wrapped in comments (hidden in Obsidian's reading view and most Markdown apps),
    /// so it can be replaced or undone without touching anything the user wrote around it.
    static let startMark = "<!-- jot:review -->", endMark = "<!-- /jot:review -->"

    static let defaultPrompt = """
    你是我认识多年的老朋友，晚上陪我翻一遍今天随手记下的东西，聊聊今天。

    怎么说：
    - 像朋友聊天那样直接对我说话，用「你」，口语、温和，别用报告腔，别客套。
    - 先用一两句话说说今天整体在忙什么、关心什么。
    - 再挑 2～3 个你觉得最有意思的点：某条想法为什么值得留意，或者几条记录之间你看出的联系。可以引用我的原话。
    - 如果有明显还没做完、值得明天接着做的事，提一下；没有就别硬凑。
    - 最后一句轻松的话收尾。

    要求：
    - 只根据记录说话，不编造没出现的事；看不懂的就略过。
    - 300 字以内，用 Markdown 段落或短列表，不要标题。
    """

    struct Tone: Identifiable { let id: String; let name: String; let blurb: String; let prompt: String }

    /// Ready-made ways to sum up a day; the first is the default.
    static let tones: [Tone] = [
        Tone(id: "friend", name: "老朋友", blurb: "像朋友一样陪你聊聊今天", prompt: defaultPrompt),
        Tone(id: "digest", name: "要点摘要", blurb: "按主题把记录整理成清单", prompt: """
        你是一位细心的整理者，把我今天的全部记录整理成一份摘要，方便以后回看。

        怎么写：
        - 先用一句话概括今天的记录主要关于什么。
        - 再按主题分组（3～6 组，每组一个加粗的短标题），每组用短列表列出要点；每条记录都要被覆盖到，不要遗漏。
        - 链接、书名、人名、数字等关键信息原样保留。
        - 有待办或要跟进的事，最后单独列出「待办」。

        要求：
        - 客观、简洁，不评价、不发挥，只根据记录写。
        - 用 Markdown 列表，不要一级标题，篇幅跟随记录多少，尽量精炼。
        """),
        Tone(id: "coach", name: "复盘教练", blurb: "做得好的、可改进的、明天的事", prompt: """
        你是我的复盘教练，帮我用今天的记录做一次简短复盘。

        分三部分，每部分用加粗短语开头：
        - **今天的进展**：做成了什么、推进了什么，具体到事。
        - **可以更好**：一两个值得改进的地方，或者一个值得想想的问题；要具体、有建设性，不说空话。
        - **明天先做**：最多 3 件，从记录里能看出来的事，按重要程度排。

        要求：
        - 直接对我说话，用「你」，语气务实、鼓励但不吹捧。
        - 只根据记录说话，看不出来的就别硬写。
        - 250 字以内，不要标题。
        """),
        Tone(id: "spark", name: "灵感连线", blurb: "找出想法之间的联系和新点子", prompt: """
        你是一个好奇心很强的思考伙伴，帮我从今天零散的记录里找灵感。

        怎么写：
        - 找出 2～3 组看起来无关、其实有联系的记录，说清楚它们怎么连起来，可以引用原话。
        - 基于这些联系，提 1～2 个值得继续探索的问题或可以动手试的点子。
        - 如果某条记录特别值得展开写成文章或做成东西，点出来并说一句为什么。

        要求：
        - 用「你」直接对我说话，轻松、有启发，不说教。
        - 只基于记录联想，不编造事实。
        - 300 字以内，用短段落或短列表，不要标题。
        """),
        Tone(id: "diary", name: "替我写日记", blurb: "用第一人称写成一段日记", prompt: """
        请用我的口吻，把今天的记录写成一篇简短的日记。

        怎么写：
        - 第一人称「我」，自然、真实，像晚上睡前随手写下的。
        - 按时间或心情的线索串起今天看到的、想到的、做的事，挑重要的写，不必面面俱到。
        - 可以带一点当时的感受，但不要煽情，不要升华。

        要求：
        - 只写记录里有的事，不编造经历和情绪。
        - 200～300 字，一到三段，不要标题、不要列表。
        """),
    ]

    /// The preset whose prompt matches, or nil for a custom one.
    static func tone(for prompt: String) -> Tone? {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return tones.first { $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == p }
    }

    static func dayKey(_ d: Date) -> String { MomentFormat.string(d, format: "YYYY-MM-DD") }
    static func day(fromKey k: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: k)
    }
    static func dayTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = "M月d日 EEEE"
        return f.string(from: d)
    }

    static func dailyNote(for day: Date) -> URL? {
        Prefs.shared.vaultURL.map { DailyNoteWriter(vault: $0, attachmentOverride: "").noteURL(for: day) }
    }

    struct Material { var text: String; var count: Int }

    /// The day's daily note (minus an earlier review) plus captures saved to other notes that day.
    static func material(for day: Date) -> Material? {
        var parts: [String] = []
        let items = CaptureLog.items(on: day)
        if let note = dailyNote(for: day), let s = try? String(contentsOf: note, encoding: .utf8) {
            let body = removeBlock(from: s).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { parts.append("## 当天日记\n\n" + body) }
        }
        let elsewhere = items.filter { !$0.daily }
        for i in elsewhere {
            guard let t = i.text()?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { continue }
            let name = (i.notePath as NSString).lastPathComponent
            parts.append("## \(MomentFormat.string(i.date, format: "HH:mm")) 记到「\(name)」\n\n" + String(t.prefix(4000)))
        }
        guard !parts.isEmpty else { return nil }
        var text = parts.joined(separator: "\n\n")
        if text.count > 40_000 { text = String(text.prefix(40_000)) + "\n\n（后面还有，太长截断了）" }
        return Material(text: text, count: items.count)
    }

    static func summarize(day: Date, engine: AIEngine, prompt: String = Prefs.shared.reviewPrompt) async throws -> String {
        guard let m = material(for: day) else { throw AIError(message: "这一天没有记录") }
        let when = Calendar.current.isDateInToday(day) ? "今天" : dayTitle(day)
        let user = "日期：\(dayKey(day))（\(dayTitle(day))）\n" + (m.count > 0 ? "\(when)用乔木闪记记了 \(m.count) 条。\n" : "")
            + "\n<记录>\n\(m.text)\n</记录>"
        let system = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultPrompt : prompt
        let out = try await engine.complete(system: system, user: user)
        return clean(out)
    }

    /// Drops a leading heading the model may add anyway.
    static func clean(_ s: String) -> String {
        var lines = s.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        while let f = lines.first, f.hasPrefix("#") || f.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The note without Jot's review block (and its heading).
    static func removeBlock(from text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        func t(_ i: Int) -> String { lines[i].trimmingCharacters(in: .whitespaces) }
        guard let s = lines.indices.first(where: { t($0) == startMark }),
              let e = lines.indices.first(where: { $0 > s && t($0) == endMark }) else { return text }
        var lo = s
        if lo > 0, t(lo - 1).hasPrefix("#") { lo -= 1 }        // its 「## 今日回顾」 heading
        lines.removeSubrange(lo...e)
        // Don't leave a double blank line at the seam.
        if lo > 0, t(lo - 1).isEmpty, lo == lines.count || t(lo).isEmpty { lines.remove(at: lo - 1) }
        return lines.joined(separator: "\n")
    }

    /// Replaces an earlier review, or appends one at the end.
    static func replaceBlock(_ summary: String, in text: String) -> String {
        var out = removeBlock(from: text)
        while out.hasSuffix("\n") { out.removeLast() }
        let block = "## \(heading)\n\(startMark)\n\(summary.trimmingCharacters(in: .whitespacesAndNewlines))\n\(endMark)\n"
        return out.isEmpty ? block : out + "\n\n" + block
    }

    @discardableResult
    static func write(_ summary: String, day: Date) throws -> URL {
        guard let note = dailyNote(for: day) else { throw AIError(message: "还没有选择保存位置") }
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = (try? String(contentsOf: note, encoding: .utf8)) ?? ""
        try replaceBlock(summary, in: old).write(to: note, atomically: true, encoding: .utf8)
        return note
    }

    static func unwrite(day: Date) throws {
        guard let note = dailyNote(for: day), let old = try? String(contentsOf: note, encoding: .utf8) else { return }
        var out = removeBlock(from: old)
        if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
        try out.write(to: note, atomically: true, encoding: .utf8)
    }

    static func isWritten(day: Date) -> Bool {
        guard let note = dailyNote(for: day), let s = try? String(contentsOf: note, encoding: .utf8) else { return false }
        return s.contains(startMark)
    }
}

/// Summaries generated but not yet written (the preview survives closing the window).
enum ReviewDrafts {
    private static let key = "reviewDrafts"
    static func get(_ day: Date) -> String? { all[DailyReview.dayKey(day)] }
    static func set(_ text: String?, _ day: Date) {
        var d = all
        d[DailyReview.dayKey(day)] = text
        if d.count > 14 { for k in d.keys.sorted().prefix(d.count - 14) { d[k] = nil } }
        UserDefaults.standard.set(d, forKey: key)
    }
    private static var all: [String: String] { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
}

/// Fires once a day at the chosen time; catches up after sleep or a powered-off evening.
final class ReviewScheduler {
    static let shared = ReviewScheduler()
    private var timer: Timer?
    private var running = false
    /// Opens the records window for a day (set by the app delegate).
    var open: ((Date, Bool) -> Void)?

    func start() {
        let p = Prefs.shared
        // First run: nothing to catch up on.
        if p.lastReviewDay.isEmpty { p.lastReviewDay = DailyReview.dayKey(Date().addingTimeInterval(-86400)) }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.check() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in DispatchQueue.main.asyncAfter(deadline: .now() + 20) { self?.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.check() }
    }

    /// Today once its time has passed, otherwise yesterday (missed while asleep or off).
    static func due(now: Date, minutes: Int, last: String) -> Date? {
        let cal = Calendar.current
        let m = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        let day = m >= minutes ? now : now.addingTimeInterval(-86400)
        return DailyReview.dayKey(day) > last ? day : nil
    }

    func check(now: Date = Date()) {
        let p = Prefs.shared
        guard p.reviewEnabled, !running,
              let day = Self.due(now: now, minutes: p.reviewMinutes, last: p.lastReviewDay) else { return }
        p.lastReviewDay = DailyReview.dayKey(day)
        run(day: day)
    }

    func run(day: Date) {
        guard let m = DailyReview.material(for: day) else { return }      // nothing recorded: stay quiet
        let today = Calendar.current.isDateInToday(day)
        let when = today ? "今天" : "昨天"
        let countText = m.count > 0 ? "\(when)记了 \(m.count) 条" : "\(when)的日记"
        guard Prefs.shared.reviewAI, let engine = AIStore.current else {
            notify(title: m.count > 0 ? "\(countText)，回顾一下？" : "回顾一下\(when)？", body: "点开看看\(when)记了什么", day: day)
            return
        }
        running = true
        Task {
            do {
                let s = try await DailyReview.summarize(day: day, engine: engine)
                await MainActor.run {
                    ReviewDrafts.set(s, day)
                    self.running = false
                    self.notify(title: "\(when)的回顾准备好了", body: Self.firstSentence(s) + "（点开预览，确认后写入日记）", day: day)
                }
            } catch {
                await MainActor.run {
                    self.running = false
                    self.notify(title: "\(countText)，回顾一下？", body: "AI 总结没生成：\(error.localizedDescription)", day: day)
                }
            }
        }
    }

    static func firstSentence(_ s: String) -> String {
        let plain = s.replacingOccurrences(of: #"[*_`>#\-]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let end = plain.firstIndex { "。！？\n".contains($0) }.map { plain.index(after: $0) } ?? plain.endIndex
        let first = String(plain[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return first.count > 60 ? String(first.prefix(60)) + "…" : first
    }

    func notify(title: String, body: String, day: Date) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            c.userInfo = ["day": DailyReview.dayKey(day)]
            center.add(UNNotificationRequest(identifier: "review-\(DailyReview.dayKey(day))", content: c, trigger: nil))
        }
    }
}
