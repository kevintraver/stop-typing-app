import CoreGraphics
import StopTypingCore
import Testing

@Suite("Keyboard event privacy")
struct KeyboardPrivacyTests {
    private func event(for processID: Int64, text: String = "a") throws -> CGEvent {
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: processID)
        let characters = Array(text.utf16)
        event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        return event
    }

    @Test func queuedCountsDoNotSurviveAnIgnoredDestination() throws {
        let gate = TapGate()
        gate.allow(processID: 42)
        let allowed = try event(for: 42)
        let queued = try #require(gate.classify(allowed))
        let ignored = try event(for: 99, text: "z")
        #expect(gate.classify(ignored) == nil)
        gate.allow(processID: 42)
        #expect(!gate.accepts(generation: queued.generation))
        #expect(gate.classify(allowed) != nil)
    }

    @Test func closedGateDoesNotProduceCounts() throws {
        let gate = TapGate()
        let key = try event(for: 42)
        #expect(gate.classify(key) == nil)
        gate.allow(processID: 42)
        let queued = try #require(gate.classify(key))
        gate.allow(processID: nil)
        #expect(gate.classify(key) == nil)
        #expect(!gate.accepts(generation: queued.generation))
    }

    @Test func eventCharactersReduceToIdenticalLetterCounts() throws {
        let gate = TapGate()
        gate.allow(processID: 42)
        let first = try event(for: 42, text: "k")
        let second = try event(for: 42, text: "q")
        #expect(gate.classify(first)?.keystroke == gate.classify(second)?.keystroke)
        #expect(gate.classify(first)?.keystroke == .text(KeyCounts("x")))
    }
}
