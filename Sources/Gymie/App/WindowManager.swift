import AppKit
import SwiftUI

/// AppKit-owned windows, so the scheduler can open them without a SwiftUI scene and
/// so closing the break window can count as a skip.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private var breakWindow: NSWindow?
    private var breakClosed: (() -> Void)?
    private var settingsWindow: NSWindow?
    private var practiceWindow: NSWindow?
    private var practiceCoach: PoseCoach?

    var isBreakOpen: Bool { breakWindow != nil }

    func showBreak(session: BreakSession, onClose: @escaping () -> Void) {
        closeBreak(notify: false)
        let window = makeWindow(title: "Gymie break", size: NSSize(width: 960, height: 640),
                                content: BreakView(session: session).environment(AppModel.shared))
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        breakWindow = window
        breakClosed = onClose
        present(window)
    }

    func focusBreak() {
        if let breakWindow { present(breakWindow) }
    }

    /// Closes the break window; `notify` runs the close handler (which may count a skip).
    func closeBreak(notify: Bool = true) {
        guard let window = breakWindow else { return }
        if !notify { breakClosed = nil }
        window.close()
    }

    func showSettings(model: AppModel) {
        if let settingsWindow { present(settingsWindow); return }
        let window = makeWindow(title: "Gymie Settings", size: NSSize(width: 620, height: 600),
                                content: SettingsView().environment(model))
        settingsWindow = window
        present(window)
    }

    func showPractice(model: AppModel) {
        if let practiceWindow { present(practiceWindow); return }
        let coach = PoseCoach()
        practiceCoach = coach
        let window = makeWindow(title: "Gymie Practice", size: NSSize(width: 900, height: 600),
                                content: PracticeView(coach: coach).environment(model))
        practiceWindow = window
        present(window)
    }

    private func makeWindow(title: String, size: NSSize, content: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === breakWindow {
            breakWindow = nil
            let done = breakClosed
            breakClosed = nil
            done?()
        } else if window === settingsWindow {
            settingsWindow = nil
        } else if window === practiceWindow {
            practiceCoach?.stop()
            practiceCoach = nil
            practiceWindow = nil
        }
        // Defer so the closing window's hosting view is released after AppKit finishes with it.
        DispatchQueue.main.async { window.contentViewController = nil }
    }
}
