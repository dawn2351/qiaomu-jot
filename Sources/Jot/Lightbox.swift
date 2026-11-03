import SwiftUI
import AppKit
import AVKit

/// Full-screen viewer for attachments: images (GIFs animate), videos play, ← → to switch.
final class LightboxModel: ObservableObject {
    @Published var urls: [URL]
    @Published var index: Int
    var onRemove: ((URL) -> Void)?
    var onClose: (() -> Void)?

    init(urls: [URL], index: Int) {
        self.urls = urls
        self.index = min(max(index, 0), max(urls.count - 1, 0))
    }

    var current: URL? { urls.indices.contains(index) ? urls[index] : nil }

    func step(_ d: Int) {
        guard urls.count > 1 else { return }
        index = (index + d + urls.count) % urls.count
    }

    func removeCurrent() {
        guard let u = current else { return }
        onRemove?(u)
        urls.remove(at: index)
        if urls.isEmpty { onClose?() } else { index = min(index, urls.count - 1) }
    }
}

final class LightboxPanel: NSPanel {
    var model: LightboxModel?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { model?.onClose?() }
    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 123: model?.step(-1)            // ←
        case 124: model?.step(1)             // →
        case 49: model?.onClose?()           // space, like Quick Look
        default: super.keyDown(with: e)
        }
    }
}

enum Lightbox {
    private static var panel: LightboxPanel?

    static func show(urls: [URL], index: Int, onRemove: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        guard !urls.isEmpty else { return }
        dismiss()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let m = LightboxModel(urls: urls, index: index)
        m.onRemove = onRemove
        m.onClose = { DispatchQueue.main.async { dismiss(); onClose() } }
        let p = LightboxPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        p.model = m
        p.contentView = NSHostingView(rootView: LightboxView(model: m))
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.setFrame(frame, display: false)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(nil)            // arrows/space go to the panel's keyDown
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct LightboxView: View {
    @ObservedObject var model: LightboxModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .contentShape(Rectangle())
                .onTapGesture { model.onClose?() }

            if let url = model.current {
                MediaView(url: url)
                    .id(url)
                    .padding(.horizontal, 110).padding(.top, 80).padding(.bottom, model.urls.count > 1 ? 120 : 80)
                    .transition(.opacity)
            }

            if model.urls.count > 1 {
                HStack {
                    NavButton(symbol: "chevron.left") { model.step(-1) }
                    Spacer()
                    NavButton(symbol: "chevron.right") { model.step(1) }
                }
                .padding(.horizontal, 32)
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if model.urls.count > 1 { filmstrip.padding(.bottom, 28) }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.easeOut(duration: 0.15), value: model.index)
        .animation(.easeOut(duration: 0.15), value: model.urls)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if let url = model.current {
                Text(url.lastPathComponent).font(Theme.sans(13, .medium)).foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1).truncationMode(.middle)
            }
            if model.urls.count > 1 {
                Text("\(model.index + 1) / \(model.urls.count)").font(Theme.mono(12)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            GhostButton(title: "在 Finder 中显示", symbol: "folder") {
                if let u = model.current { NSWorkspace.shared.activateFileViewerSelecting([u]) }
            }
            GhostButton(title: "移除", symbol: "trash") { model.removeCurrent() }
            GhostButton(title: nil, symbol: "xmark") { model.onClose?() }
        }
        .padding(.horizontal, 24).padding(.top, 20)
    }

    private var filmstrip: some View {
        HStack(spacing: 8) {
            ForEach(Array(model.urls.enumerated()), id: \.element) { i, url in
                Button { model.index = i } label: {
                    Thumbnail(url: url, size: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(i == model.index ? Color.white : Color.white.opacity(0.12),
                                          lineWidth: i == model.index ? 2 : 1))
                        .opacity(i == model.index ? 1 : 0.55)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

struct MediaView: View {
    let url: URL
    var body: some View {
        switch MediaKind(url) {
        case .image, .gif:
            AnimatedImageView(url: url)
        case .video:
            VideoView(url: url)
        case .other:
            VStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 128, height: 128)
                Text(url.lastPathComponent).font(Theme.sans(14, .medium)).foregroundStyle(.white)
                GhostButton(title: "用默认应用打开", symbol: "arrow.up.right.square") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

/// NSImageView animates GIFs natively and scales large images down to fit.
struct AnimatedImageView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.image = NSImage(contentsOf: url)
        v.animates = true
        v.imageScaling = .scaleProportionallyDown
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        return v
    }
    func updateNSView(_ v: NSImageView, context: Context) {}
}

struct VideoView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = AVPlayer(url: url)
        v.controlsStyle = .floating
        v.videoGravity = .resizeAspect
        v.player?.play()
        return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) {}
    static func dismantleNSView(_ v: AVPlayerView, coordinator: ()) { v.player?.pause() }
}

struct NavButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(hover ? 0.18 : 0.08)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct GhostButton: View {
    let title: String?
    let symbol: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                if let title { Text(title).font(Theme.sans(12, .medium)) }
            }
            .foregroundStyle(.white.opacity(hover ? 1 : 0.75))
            .padding(.horizontal, title == nil ? 0 : 10).frame(minWidth: 30, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hover ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
