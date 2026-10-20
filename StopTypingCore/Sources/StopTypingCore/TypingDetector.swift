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

    // A burst reads like prose when it has word breaks in proportion to its length and is mostly
    // letters. That keeps Vim motions (`jjkk`, even with the odd `:w⏎` or space), URLs and symbol-heavy
    // code from counting; held keys never arrive (auto-repeat is dropped at the tap). Which letters were
    // typed is never known, so there's deliberately no variety check.
    public var minimumWordBreaks = 2
    /// At least one word break per this many characters. Prose has one every 5 to 8, so 12 leaves room
    /// for long words while a burst of navigation keys with a stray break or two never qualifies.
    public var charactersPerWordBreak = 12
    public var minimumLetterRatio = 0.6

    public init() {}

    /// Settings saved by an older version lack the keys added since, and must keep their other values.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DetectorConfiguration()
        sentenceLength = try container.decodeIfPresent(Int.self, forKey: .sentenceLength) ?? defaults.sentenceLength
        paragraphLength = try container.decodeIfPresent(Int.self, forKey: .paragraphLength) ?? defaults.paragraphLength
        sustainedTyping = try container.decodeIfPresent(TimeInterval.self, forKey: .sustainedTyping) ?? defaults.sustainedTyping
        burstGap = try container.decodeIfPresent(TimeInterval.self, forKey: .burstGap) ?? defaults.burstGap
        shortBurstGap = try container.decodeIfPresent(TimeInterval.self, forKey: .shortBurstGap) ?? defaults.shortBurstGap
        shortBurstLength = try container.decodeIfPresent(Int.self, forKey: .shortBurstLength) ?? defaults.shortBurstLength
        cooldown = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldown) ?? defaults.cooldown
        escalationInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .escalationInterval) ?? defaults.escalationInterval
        stopDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .stopDelay) ?? defaults.stopDelay
        minimumWordBreaks = try container.decodeIfPresent(Int.self, forKey: .minimumWordBreaks) ?? defaults.minimumWordBreaks
        charactersPerWordBreak = try container.decodeIfPresent(Int.self, forKey: .charactersPerWordBreak) ?? defaults.charactersPerWordBreak
        minimumLetterRatio = try container.decodeIfPresent(Double.self, forKey: .minimumLetterRatio) ?? defaults.minimumLetterRatio
    }

    /// Whether a burst with these counts reads like prose. Letters divided by length is the letter ratio.
    public func readsAsProse(length: Int, letters: Int, wordBreaks: Int) -> Bool {
        length >= sentenceLength
            && wordBreaks >= minimumWordBreaks
            && wordBreaks * charactersPerWordBreak >= length
            && Double(letters) / Double(length) >= minimumLetterRatio
    }
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

    /// The counts of the burst being tracked, so a settings screen can show what the detector sees.
    public struct BurstSummary: Equatable, Sendable {
        public var length: Int
        public var letters: Int
        public var wordBreaks: Int
        /// When the burst started and when its last key arrived, in the detector's clock.
        public var start: TimeInterval
        public var lastKey: TimeInterval
        /// A pause this long after `lastKey` ends the burst.
        public var endsAfterPause: TimeInterval
        public var readsAsProse: Bool
        public var wasNudged: Bool
    }

    public var configuration: DetectorConfiguration
    /// Escalate gentle → stop instead of gentle → firm, firm, …
    public var usesStopWindow = false
    /// Keep tracking prose, but never nudge or advance the escalation (e.g. during a Focus).
    public var isQuiet = false
    /// The last nudge and when it fired; the cooldown counts from here.
    public private(set) var lastNudge: (kind: Nudge, time: TimeInterval)?
    private var burst: Burst?

    /// The burst as of its last key. Whether a pause has ended it since is up to the caller's clock.
    public var currentBurst: BurstSummary? {
        burst.map { burst in
            BurstSummary(
                length: burst.length,
                letters: burst.letters,
                wordBreaks: burst.wordBreaks,
                start: burst.start,
                lastKey: burst.lastKey,
                endsAfterPause: burst.length < configuration.shortBurstLength
                    ? min(configuration.shortBurstGap, configuration.burstGap)
                    : configuration.burstGap,
                readsAsProse: burst.isProse(configuration),
                wasNudged: burst.wasNudged
            )
        }
    }

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

    /// Forgets the burst and the last nudge too, so the next prose is nudged as if the app had just started.
    public mutating func startOver() {
        burst = nil
        lastNudge = nil
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
        lastKey = time
        return counts.total
    }

    func hasEnded(at time: TimeInterval, _ configuration: DetectorConfiguration) -> Bool {
        let idle = time - lastKey
        return idle >= configuration.burstGap
            || (idle >= configuration.shortBurstGap && length < configuration.shortBurstLength)
    }

    func isProse(_ configuration: DetectorConfiguration) -> Bool {
        configuration.readsAsProse(length: length, letters: letters, wordBreaks: wordBreaks)
    }

    func isLong(at time: TimeInterval, _ configuration: DetectorConfiguration) -> Bool {
        length >= configuration.paragraphLength || time - start >= configuration.sustainedTyping
    }
}
