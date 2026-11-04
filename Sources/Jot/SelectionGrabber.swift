import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// File links on the pasteboard that are safe to use. Apps like WeChat put a link into their own
/// sandbox container (~/Library/Containers/…) next to the image data; reading that link triggers macOS's
/// "App Data" privacy check with nothing the user can grant. Prefer the data whenever it's there.
enum PasteboardFiles {
    static func isInOtherAppsContainer(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        return p.contains("/Library/Containers/") || p.contains("/Library/Group Containers/")
    }

    static var mediaDataTypes: [NSPasteboard.PasteboardType] {
        CaptureModel.mediaTypes.map { NSPasteboard.PasteboardType($0.type.identifier) } + [.tiff]
    }

    /// Usable file URLs, or nil when the pasteboard's own image/video data should be used instead.
    static func usable(_ pb: NSPasteboard) -> [URL]? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        if urls.contains(where: isInOtherAppsContainer), pb.availableType(from: mediaDataTypes) != nil { return nil }
        // Files only: a copied folder would pull a whole directory into the vault.
        let files = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
        return files.isEmpty ? nil : files
    }
}

/// Raw selection from the frontmost app.
struct Grabbed {
    var text = ""
    var html: String?
    var files: [URL] = []
    var media: [(data: Data, ext: String)] = []
    var concealed = false

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.isEmpty && media.isEmpty
    }
}

/// Grabs the selection in the frontmost app.
/// Plain-text sources are read through Accessibility, which leaves the clipboard untouched.
/// Browsers, Mail, Notes and Finder (rich text, links, files) and apps that don't expose their
/// selection get a synthetic ⌘C; the user's clipboard is restored right afterwards.
enum SelectionGrabber {
    static func ensureAccessibility(prompt: Bool = true) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func grab(_ ctx: SourceContext?, timeout: TimeInterval, _ done: @escaping (Grabbed) -> Void) {
        let rich: Bool
        switch ctx?.kind {
        case .browser, .mail, .notes, .finder: rich = true
        default: rich = false
        }
        let ax = AX.selectedText()
        // Accessibility answered and nothing is selected: don't touch the clipboard at all.
        if let ax, ax.isEmpty, ctx?.kind != .finder { done(Grabbed()); return }
        if let ax, !ax.isEmpty, !rich { done(Grabbed(text: ax)); return }

        let pb = NSPasteboard.general
        let before = pb.changeCount
        let backup: [[(NSPasteboard.PasteboardType, Data)]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        sendCopy()
        poll(pb, before: before, deadline: Date().addingTimeInterval(timeout)) { changed in
            var g = Grabbed()
            if changed {
                g = read(pb)
                restore(pb, backup)
            }
            if g.isEmpty, let ax, !ax.isEmpty { g = Grabbed(text: ax) }
            done(g)
        }
    }

    private static func poll(_ pb: NSPasteboard, before: Int, deadline: Date, _ cb: @escaping (Bool) -> Void) {
        if pb.changeCount != before {
            // Some apps write several types in steps; give them a beat to finish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { cb(true) }
            return
        }
        if Date() > deadline { cb(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { poll(pb, before: before, deadline: deadline, cb) }
    }

    static func read(_ pb: NSPasteboard) -> Grabbed {
        var g = Grabbed()
        let types = pb.types ?? []
        g.concealed = types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        if let files = PasteboardFiles.usable(pb) {
            g.files = files
            return g
        }
        g.text = pb.string(forType: .string) ?? ""
        g.html = pb.string(forType: .html) ?? webArchiveHTML(pb)
        let s = g.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let textIsIncidental = s.isEmpty || (!s.contains(where: \.isWhitespace) && URL(string: s)?.scheme != nil)
        if textIsIncidental {
            let mediaTypes = CaptureModel.mediaTypes.map { NSPasteboard.PasteboardType($0.type.identifier) }
            if let t = pb.availableType(from: mediaTypes), let data = pb.data(forType: t),
               let ext = CaptureModel.mediaTypes.first(where: { $0.type.identifier == t.rawValue })?.ext {
                g.media = [(data, ext)]
            } else if let tiff = pb.data(forType: .tiff),
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                g.media = [(png, "png")]
            }
            if !g.media.isEmpty { g.text = ""; g.html = nil }
        }
        return g
    }

    /// Safari puts the selection on the pasteboard as a web archive rather than plain HTML.
    private static func webArchiveHTML(_ pb: NSPasteboard) -> String? {
        guard let data = pb.data(forType: NSPasteboard.PasteboardType("com.apple.webarchive")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let main = plist["WebMainResource"] as? [String: Any],
              let html = main["WebResourceData"] as? Data else { return nil }
        let encoding = (main["WebResourceTextEncodingName"] as? String)?.lowercased()
        return String(data: html, encoding: encoding == "utf-16" ? .utf16 : .utf8)
            ?? String(data: html, encoding: .isoLatin1)
    }

    private static func restore(_ pb: NSPasteboard, _ backup: [[(NSPasteboard.PasteboardType, Data)]]) {
        pb.clearContents()
        let items: [NSPasteboardItem] = backup.enumerated().map { i, pairs in
            let it = NSPasteboardItem()
            for (t, d) in pairs { it.setData(d, forType: t) }
            // Tell clipboard managers this restore isn't a new copy.
            if i == 0 { it.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) }
            return it
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }

    private static func sendCopy() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)   // 'c'
        let up = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap); up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
