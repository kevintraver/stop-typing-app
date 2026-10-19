import Foundation

/// Counts for a single calendar day. Only counts are kept, never what was typed.
public struct DailyStats: Equatable, Sendable, Codable {
    public private(set) var day: Date
    public private(set) var proseCharacters = 0
    public private(set) var nudges = 0

    public init(day: Date, calendar: Calendar = .current) {
        self.day = calendar.startOfDay(for: day)
    }

    /// Rough word count, assuming about six characters per word including the space.
    public var estimatedWords: Int { proseCharacters / 6 }

    /// These stats if they belong to `date`'s day, otherwise an empty day.
    public func on(_ date: Date, calendar: Calendar = .current) -> DailyStats {
        calendar.isDate(day, inSameDayAs: date) ? self : DailyStats(day: date, calendar: calendar)
    }

    public mutating func recordProse(_ characters: Int, at date: Date, calendar: Calendar = .current) {
        self = on(date, calendar: calendar)
        proseCharacters += characters
    }

    public mutating func recordNudge(at date: Date, calendar: Calendar = .current) {
        self = on(date, calendar: calendar)
        nudges += 1
    }
}
