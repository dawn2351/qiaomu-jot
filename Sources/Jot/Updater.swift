import AppKit
import Sparkle

/// Sparkle auto-update. Feed: the `appcast.xml` attached to the latest GitHub release (see release.sh),
/// signed with the EdDSA key whose public half is `SUPublicEDKey` in Info.plist.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController!

    func start() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    var updater: SPUUpdater? { controller?.updater }

    @objc func checkForUpdates() {
        // The update window needs keyboard focus like any normal window.
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        controller?.checkForUpdates(nil)
    }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? true }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    // MARK: Gentle reminders: a background check never throws a window over the user's work.

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        Toast.show("乔木闪记有新版本", detail: update.displayVersionString, actions: [
            .init(title: "查看") { Updater.shared.checkForUpdates() },
        ], duration: 8)
    }
}
