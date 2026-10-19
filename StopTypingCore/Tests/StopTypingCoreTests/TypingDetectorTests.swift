import Testing
@testable import StopTypingCore

/// Types `text` one character at a time, `interval` seconds apart, starting at `start`.
/// Returns every nudge with the time it fired, plus the time of the last keystroke.
private func type(
    _ text: String,
    into detector: inout TypingDetector,
    from start: Double = 0,
    interval: Double = 0.1
) -> (nudges: [(Nudge, Double)], prose: Int, end: Double) {
    var nudges: [(Nudge, Double)] = []
    var prose = 0
    var time = start
    for character in text {
        let outcome = detector.register(.text(KeyCounts(String(character))), at: time)
        if let nudge = outcome.nudge { nudges.append((nudge, time)) }
        prose += outcome.newProseCharacters
        time += interval
    }
    return (nudges, prose, time - interval)
}

private let sentence = "I think we should move the meeting to Thursday afternoon"
private let paragraph = String(repeating: "this is a long paragraph of ordinary words ", count: 4)

@Suite("TypingDetector")
struct TypingDetectorTests {
    @Test func nudgesGentlyOnceASentenceOfProseIsTyped() {
        var detector = TypingDetector()
        let result = type(sentence, into: &detector)

        #expect(result.nudges.map(\.0) == [.gentle])
        let nudgeIndex = Int((result.nudges[0].1 / 0.1).rounded())
        #expect(nudgeIndex + 1 == DetectorConfiguration().sentenceLength)
    }

    @Test func shortTextNeverNudges() {
        var detector = TypingDetector()
        #expect(type("thanks, sounds good", into: &detector).nudges.isEmpty)
    }

    @Test(arguments: [
        String(repeating: "j", count: 60),              // Vim motions / held key
        String(repeating: "jjkkhhll", count: 8),         // Vim navigation
        "https://example.com/some/long/path/to/a/page",  // no word breaks
        "let x = foo(bar, 1); let y = baz(2, 3); z(4)",  // symbol- and digit-heavy code
    ])
    func nonProseNeverNudges(text: String) {
        var detector = TypingDetector()
        #expect(type(text, into: &detector).nudges.isEmpty)
    }

    @Test func shortcutsAreIgnoredAndDoNotBreakTheBurst() {
        var detector = TypingDetector()
        let first = type("I think we should move ", into: &detector)
        _ = detector.register(.shortcut, at: first.end + 0.1)
        let second = type("the meeting to Thursday", into: &detector, from: first.end + 0.2)

        #expect(first.nudges.isEmpty)
        #expect(second.nudges.map(\.0) == [.gentle])
    }

    @Test func escapeEndsTheBurst() {
        var detector = TypingDetector()
        let first = type("I think we should move ", into: &detector)
        _ = detector.register(.escape, at: first.end + 0.1)
        let second = type("the meeting to Thursday", into: &detector, from: first.end + 0.2)

        #expect((first.nudges + second.nudges).isEmpty)
    }

    @Test func aLongPauseEndsTheBurst() {
        var detector = TypingDetector()
        let first = type("I think we should move ", into: &detector)
        let second = type("the meeting to Thursday", into: &detector, from: first.end + 5)

        #expect((first.nudges + second.nudges).isEmpty)
    }

    @Test func aShortBurstEndsAfterAShorterPause() {
        var detector = TypingDetector()
        let first = type("I think ", into: &detector)
        // 23 characters: only a nudge if it still counted as one burst with the first 8.
        let second = type("we should move the meet", into: &detector, from: first.end + 2.5)

        #expect(second.nudges.isEmpty)
    }

    @Test func aMidLengthPauseKeepsALongerBurstGoing() {
        var detector = TypingDetector()
        let first = type("I think we should ", into: &detector)
        let second = type("move the meeting", into: &detector, from: first.end + 3)

        #expect(second.nudges.map(\.0) == [.gentle])
    }

    @Test func aNewSentenceDuringTheCooldownIsNotNudged() {
        var detector = TypingDetector()
        let first = type(sentence, into: &detector)
        let second = type(sentence, into: &detector, from: first.end + 10)

        #expect(first.nudges.count == 1)
        #expect(second.nudges.isEmpty)
    }

    @Test func aNewSentenceAfterTheCooldownIsNudgedAgain() {
        var detector = TypingDetector()
        let first = type(sentence, into: &detector)
        let second = type(sentence, into: &detector, from: first.end + 120)

        #expect(first.nudges.map(\.0) == [.gentle])
        #expect(second.nudges.map(\.0) == [.gentle])
    }

    @Test func typingAParagraphAfterANudgeEscalates() {
        var detector = TypingDetector()
        // 0.4s per key: the burst passes 80 characters after the 30s escalation interval.
        let result = type(paragraph, into: &detector, interval: 0.4)

        #expect(result.nudges.map(\.0).prefix(2) == [.gentle, .firm])
        let gap = result.nudges[1].1 - result.nudges[0].1
        #expect(gap >= DetectorConfiguration().escalationInterval)
    }

    @Test func withoutTheStopWindowFirmNudgesRepeat() {
        var detector = TypingDetector()
        let long = String(repeating: paragraph, count: 4)
        let result = type(long, into: &detector, interval: 0.3)

        #expect(result.nudges.count > 2)
        #expect(result.nudges.map(\.0).dropFirst().allSatisfy { $0 == .firm })
        for (previous, next) in zip(result.nudges, result.nudges.dropFirst()) {
            #expect(next.1 - previous.1 >= DetectorConfiguration().escalationInterval)
        }
    }

    @Test func withTheStopWindowTypingThroughAGentleNudgeStops() {
        var detector = TypingDetector()
        detector.usesStopWindow = true
        let result = type(paragraph, into: &detector, interval: 0.4)

        #expect(result.nudges.map(\.0) == [.gentle, .stop])
        #expect(result.nudges[1].1 - result.nudges[0].1 >= DetectorConfiguration().stopDelay)
    }

    @Test func aFreshLongBurstAfterAShortPauseAlsoStops() {
        var detector = TypingDetector()
        detector.usesStopWindow = true
        let first = type(sentence, into: &detector)
        let second = type(paragraph, into: &detector, from: first.end + 25, interval: 0.2)

        #expect(first.nudges.map(\.0) == [.gentle])
        #expect(second.nudges.map(\.0) == [.stop])
    }

    @Test func respectsAConfiguredStopDelay() {
        var detector = TypingDetector()
        detector.usesStopWindow = true
        detector.configuration.stopDelay = 15
        let result = type(paragraph, into: &detector, interval: 0.25)

        #expect(result.nudges.map(\.0) == [.gentle, .stop])
        let gap = result.nudges[1].1 - result.nudges[0].1
        #expect(gap >= 15 && gap < 30)
    }

    @Test func afterAcknowledgingTheStopItWaitsACooldownThenStartsOver() {
        var detector = TypingDetector()
        detector.usesStopWindow = true
        let first = type(paragraph, into: &detector, interval: 0.4)
        detector.acknowledgeStop(at: first.end + 10)

        let soon = type(paragraph, into: &detector, from: first.end + 11, interval: 0.2)
        let later = type(paragraph, into: &detector, from: first.end + 10 + 120, interval: 0.4)

        #expect(first.nudges.map(\.0) == [.gentle, .stop])
        #expect(soon.nudges.isEmpty)
        #expect(later.nudges.map(\.0) == [.gentle, .stop])
    }

    @Test func quietModeCountsProseButNeverNudgesOrEscalates() {
        var detector = TypingDetector()
        detector.usesStopWindow = true
        detector.isQuiet = true
        let quiet = type(paragraph, into: &detector, interval: 0.4)
        detector.isQuiet = false
        let after = type(sentence, into: &detector, from: quiet.end + 10)

        #expect(quiet.nudges.isEmpty)
        #expect(quiet.prose > 0)
        #expect(after.nudges.map(\.0) == [.gentle])
    }

    @Test func countsProseCharactersOnlyOnceTheBurstReadsLikeProse() {
        var detector = TypingDetector()
        let prose = type(sentence, into: &detector)
        let code = type(String(repeating: "j", count: 40), into: &detector, from: prose.end + 10)

        #expect(prose.prose == sentence.count)
        #expect(code.prose == 0)
    }

    @Test func respectsAConfiguredSentenceLength() {
        var configuration = DetectorConfiguration()
        configuration.sentenceLength = 40
        var detector = TypingDetector(configuration: configuration)
        let result = type(sentence, into: &detector)

        let nudgeIndex = Int((result.nudges[0].1 / 0.1).rounded())
        #expect(nudgeIndex + 1 == 40)
    }

    @Test func multiCharacterKeysAndNonLatinTextCount() {
        var detector = TypingDetector()
        let words = ["Ça ", "fait ", "très ", "longtemps ", "que ", "je ", "n'écris ", "pas"]
        var nudges: [Nudge] = []
        for (index, word) in words.enumerated() {
            if let nudge = detector.register(.text(KeyCounts(word)), at: Double(index)).nudge { nudges.append(nudge) }
        }
        #expect(nudges == [.gentle])
    }

    @Test func keyCountsKeepOnlyCoarseLetterBuckets() {
        // a (0x61) and q (0x71) share a bucket, so the mask can't say which of them was typed.
        #expect(KeyCounts("a").letterBuckets == KeyCounts("q").letterBuckets)
        #expect(KeyCounts("A").letterBuckets == KeyCounts("a").letterBuckets)
        #expect(KeyCounts("jjkkhhll").letterBuckets.nonzeroBitCount == 4)
    }

    @Test func keyCountsClassifyWithoutKeepingText() {
        let counts = KeyCounts("Hi, 2 you!")
        #expect(counts.letters == 5)
        #expect(counts.wordBreaks == 2)
        #expect(counts.others == 3)
        #expect(KeyCounts("\u{F700}=+").total == 0) // an arrow key and symbols don't count
    }
}
