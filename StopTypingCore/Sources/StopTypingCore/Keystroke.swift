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
///
/// Only the kind of character survives: letter, word break or other. Any two letters give identical
/// counts, so nothing downstream can tell which keys were pressed, only how many of each kind.
public struct KeyCounts: Equatable, Sendable {
    public private(set) var letters = 0
    public private(set) var wordBreaks = 0
    /// Digits, punctuation and symbols such as `=`, `+`, `|` and `<`: they add to a burst's length but
    /// not to how much it reads like prose. Arrows, Delete and function keys aren't counted at all.
    public private(set) var others = 0

    public var total: Int { letters + wordBreaks + others }

    public init(_ text: String) {
        for character in text {
            if character.isLetter {
                letters += 1
            } else if character.isWhitespace {
                wordBreaks += 1
            } else if character.isNumber || character.isPunctuation || character.isSymbol {
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
