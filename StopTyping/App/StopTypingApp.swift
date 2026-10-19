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
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

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
            Image(systemName: "moon.zzz")
                .accessibilityLabel("Stop Typing App, snoozed")
        case .off:
            Image(systemName: "hand.raised.slash")
                .accessibilityLabel("Stop Typing App, paused")
        case .needsPermission, .unavailable:
            Image(systemName: "exclamationmark.triangle")
                .accessibilityLabel("Stop Typing App needs attention")
        }
    }
}
