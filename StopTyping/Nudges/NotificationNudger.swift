import Foundation
import StopTypingCore
import UserNotifications

/// Delivers nudges as system notifications, an opt-in alternative to the on-screen nudge.
@MainActor
final class NotificationNudger: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    /// Asks for permission. Returns false if the user declines or turned notifications off in System Settings.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func post(_ nudge: Nudge) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: nudge.title)
        content.body = String(localized: nudge.message)
        content.interruptionLevel = .active
        // Reusing one identifier replaces the previous nudge instead of piling them up in Notification Center.
        center.add(UNNotificationRequest(identifier: "nudge", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
