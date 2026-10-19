/// What a single key press means to the detector. The event tap builds this the moment a key
/// arrives, so no typed character ever leaves the tap's callback.
public enum Keystroke: Equatable, Sendable {
    /// Counts for a key pressed without Command, Control or Option.
    case text(KeyCounts)
    /// A key pressed with Command, Control or Option. Neither counts nor ends a burst.
    case shortcut
    /// Escape abandons whatever was being typed.
    case escape
}

/// The countable parts of a key press, with the characters themselves thrown away.
public struct KeyCounts: Equatable, Sendable {
    public private(set) var letters = 0
    public private(set) var wordBreaks = 0
    /// Digits and punctuation: they add to a burst's length but not to how much it reads like prose.
    /// Symbols, arrows, Delete and function keys aren't counted at all.
    public private(set) var others = 0
    /// Which of 16 buckets the letters fell into. Enough to tell `jjjj` from varied prose,
    /// but deliberately too coarse to tell which letters were typed (a and q share a bucket).
    public private(set) var letterBuckets: UInt16 = 0

    public var total: Int { letters + wordBreaks + others }

    public init(_ text: String) {
        for character in text {
            if character.isLetter {
                letters += 1
                let scalar = character.lowercased().unicodeScalars.first?.value ?? 0
                letterBuckets |= 1 << (scalar & 0xF)
            } else if character.isWhitespace {
                wordBreaks += 1
            } else if character.isNumber || character.isPunctuation {
                others += 1
            }
        }
    }
}

public enum Nudge: Equatable, Sendable {
    /// The first nudge for a burst that reads like prose.
    case gentle
    /// The user kept typing at length after being nudged.
    case firm
    /// The user kept typing through a nudge, with the stop window turned on.
    case stop
}
