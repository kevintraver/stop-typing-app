import Foundation

/// The iPhone keyboard's typing behaviour: which page is showing, shift and caps lock, automatic
/// capitals after a sentence, and the double-space period.
///
/// It never sees the text being edited. Everything it knows comes from its own key presses, and
/// it keeps only the kind of the last key (space, sentence end, letter), never the key itself.
public struct KeyboardInput: Equatable, Sendable {
    public enum Page: Equatable, Sendable {
        case letters, numbers, symbols
    }

    public enum Shift: Equatable, Sendable {
        case off
        /// Capitalizes the next letter, then turns off.
        case once
        case locked
    }

    public enum Key: Equatable, Sendable {
        case character(String)
        case space
        case returnKey
        case delete
        case shift
        case page(Page)
    }

    /// What to do to the text field.
    public enum Edit: Equatable, Sendable {
        case insert(String)
        case deleteBackward
    }

    /// Two shift taps closer together than this lock caps.
    public static let capsLockInterval: TimeInterval = 0.35

    public private(set) var page = Page.letters
    public private(set) var shift = Shift.off
    public let autocapitalizes: Bool

    private enum LastKey: Equatable {
        case none, wordCharacter, sentenceEnd, space, other
    }

    private var lastKey = LastKey.none
    private var lastShiftTap: TimeInterval?

    /// Starts on letters, capitalized if the field wants sentence capitals. The field could be
    /// mid-sentence, but the keyboard can't know without reading it, and it never does.
    public init(autocapitalizes: Bool) {
        self.autocapitalizes = autocapitalizes
        shift = autocapitalizes ? .once : .off
    }

    /// Applies a key and returns the edits to make, in order.
    public mutating func press(_ key: Key, at time: TimeInterval) -> [Edit] {
        switch key {
        case .character(let character):
            return [.insert(type(character))]
        case .space:
            return typeSpace()
        case .returnKey:
            lastKey = .space
            if autocapitalizes && shift != .locked { shift = .once }
            return [.insert("\n")]
        case .delete:
            lastKey = .other
            return [.deleteBackward]
        case .shift:
            toggleShift(at: time)
            return []
        case .page(let newPage):
            page = newPage
            return []
        }
    }

    private mutating func type(_ character: String) -> String {
        let text = page == .letters && shift != .off ? character.uppercased() : character
        if shift == .once { shift = .off }
        if [".", "!", "?"].contains(character) {
            lastKey = .sentenceEnd
        } else if character.first.map({ $0.isLetter || $0.isNumber }) ?? false {
            lastKey = .wordCharacter
        } else {
            lastKey = .other
        }
        return text
    }

    private mutating func typeSpace() -> [Edit] {
        defer {
            // Like the system keyboard, a space after numbers or symbols goes back to letters.
            page = .letters
        }
        switch lastKey {
        case .space:
            // Double space after a word: "word␣" becomes "word.␣". A third space stays a space.
            lastKey = .other
            if autocapitalizes && shift != .locked { shift = .once }
            return [.deleteBackward, .insert(". ")]
        case .sentenceEnd:
            lastKey = .other
            if autocapitalizes && shift != .locked { shift = .once }
            return [.insert(" ")]
        case .wordCharacter:
            lastKey = .space
            return [.insert(" ")]
        case .none, .other:
            lastKey = .other
            return [.insert(" ")]
        }
    }

    private mutating func toggleShift(at time: TimeInterval) {
        defer { lastShiftTap = time }
        if let lastShiftTap, time - lastShiftTap < Self.capsLockInterval, shift == .once || shift == .off {
            shift = .locked
            return
        }
        shift = shift == .off ? .once : .off
    }
}
