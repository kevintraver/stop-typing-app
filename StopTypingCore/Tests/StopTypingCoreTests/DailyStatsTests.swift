import Foundation
import Testing
@testable import StopTypingCore

@Suite("DailyStats")
struct DailyStatsTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let morning = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func accumulatesWithinADay() {
        var stats = DailyStats(day: morning, calendar: calendar)
        stats.recordProse(30, at: morning, calendar: calendar)
        stats.recordProse(12, at: morning.addingTimeInterval(3600), calendar: calendar)
        stats.recordNudge(at: morning.addingTimeInterval(3600), calendar: calendar)

        #expect(stats.proseCharacters == 42)
        #expect(stats.estimatedWords == 7)
        #expect(stats.nudges == 1)
    }

    @Test func startsOverOnANewDay() {
        var stats = DailyStats(day: morning, calendar: calendar)
        stats.recordProse(30, at: morning, calendar: calendar)
        stats.recordNudge(at: morning, calendar: calendar)

        let tomorrow = morning.addingTimeInterval(86_400)
        #expect(stats.on(tomorrow, calendar: calendar).nudges == 0)

        stats.recordNudge(at: tomorrow, calendar: calendar)
        #expect(stats.nudges == 1)
        #expect(stats.proseCharacters == 0)
    }
}
