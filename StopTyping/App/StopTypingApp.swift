import AppKit
import SwiftUI

@main
struct StopTypingApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel()
                .environment(appDelegate.model)
        } label: {
            StatusIcon()
                .environment(appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.model)
                .environment(appDelegate.updater)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    let updater = Updater()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }
}

private struct StatusIcon: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.status {
        case .listening:
            Image(systemName: "hand.raised")
                .accessibilityLabel("Stop Typing App")
        case .snoozed:
            Image(nsImage: Self.snoozedIcon)
                .accessibilityLabel("Stop Typing App, snoozed")
        case .off:
            Image(systemName: "hand.raised.slash")
                .accessibilityLabel("Stop Typing App, paused")
        case .needsPermission, .unavailable:
            Image(systemName: "exclamationmark.triangle")
                .accessibilityLabel("Stop Typing App needs attention")
        }
    }

    /// The raised hand with a small crescent moon at its top right, cut out so the two don't touch.
    /// Menu bar labels can only show a single image, so the two symbols are composed into one template.
    private static let snoozedIcon: NSImage = {
        let hand = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))!
        let moon = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 7, weight: .semibold))!
        let size = NSSize(width: hand.size.width + moon.size.width * 0.45, height: hand.size.height + moon.size.height * 0.3)
        let image = NSImage(size: size, flipped: false) { _ in
            hand.draw(in: NSRect(origin: .zero, size: hand.size))
            let badge = NSRect(
                x: size.width - moon.size.width,
                y: size.height - moon.size.height,
                width: moon.size.width,
                height: moon.size.height
            )
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: badge.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            moon.draw(in: badge)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
