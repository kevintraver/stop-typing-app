import AppKit
import StopTypingCore
import Testing

@Suite("Persisted daily retention")
@MainActor
struct StatsRetentionTests {
    @Test(arguments: [
        Notification.Name.NSCalendarDayChanged,
        .NSSystemClockDidChange,
        .NSSystemTimeZoneDidChange,
        NSApplication.didBecomeActiveNotification,
        NSWorkspace.didWakeNotification,
    ])
    func lifecycleEventsEraseYesterdaysPersistedCounts(event: Notification.Name) throws {
        let domain = "StopTypingPrivacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        var date = Date.now
        preferences.stats.recordProse(120, at: date)
        preferences.stats.recordNudge(at: date)
        let center = NotificationCenter()
        let workspaceCenter = NotificationCenter()
        let rollover = StatsRollover(
            preferences: preferences,
            center: center,
            workspaceCenter: workspaceCenter,
            now: { date }
        )
        rollover.start()
        defer { rollover.stop() }

        date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        let source = event == NSWorkspace.didWakeNotification ? workspaceCenter : center
        source.post(name: event, object: nil)

        // Reopen preferences to check storage, not just the number shown by a view.
        let restored = Preferences(defaults: defaults)
        #expect(restored.stats.proseCharacters == 0)
        #expect(restored.stats.nudges == 0)
        #expect(Calendar.current.isDate(restored.stats.day, inSameDayAs: date))
    }

    @Test func refreshingWithinTheDayPreservesCounts() throws {
        let domain = "StopTypingPrivacyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preferences = Preferences(defaults: defaults)
        let date = Date.now
        preferences.stats.recordProse(120, at: date)
        preferences.refreshStats(at: date)
        #expect(Preferences(defaults: defaults).stats.proseCharacters == 120)
    }
}
