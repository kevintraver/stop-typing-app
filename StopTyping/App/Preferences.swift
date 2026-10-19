import Foundation
import Observation
import StopTypingCore

/// User settings, saved to `UserDefaults` as they change.
@MainActor
@Observable
final class Preferences {
    var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Key.isEnabled) }
    }
    var showsOnScreenNudge: Bool {
        didSet { defaults.set(showsOnScreenNudge, forKey: Key.showsOnScreenNudge) }
    }
    var sendsNotifications: Bool {
        didSet { defaults.set(sendsNotifications, forKey: Key.sendsNotifications) }
    }
    /// Opt-in: typing through a gentle nudge opens a window that has to be clicked away.
    var stopsWhenIgnored: Bool {
        didSet { defaults.set(stopsWhenIgnored, forKey: Key.stopsWhenIgnored) }
    }
    /// Show the on-screen nudge instead of the stop window while a full-screen app is in front.
    var skipsStopInFullScreen: Bool {
        didSet { defaults.set(skipsStopInFullScreen, forKey: Key.skipsStopInFullScreen) }
    }
    /// No nudges of any kind while a Focus such as Do Not Disturb is on.
    var isQuietDuringFocus: Bool {
        didSet { defaults.set(isQuietDuringFocus, forKey: Key.isQuietDuringFocus) }
    }
    var detection: DetectorConfiguration {
        didSet { defaults.set(try? JSONEncoder().encode(detection), forKey: Key.detection) }
    }
    /// Bundle identifiers of apps where typing is never counted.
    var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: Key.excludedApps) }
    }
    /// Where the user dragged the on-screen nudge: the horizontal offset of its center from the screen's
    /// center, and the distance of its top from the top of the screen's usable area. Nil means the default.
    var nudgeOffset: CGSize? {
        didSet {
            defaults.set(nudgeOffset.map { [$0.width, $0.height] }, forKey: Key.nudgeOffset)
        }
    }
    var snoozedUntil: Date? {
        didSet { defaults.set(snoozedUntil, forKey: Key.snoozedUntil) }
    }
    var stats: DailyStats {
        didSet { defaults.set(try? JSONEncoder().encode(stats), forKey: Key.stats) }
    }
    /// Set by Done in the setup window. Until then the window opens at every launch.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }
    /// The system shows its Input Monitoring prompt only once, so later requests open System Settings instead.
    var hasRequestedInputMonitoring: Bool {
        didSet { defaults.set(hasRequestedInputMonitoring, forKey: Key.hasRequestedInputMonitoring) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    func refreshStats(at date: Date = .now, calendar: Calendar = .current) {
        let today = stats.on(date, calendar: calendar)
        if stats != today { stats = today }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.showsOnScreenNudge: true,
            Key.sendsNotifications: false,
            Key.stopsWhenIgnored: false,
            Key.skipsStopInFullScreen: true,
            Key.isQuietDuringFocus: true,
            Key.hasCompletedOnboarding: false,
            Key.hasRequestedInputMonitoring: false,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        showsOnScreenNudge = defaults.bool(forKey: Key.showsOnScreenNudge)
        sendsNotifications = defaults.bool(forKey: Key.sendsNotifications)
        stopsWhenIgnored = defaults.bool(forKey: Key.stopsWhenIgnored)
        skipsStopInFullScreen = defaults.bool(forKey: Key.skipsStopInFullScreen)
        isQuietDuringFocus = defaults.bool(forKey: Key.isQuietDuringFocus)
        detection = defaults.decoded(DetectorConfiguration.self, forKey: Key.detection) ?? DetectorConfiguration()
        excludedApps = defaults.stringArray(forKey: Key.excludedApps) ?? []
        nudgeOffset = (defaults.array(forKey: Key.nudgeOffset) as? [Double]).flatMap { values in
            values.count == 2 ? CGSize(width: values[0], height: values[1]) : nil
        }
        snoozedUntil = defaults.object(forKey: Key.snoozedUntil) as? Date
        stats = defaults.decoded(DailyStats.self, forKey: Key.stats) ?? DailyStats(day: .now)
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasRequestedInputMonitoring = defaults.bool(forKey: Key.hasRequestedInputMonitoring)
    }

    private enum Key {
        static let isEnabled = "isEnabled"
        static let showsOnScreenNudge = "showsOnScreenNudge"
        static let sendsNotifications = "sendsNotifications"
        static let stopsWhenIgnored = "stopsWhenIgnored"
        static let skipsStopInFullScreen = "skipsStopInFullScreen"
        static let isQuietDuringFocus = "isQuietDuringFocus"
        static let detection = "detection"
        static let excludedApps = "excludedApps"
        static let nudgeOffset = "nudgeOffset"
        static let snoozedUntil = "snoozedUntil"
        static let stats = "stats"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasRequestedInputMonitoring = "hasRequestedInputMonitoring"
    }
}

private extension UserDefaults {
    func decoded<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
