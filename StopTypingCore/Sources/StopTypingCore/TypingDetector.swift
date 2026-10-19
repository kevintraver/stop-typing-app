import Foundation

public struct DetectorConfiguration: Equatable, Sendable, Codable {
    /// Characters of prose in one burst before the first nudge.
    public var sentenceLength = 25
    /// Characters in one burst that count as a paragraph, which can escalate to a firm nudge.
    public var paragraphLength = 80
    /// Seconds of continuous typing that also escalate.
    public var sustainedTyping: TimeInterval = 60
    /// A pause this long ends the burst.
    public var burstGap: TimeInterval = 5
    /// Bursts shorter than `shortBurstLength` end after this shorter pause.
    public var shortBurstGap: TimeInterval = 2.5
    public var shortBurstLength = 10
    /// After a nudge, a new burst has to wait this long for its own gentle nudge.
    public var cooldown: TimeInterval = 120
    /// Minimum time between firm nudges.
    public var escalationInterval: TimeInterval = 30
    /// With the stop window on: how long after a gentle nudge continued typing brings the stop window.
    public var stopDelay: TimeInterval = 30

    // A burst reads like prose when it has word breaks, a variety of letters, and is mostly letters.
    // This keeps Vim motions (`jjjj`), held keys, URLs and symbol-heavy code from counting.
    public var minimumWordBreaks = 2
    /// How many of `KeyCounts`' 16 letter buckets a burst has to touch. The name predates the
    /// buckets and is kept so saved settings still decode.
    public var minimumDistinctLetters = 5
    public var minimumLetterRatio = 0.6

    public init() {}
}

/// Decides when continuous typing looks like prose that would be faster to dictate.
///
/// Feed it every keystroke with a monotonic timestamp in seconds; it returns when to nudge.
public struct TypingDetector: Sendable {
    public struct Outcome: Equatable, Sendable {
        public var nudge: Nudge?
        /// Characters newly counted as prose by this keystroke, for daily stats.
        public var newProseCharacters = 0

        public init(nudge: Nudge? = nil, newProseCharacters: Int = 0) {
            self.nudge = nudge
            self.newProseCharacters = newProseCharacters
        }
    }

    public var configuration: DetectorConfiguration
    /// Escalate gentle → stop instead of gentle → firm, firm, …
    public var usesStopWindow = false
    /// Keep tracking prose, but never nudge or advance the escalation (e.g. during a Focus).
    public var isQuiet = false
    private var burst: Burst?
    private var lastNudge: (kind: Nudge, time: TimeInterval)?

    public init(configuration: DetectorConfiguration = DetectorConfiguration()) {
        self.configuration = configuration
    }

    public mutating func register(_ keystroke: Keystroke, at time: TimeInterval) -> Outcome {
        switch keystroke {
        case .shortcut:
            return Outcome()
        case .escape:
            burst = nil
            return Outcome()
        case .text(let counts):
            return registerText(counts, at: time)
        }
    }

    /// Forgets the current burst, e.g. after a snooze or when monitoring stops.
    public mutating func reset() {
        burst = nil
    }

    /// The user dismissed the stop window: stay quiet for a full cooldown from now, then start over.
    public mutating func acknowledgeStop(at time: TimeInterval) {
        burst = nil
        lastNudge = (.stop, time)
    }

    private mutating func registerText(_ counts: KeyCounts, at time: TimeInterval) -> Outcome {
        if let burst, burst.hasEnded(at: time, configuration) {
            self.burst = nil
        }

        var burst = self.burst ?? Burst(start: time)
        let added = burst.append(counts, at: time)
        guard added > 0 else { return Outcome() }

        var outcome = Outcome()
        if burst.isProse(configuration) {
            outcome.newProseCharacters = burst.countedAsProse ? added : burst.length
            burst.countedAsProse = true
            if !isQuiet { outcome.nudge = nudge(for: burst, at: time) }
        }
        if let nudge = outcome.nudge {
            burst.wasNudged = true
            lastNudge = (nudge, time)
        }
        self.burst = burst
        return outcome
    }

    private func nudge(for burst: Burst, at time: TimeInterval) -> Nudge? {
        guard let lastNudge else { return .gentle }
        let sinceLastNudge = time - lastNudge.time
        let isLong = burst.isLong(at: time, configuration)

        // After the stop window, stay quiet for a full cooldown, then start over with a gentle nudge.
        if lastNudge.kind == .stop {
            return sinceLastNudge >= configuration.cooldown ? .gentle : nil
        }
        if usesStopWindow && lastNudge.kind == .gentle && isLong && sinceLastNudge >= configuration.stopDelay {
            return .stop
        }
        if !burst.wasNudged && sinceLastNudge >= configuration.cooldown {
            return .gentle
        }
        if !usesStopWindow && isLong && sinceLastNudge >= configuration.escalationInterval {
            return .firm
        }
        return nil
    }
}

private struct Burst: Sendable {
    let start: TimeInterval
    var lastKey: TimeInterval
    var length = 0
    var letters = 0
    var wordBreaks = 0
    var letterBuckets: UInt16 = 0
    var countedAsProse = false
    var wasNudged = false

    init(start: TimeInterval) {
        self.start = start
        self.lastKey = start
    }

    /// Adds a key press's counts and returns how many characters it added.
    mutating func append(_ counts: KeyCounts, at time: TimeInterval) -> Int {
        guard counts.total > 0 else { return 0 }
        length += counts.total
        letters += counts.letters
        wordBreaks += counts.wordBreaks
        letterBuckets |= counts.letterBuckets
        lastKey = time
        return counts.total
    }

    func hasEnded(at time: TimeInterval, _ configuration: DetectorConfiguration) -> Bool {
        let idle = time - lastKey
        return idle >= configuration.burstGap
            || (idle >= configuration.shortBurstGap && length < configuration.shortBurstLength)
    }

    func isProse(_ configuration: DetectorConfiguration) -> Bool {
        length >= configuration.sentenceLength
            && wordBreaks >= configuration.minimumWordBreaks
            && letterBuckets.nonzeroBitCount >= configuration.minimumDistinctLetters
            && Double(letters) / Double(length) >= configuration.minimumLetterRatio
    }

    func isLong(at time: TimeInterval, _ configuration: DetectorConfiguration) -> Bool {
        length >= configuration.paragraphLength || time - start >= configuration.sustainedTyping
    }
}
