import Testing
@testable import StopTypingCore

/// Presses keys one after another, 1 s apart, and returns the text the edits would produce.
private func type(_ keys: [KeyboardInput.Key], into input: inout KeyboardInput) -> String {
    var text = ""
    for (index, key) in keys.enumerated() {
        for edit in input.press(key, at: Double(index)) {
            switch edit {
            case .insert(let inserted): text += inserted
            case .deleteBackward: if !text.isEmpty { text.removeLast() }
            }
        }
    }
    return text
}

private func letters(_ string: String) -> [KeyboardInput.Key] {
    string.map { $0 == " " ? .space : .character(String($0)) }
}

@Suite("KeyboardInput")
struct KeyboardInputTests {
    @Test func capitalizesTheFirstLetterOnlyWhenTheFieldWantsIt() {
        var sentences = KeyboardInput(autocapitalizes: true)
        var plain = KeyboardInput(autocapitalizes: false)
        #expect(type(letters("hi there"), into: &sentences) == "Hi there")
        #expect(type(letters("hi there"), into: &plain) == "hi there")
    }

    @Test func shiftCapitalizesOneLetter() {
        var input = KeyboardInput(autocapitalizes: false)
        #expect(type([.shift] + letters("abc"), into: &input) == "Abc")
        #expect(input.shift == .off)
    }

    @Test func doubleTappingShiftLocksCaps() {
        var input = KeyboardInput(autocapitalizes: false)
        _ = input.press(.shift, at: 0)
        _ = input.press(.shift, at: 0.2)
        #expect(input.shift == .locked)
        for (index, key) in letters("abc").enumerated() { _ = input.press(key, at: 1 + Double(index)) }
        #expect(input.shift == .locked)
        _ = input.press(.shift, at: 5)
        #expect(input.shift == .off)
    }

    @Test func doubleSpaceAfterAWordBecomesAPeriodAndCapitalizesNext() {
        var input = KeyboardInput(autocapitalizes: true)
        #expect(type(letters("ok  next"), into: &input) == "Ok. Next")
    }

    @Test func aThirdSpaceStaysASpace() {
        var input = KeyboardInput(autocapitalizes: false)
        #expect(type(letters("ok   x"), into: &input) == "ok.  x")
    }

    @Test func sentencePunctuationCapitalizesTheNextWord() {
        var input = KeyboardInput(autocapitalizes: true)
        #expect(type(letters("done. next! yes? sure"), into: &input) == "Done. Next! Yes? Sure")
    }

    @Test func spaceAfterNumbersGoesBackToLetters() {
        var input = KeyboardInput(autocapitalizes: false)
        _ = input.press(.page(.numbers), at: 0)
        #expect(type([.character("4"), .character("2"), .space], into: &input) == "42 ")
        #expect(input.page == .letters)
    }

    @Test func returnInsertsANewlineAndCapitalizesWhenWanted() {
        var input = KeyboardInput(autocapitalizes: true)
        #expect(type(letters("a") + [.returnKey] + letters("b"), into: &input) == "A\nB")
    }

    @Test func deleteRemovesOneCharacter() {
        var input = KeyboardInput(autocapitalizes: false)
        #expect(type(letters("abc") + [.delete], into: &input) == "ab")
    }
}
