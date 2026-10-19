import AppKit
import Observation
import os
import StopTypingCore

/// Records nudge decisions and timings only, never typed characters.
/// Read with `log show --last 10m --predicate 'subsystem == "com.kevintraver.StopTyping"'`.
private let log = Logger(subsystem: "com.kevintraver.StopTyping", category: "nudges")

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case off
        case needsPermission
        /// Permission is granted but the system refused the tap. A relaunch fixes it.
        case unavailable
        case snoozed(until: Date)
        case listening
    }

    enum TapState {
        case stopped, needsPermission, unavailable, listening
    }

    let preferences: Preferences
    private(set) var tapState = TapState.stopped
    /// The app most recently brought to the front, other than this one. Offered as a quick exclusion.
    private(set) var recentApp: AppInfo?
    private(set) var notificationsDenied = false

    @ObservationIgnored private var detector = TypingDetector()
    @ObservationIgnored private var lastNudge: Date?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var permissionPolling: Task<Void, Never>?
    @ObservationIgnored private var snoozeExpiry: Task<Void, Never>?
    @ObservationIgnored private let hud: NudgeHUD
    @ObservationIgnored private let stopWindow = StopWindow()
    @ObservationIgnored private let focus = FocusStatus()
    @ObservationIgnored private let notifier = NotificationNudger()

    init() {
        let preferences = Preferences()
        self.preferences = preferences
        hud = NudgeHUD(preferences: preferences)
    }

    var status: Status {
        guard preferences.isEnabled else { return .off }
        switch tapState {
        case .needsPermission: return .needsPermission
        case .unavailable: return .unavailable
        case .stopped, .listening: break
        }
        if let until = preferences.snoozedUntil, until > .now { return .snoozed(until: until) }
        return .listening
    }

    var isEnabled: Bool {
        get { preferences.isEnabled }
        set {
            preferences.isEnabled = newValue
            updateListening()
        }
    }

    var sendsNotifications: Bool {
        get { preferences.sendsNotifications }
        set {
            preferences.sendsNotifications = newValue
            notificationsDenied = false
            guard newValue else { return }
            Task {
                let granted = await notifier.requestAuthorization()
                notificationsDenied = !granted
                if !granted { preferences.sendsNotifications = false }
            }
        }
    }

    var hasInputMonitoringPermission: Bool { KeyboardTap.hasPermission }

    var isQuietDuringFocus: Bool {
        get { preferences.isQuietDuringFocus }
        set {
            preferences.isQuietDuringFocus = newValue
            if newValue { focus.start() } else { focus.stop() }
        }
    }

    func start() {
        if let until = preferences.snoozedUntil { scheduleSnoozeExpiry(at: until) }
        trackFrontmostApp()
        if preferences.isQuietDuringFocus { focus.start() }
        if preferences.isEnabled && !KeyboardTap.hasPermission {
            KeyboardTap.requestPermission()
        }
        updateListening()
    }

    // MARK: Snooze

    func snooze(_ option: SnoozeOption) {
        let until = option.end(from: .now)
        preferences.snoozedUntil = until
        detector.reset()
        scheduleSnoozeExpiry(at: until)
    }

    func resume() {
        snoozeExpiry?.cancel()
        preferences.snoozedUntil = nil
    }

    private func scheduleSnoozeExpiry(at until: Date) {
        snoozeExpiry?.cancel()
        snoozeExpiry = Task {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            preferences.snoozedUntil = nil
        }
    }

    // MARK: Excluded apps

    func isExcluded(_ bundleID: String) -> Bool {
        preferences.excludedApps.contains(bundleID)
    }

    func setExcluded(_ excluded: Bool, bundleID: String) {
        if excluded {
            guard !isExcluded(bundleID) else { return }
            preferences.excludedApps.append(bundleID)
        } else {
            preferences.excludedApps.removeAll { $0 == bundleID }
        }
    }

    private func trackFrontmostApp() {
        noteActivated(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated { self?.noteActivated(bundleID: bundleID) }
        }
    }

    private func noteActivated(bundleID: String?) {
        guard let bundleID, bundleID != Bundle.main.bundleIdentifier else { return }
        recentApp = AppInfo(bundleID: bundleID)
    }

    // MARK: Nudges

    /// Moves the nudge back to its default spot and shows it there, so the reset is visible right away.
    func resetNudgePosition() {
        preferences.nudgeOffset = nil
        hud.show(.gentle)
    }

    func preview(_ nudge: Nudge) {
        switch nudge {
        case .stop: stopWindow.show(ignoring: nil) { _ in }
        case .gentle, .firm: hud.show(nudge)
        }
    }

    private func present(_ nudge: Nudge) {
        switch nudge {
        case .gentle:
            if preferences.showsOnScreenNudge { hud.show(nudge) }
            // Notification Center gets one alert per cycle, never the escalations.
            if preferences.sendsNotifications { notifier.post(nudge) }
        case .firm:
            if preferences.showsOnScreenNudge { hud.show(nudge) }
        case .stop:
            if preferences.skipsStopInFullScreen && FrontmostWindow.isFullScreen {
                log.notice("Full screen: showing the on-screen nudge instead of the stop window")
                if preferences.showsOnScreenNudge { hud.show(.firm) }
            } else {
                showStopWindow()
            }
        }
    }

    private func showStopWindow() {
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            .flatMap { $0 == Bundle.main.bundleIdentifier ? nil : AppInfo(bundleID: $0) }
        stopWindow.show(ignoring: app) { [weak self] action in
            guard let self else { return }
            switch action {
            case .acknowledge:
                detector.acknowledgeStop(at: ProcessInfo.processInfo.systemUptime)
            case .snooze:
                snooze(.fifteenMinutes)
            case .ignore:
                if let app { setExcluded(true, bundleID: app.bundleID) }
                detector.acknowledgeStop(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    // MARK: Listening

    func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func updateListening() {
        guard preferences.isEnabled else {
            stopListening()
            return
        }
        guard listening == nil else { return }

        do throws(KeyboardTapError) {
            let keystrokes = try KeyboardTap.keystrokes()
            log.notice("Listening for typing")
            tapState = .listening
            listening = Task {
                for await keystroke in keystrokes { handle(keystroke) }
            }
        } catch {
            log.notice("Couldn't start listening: \(String(describing: error), privacy: .public)")
            switch error {
            case .permissionDenied:
                tapState = .needsPermission
                pollForPermission()
            case .unavailable:
                tapState = .unavailable
            }
        }
    }

    private func stopListening() {
        listening?.cancel()
        listening = nil
        permissionPolling?.cancel()
        permissionPolling = nil
        detector.reset()
        tapState = .stopped
    }

    /// Input Monitoring is granted in System Settings, which doesn't tell the app, and the grant
    /// only takes effect in a new process. Check until it's on, then relaunch.
    private func pollForPermission() {
        guard permissionPolling == nil else { return }
        permissionPolling = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if KeyboardTap.hasPermission {
                    relaunch()
                    return
                }
            }
        }
    }

    private func handle(_ keystroke: TimedKeystroke) {
        // While the stop window is up, keys go to it rather than to anything worth counting.
        guard status == .listening, !stopWindow.isShowing else { return }
        if let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, isExcluded(frontmost) {
            log.debug("Ignoring a key in excluded app \(frontmost, privacy: .public)")
            return
        }

        detector.configuration = preferences.detection
        detector.usesStopWindow = preferences.stopsWhenIgnored
        detector.isQuiet = preferences.isQuietDuringFocus && focus.isFocused
        let outcome = detector.register(keystroke.keystroke, at: keystroke.time)
        if outcome.newProseCharacters > 0 {
            preferences.stats.recordProse(outcome.newProseCharacters, at: .now)
        }
        if let nudge = outcome.nudge {
            log.notice("Nudge: \(String(describing: nudge), privacy: .public)")
            lastNudge = .now
            preferences.stats.recordNudge(at: .now)
            present(nudge)
        } else if outcome.newProseCharacters > 1, let lastNudge {
            // More than one new character means this keystroke is the one that made the burst read like prose.
            let since = Int(Date.now.timeIntervalSince(lastNudge))
            log.notice("Prose burst, no nudge: \(since) s since the last nudge, cooldown \(Int(self.preferences.detection.cooldown)) s")
        }
    }
}

enum SnoozeOption: CaseIterable, Identifiable {
    case fifteenMinutes, oneHour, untilTomorrow

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .fifteenMinutes: "15 Minutes"
        case .oneHour: "1 Hour"
        case .untilTomorrow: "Until Tomorrow"
        }
    }

    func end(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .fifteenMinutes: now.addingTimeInterval(15 * 60)
        case .oneHour: now.addingTimeInterval(60 * 60)
        case .untilTomorrow: calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        }
    }
}

struct AppInfo: Identifiable, Hashable {
    let bundleID: String
    let url: URL?

    var id: String { bundleID }

    init(bundleID: String) {
        self.bundleID = bundleID
        self.url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    var name: String {
        url?.deletingPathExtension().lastPathComponent ?? bundleID
    }

    var icon: NSImage {
        url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
    }
}
