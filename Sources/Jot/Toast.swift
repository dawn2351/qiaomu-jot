import SwiftUI
import AppKit

/// Small non-activating notice at the top of the screen, e.g. "已收录 · 来自 Safari  撤销  补充想法".
enum Toast {
    struct Action: Identifiable {
        let id = UUID()
        let title: String
        let run: () -> Void
    }
    enum Style { case success, warning }

    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?
    private(set) static var isShowingCapture = false

    static func show(_ title: String, detail: String? = nil, source: SourceInfo? = nil, style: Style = .success,
                     actions: [Action] = [], duration: TimeInterval = 3) {
        dismiss()
        isShowingCapture = style == .success && !actions.isEmpty
        let view = ToastView(title: title, detail: detail, source: source, style: style, actions: actions.map { a in
            Action(title: a.title) { dismiss(); a.run() }
        }, onHover: { hovering in hovering ? hideWork?.cancel() : schedule(1.6) })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.maxY - size.height - 14))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
        panel = p
        schedule(duration)
    }

    private static func schedule(_ delay: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { dismiss(animated: true) }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    static func dismiss(animated: Bool = false) {
        hideWork?.cancel()
        isShowingCapture = false
        guard let p = panel else { return }
        panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; p.animator().alphaValue = 0 },
                                                completionHandler: { p.orderOut(nil) })
        } else {
            p.orderOut(nil)
        }
    }
}

struct ToastView: View {
    let title: String
    let detail: String?
    var source: SourceInfo? = nil
    let style: Toast.Style
    let actions: [Toast.Action]
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: style == .success ? "checkmark" : "exclamationmark")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.inverse)
                .frame(width: 18, height: 18)
                .background(Circle().fill(style == .success ? Theme.text : Color.orange))
            Text(title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.text)
            if let source {
                SourceGlyph(bundleID: source.bundleID, kind: source.kind, size: 13, color: Theme.muted)
                    .help(source.app)
            }
            if let detail {
                Text(detail).font(Theme.sans(12)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 240, alignment: .leading).fixedSize(horizontal: true, vertical: false)
            }
            if !actions.isEmpty {
                Rectangle().fill(Theme.border).frame(width: 1, height: 16).padding(.horizontal, 2)
                ForEach(actions) { a in
                    ToastButton(title: a.title, action: a.run)
                }
            }
        }
        .padding(.leading, 12).padding(.trailing, actions.isEmpty ? 16 : 6)
        .frame(height: 40)
        .background(Capsule().fill(Theme.background))
        .overlay(Capsule().strokeBorder(Theme.border))
        .padding(1)
        .onHover(perform: onHover)
    }
}

private struct ToastButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.sans(12, .medium))
                .foregroundStyle(hover ? Theme.text : Theme.muted)
                .padding(.horizontal, 10).frame(height: 28)
                .background(Capsule().fill(hover ? Theme.hover : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
