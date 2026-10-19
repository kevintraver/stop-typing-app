/// What a single key press means to the detector. Characters are classified and dropped, never stored.
public enum Keystroke: Equatable, Sendable {
    /// Characters produced by a key pressed without Command, Control or Option.
    case text(String)
    /// A key pressed with Command, Control or Option. Neither counts nor ends a burst.
    case shortcut
    /// Escape abandons whatever was being typed.
    case escape
}

public enum Nudge: Equatable, Sendable {
    /// The first nudge for a burst that reads like prose.
    case gentle
    /// The user kept typing at length after being nudged.
    case firm
    /// The user kept typing through a firm nudge.
    case stop
}
