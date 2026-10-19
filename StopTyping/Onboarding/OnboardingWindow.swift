import AppKit
import SwiftUI

/// Hosts the setup checklist in an ordinary titled window, so it can be moved, closed and reopened from
/// the menu bar panel. Built from code rather than as a SwiftUI scene, so `AppModel` can open it at launch.
@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let controller = NSHostingController(rootView: OnboardingView().environment(model))
        // Lets the window grow when a row adds a line, such as the hint that notifications are turned off.
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable]
        window.title = String(localized: "Set Up Stop Typing App")
        // The content opens with its own heading, so the title stays for VoiceOver and the Window menu only.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.setContentSize(controller.view.fittingSize)

        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            ))
        }
        return window
    }
}
