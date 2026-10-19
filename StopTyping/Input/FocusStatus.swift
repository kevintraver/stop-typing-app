import Intents
import os

private let log = Logger(subsystem: "com.kevintraver.StopTyping", category: "focus")

/// Whether a Focus such as Do Not Disturb is on. macOS asks the user once for access.
///
/// The system only reports on/off: not which Focus, and "off" if the Focus allows this app.
/// There's no change notification, so the state is re-read every few seconds.
@MainActor
final class FocusStatus {
    private(set) var isFocused = false
    private var polling: Task<Void, Never>?

    func start() {
        guard polling == nil else { return }
        polling = Task {
            let status = await INFocusStatusCenter.default.requestAuthorization()
            log.notice("Focus status authorization: \(status.rawValue, privacy: .public)")
            while !Task.isCancelled {
                let focused = INFocusStatusCenter.default.focusStatus.isFocused ?? false
                if focused != isFocused {
                    log.notice("Focus is \(focused ? "on" : "off", privacy: .public)")
                    isFocused = focused
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
        isFocused = false
    }
}
