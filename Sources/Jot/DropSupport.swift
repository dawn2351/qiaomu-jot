import AppKit
import UniformTypeIdentifiers

/// One drop pipeline for the capture panel, its text view and the menu bar icon.
/// SwiftUI's `.onDrop` only sees plain file URLs; Photos, Mail, the screenshot thumbnail and many
/// browser image drags deliver *file promises* (the file is written after the drop), which need AppKit.
final class MediaDropHandler {
    weak var model: CaptureModel?
    init(model: CaptureModel) { self.model = model }

    static let promiseQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        return q
    }()

    private static var mediaTypes: [NSPasteboard.PasteboardType] {
        CaptureModel.mediaTypes.map { NSPasteboard.PasteboardType($0.type.identifier) } + [.tiff]
    }

    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string] + mediaTypes
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    /// Files, promises or image/video data (as opposed to text, which the text view inserts itself).
    static func isMedia(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pb.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
            || pb.availableType(from: mediaTypes) != nil
    }

    func setTargeted(_ on: Bool) {
        guard let model, model.dropTargeted != on else { return }
        model.dropTargeted = on
    }

    /// Attaches dropped media; text and links are added to the note. Returns false if nothing usable.
    @discardableResult
    func perform(_ pb: NSPasteboard) -> Bool {
        guard let model else { return false }
        // 1. Real files (Finder, most apps).
        if let files = PasteboardFiles.usable(pb) {
            model.add(urls: files)
            return true
        }
        // 2. File promises: keep the original file (name, format, GIF animation).
        if let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            model.adoptTemp([dir])
            for p in promises {
                p.receivePromisedFiles(atDestination: dir, options: [:], operationQueue: Self.promiseQueue) { [weak model] url, error in
                    DispatchQueue.main.async {
                        if error == nil { model?.add(urls: [url]) } else { model?.error = "无法接收拖入的文件" }
                    }
                }
            }
            return true
        }
        // 3. Raw image / video data.
        if let t = pb.availableType(from: Self.mediaTypes), let data = pb.data(forType: t) {
            if let ext = CaptureModel.mediaTypes.first(where: { $0.type.identifier == t.rawValue })?.ext {
                model.add(imageData: data, ext: ext)
            } else if let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                model.add(imageData: png, ext: "png")
            }
            return true
        }
        // 4. A link (e.g. dragged from a browser's address bar) → [title](url).
        if let url = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first, url.scheme?.hasPrefix("http") == true {
            let title = pb.string(forType: NSPasteboard.PasteboardType("public.url-name"))
            model.appendText(title.map { "[\($0)](\(url.absoluteString))" } ?? url.absoluteString)
            return true
        }
        // 5. Plain text dropped outside the editor.
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.appendText(s)
            return true
        }
        return false
    }
}

/// The panel's root view: catches drops anywhere in the panel (SwiftUI content registers none).
final class DropContainerView: NSView {
    var handler: MediaDropHandler? {
        didSet { registerForDraggedTypes(MediaDropHandler.acceptedTypes) }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        handler?.setTargeted(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { handler?.setTargeted(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        handler?.setTargeted(false)
        return handler?.perform(sender.draggingPasteboard) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { handler?.setTargeted(false) }
}

/// Drops on the menu bar icon open the capture panel with the dropped content.
/// (The status button's window forwards dragging calls to its delegate.)
final class StatusItemDropTarget: NSObject, NSWindowDelegate, NSDraggingDestination {
    var onDrop: ((NSPasteboard) -> Bool)?
    weak var button: NSStatusBarButton?

    func install(on button: NSStatusBarButton) {
        self.button = button
        button.window?.registerForDraggedTypes(MediaDropHandler.acceptedTypes)
        button.window?.delegate = self
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        button?.highlight(true)
        return .copy
    }
    func draggingExited(_ sender: NSDraggingInfo?) { button?.highlight(false) }
    func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.highlight(false)
        return onDrop?(sender.draggingPasteboard) ?? false
    }
}
