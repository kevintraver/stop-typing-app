import AppKit
import Observation
import StopTypingCore

@MainActor
@Observable
final class AppModel {
    enum Status: Equatable {
        case off
        case needsPermission
        /// Permission is granted but the system refused the tap even so. A relaunch fixes it.
        case unavailable
        case snoozed(until: Date)
        case listening
    }

    enum TapState {
        case stopped, needsPermission, unavailable, listening
    }

    let preferences: Preferences
    let updater = Updater()
    private(set) var tapState = TapState.stopped
    /// The app most recently brought to the front, other than this one. Offered as a quick exclusion.
    private(set) var recentApp: AppInfo?
    private(set) var notificationsDenied = false

    @ObservationIgnored private var detector = TypingDetector()
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private let tapGate = TapGate()
    @ObservationIgnored private var inputGeneration: UInt64?
    @ObservationIgnored private var permissionPolling: Task<Void, Never>?
    @ObservationIgnored private var snoozeExpiry: Task<Void, Never>?
    @ObservationIgnored private let hud: NudgeHUD
    @ObservationIgnored private let stopWindow = StopWindow()
    @ObservationIgnored private let focus = FocusStatus()
    @ObservationIgnored private let notifier = NotificationNudger()
    @ObservationIgnored private let onboarding = OnboardingWindow()

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

    /// The main switch as people see it: off while paused or snoozed. Flipping it always ends a snooze.
    var isWatching: Bool {
        get { preferences.isEnabled && snoozeDescription == nil }
        set {
            resume()
            isEnabled = newValue
        }
    }

    /// "Snoozed until 3:45 PM" or "Snoozed until tomorrow"; nil when not snoozed.
    var snoozeDescription: String? {
        guard let until = preferences.snoozedUntil, until > .now else { return nil }
        return Calendar.current.isDateInToday(until)
            ? String(localized: "Snoozed until \(until.formatted(date: .omitted, time: .shortened))")
            : String(localized: "Snoozed until tomorrow")
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

    /// Kept current by `refreshPermission()`, so views watching it see a grant made in System Settings.
    private(set) var hasInputMonitoringPermission = KeyboardTap.hasPermission

    var isQuietDuringFocus: Bool {
        get { preferences.isQuietDuringFocus }
        set {
            preferences.isQuietDuringFocus = newValue
            if newValue { focus.start() } else { focus.stop() }
        }
    }

    func start() {
        // Only today's counts are kept: a previous day's are cleared rather than left until the next prose.
        preferences.stats = preferences.stats.on(.now)
        if let until = preferences.snoozedUntil { scheduleSnoozeExpiry(at: until) }
        trackFrontmostApp()
        refreshPermissionOnActivation()
        if preferences.isQuietDuringFocus { focus.start() }
        updateListening()
        // The setup window asks for Input Monitoring itself, so the system prompt never appears unexplained.
        if !preferences.hasCompletedOnboarding || (preferences.isEnabled && !KeyboardTap.hasPermission) {
            showOnboarding()
        }
    }

    // MARK: Setup

    func showOnboarding() {
        onboarding.show(model: self)
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        onboarding.close()
    }

    /// Closes the setup window without finishing it, so it opens again at the next launch.
    func closeOnboarding() {
        onboarding.close()
    }

    /// The system prompt appears only the first time; after that the switch is only in System Settings.
    func requestInputMonitoring() {
        if preferences.hasRequestedInputMonitoring {
            NSWorkspace.shared.open(KeyboardTap.privacySettingsURL)
        } else {
            preferences.hasRequestedInputMonitoring = true
            KeyboardTap.requestPermission()
        }
    }

    // MARK: Snooze

    func snooze(_ option: SnoozeOption) {
        let until = option.end(from: .now)
        preferences.snoozedUntil = until
        detector.reset()
        scheduleSnoozeExpiry(at: until)
        updateTapGate()
    }

    func resume() {
        snoozeExpiry?.cancel()
        preferences.snoozedUntil = nil
        updateTapGate()
    }

    private func scheduleSnoozeExpiry(at until: Date) {
        snoozeExpiry?.cancel()
        snoozeExpiry = Task {
            try? await Task.sleep(for: .seconds(max(0, until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            preferences.snoozedUntil = nil
            updateTapGate()
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
        updateTapGate()
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
        updateTapGate()
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
        case .stop:
            stopWindow.show(ignoring: nil) { [weak self] _ in self?.updateTapGate() }
            updateTapGate()
        case .gentle, .firm: hud.show(nudge)
        }
    }

    private func present(_ nudge: Nudge) {
        switch nudge {
        case .gentle, .firm:
            showNudge(nudge)
        case .stop:
            if preferences.skipsStopInFullScreen && FrontmostWindow.isFullScreen {
                showNudge(.firm)
            } else {
                // The stop window already demands attention, so it isn't also sent to Notification Center.
                showStopWindow()
            }
        }
    }

    private func showNudge(_ nudge: Nudge) {
        if preferences.showsOnScreenNudge { hud.show(nudge) }
        if preferences.sendsNotifications { notifier.post(nudge) }
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
            updateTapGate()
        }
        updateTapGate()
    }

    /// Closes the tap's gate whenever keys shouldn't count, so they aren't even read: while snoozed,
    /// while an ignored app is in front, and while the stop window (which takes the keys) is up.
    private func updateTapGate() {
        let isSnoozed = preferences.snoozedUntil.map { $0 > .now } ?? false
        let frontmost = NSWorkspace.shared.frontmostApplication
        let allowed = preferences.isEnabled && !isSnoozed && !stopWindow.isShowing
            && frontmost?.bundleIdentifier.map { !isExcluded($0) } == true
        tapGate.allow(processID: allowed ? frontmost?.processIdentifier : nil)
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
            updateTapGate()
            let keystrokes = try KeyboardTap.keystrokes(gate: tapGate)
            tapState = .listening
            listening = Task {
                for await keystroke in keystrokes { handle(keystroke) }
            }
        } catch {
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
        tapGate.allow(processID: nil)
        inputGeneration = nil
        listening?.cancel()
        listening = nil
        permissionPolling?.cancel()
        permissionPolling = nil
        detector.reset()
        tapState = .stopped
    }

    /// Re-reads Input Monitoring and, once it's granted, starts the tap in this process.
    ///
    /// A listen-only tap created before the grant never receives keys, and macOS doesn't upgrade it,
    /// but one created after the grant works without a relaunch. `KeyboardTap` refuses to create a tap
    /// until the grant, so there's never a stale one to replace. If the system still refuses the tap,
    /// the status becomes `.unavailable` and the menu bar panel offers a relaunch.
    func refreshPermission() {
        let granted = KeyboardTap.hasPermission
        if granted != hasInputMonitoringPermission { hasInputMonitoringPermission = granted }
        guard granted, tapState == .needsPermission else { return }
        permissionPolling?.cancel()
        permissionPolling = nil
        updateListening()
    }

    /// Opening the menu bar panel or Settings activates the app, so they show a grant made while paused,
    /// when nothing is polling.
    private func refreshPermissionOnActivation() {
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermission() }
        }
    }

    /// Input Monitoring is granted in System Settings, which doesn't tell the app, so check until it's on.
    private func pollForPermission() {
        guard permissionPolling == nil else { return }
        permissionPolling = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                refreshPermission()
            }
        }
    }

    private func handle(_ keystroke: TimedKeystroke) {
        // While the stop window is up, keys go to it rather than to anything worth counting.
        updateTapGate()
        guard status == .listening, !stopWindow.isShowing,
              tapGate.accepts(generation: keystroke.generation)
        else { return }
        if inputGeneration != keystroke.generation {
            detector.reset()
            inputGeneration = keystroke.generation
        }

        detector.configuration = preferences.detection
        detector.usesStopWindow = preferences.stopsWhenIgnored
        detector.isQuiet = preferences.isQuietDuringFocus && focus.isFocused
        let outcome = detector.register(keystroke.keystroke, at: keystroke.time)
        if outcome.newProseCharacters > 0 {
            preferences.stats.recordProse(outcome.newProseCharacters, at: .now)
        }
        if let nudge = outcome.nudge {
            preferences.stats.recordNudge(at: .now)
            present(nudge)
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
