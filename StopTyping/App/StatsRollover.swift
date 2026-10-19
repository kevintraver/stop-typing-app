import AppKit

/// Clears expired persisted counts even when no new typing arrives. Wake and clock changes
/// reschedule the calendar deadline instead of assuming a day is always 24 hours.
@MainActor
final class StatsRollover {
    private let preferences: Preferences
    private let center: NotificationCenter
    private let workspaceCenter: NotificationCenter
    private let now: () -> Date
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(
        preferences: Preferences,
        center: NotificationCenter = .default,
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        now: @escaping () -> Date = { .now }
    ) {
        self.preferences = preferences
        self.center = center
        self.workspaceCenter = workspaceCenter
        self.now = now
    }

    func start() {
        stop()
        for name in [
            Notification.Name.NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            NSApplication.didBecomeActiveNotification,
        ] {
            observe(name, on: center)
        }
        observe(NSWorkspace.didWakeNotification, on: workspaceCenter)
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append((center, observer))
    }

    private func refresh() {
        let date = now()
        preferences.refreshStats(at: date)
        timer?.invalidate()
        let midnight = Calendar.current.dateInterval(of: .day, for: date)!.end
        let timer = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
