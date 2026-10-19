import Testing
@testable import StopTypingCore

@Suite("Input privacy boundaries")
struct InputScopeTests {
    @Test func startsClosedAndRejectsUnknownDestinations() {
        var scope = InputScope()
        #expect(scope.capture(processID: 42) == nil)
        scope.allow(processID: 42)
        #expect(scope.capture(processID: 0) == nil)
        #expect(scope.capture(processID: 42) == nil)
    }

    @Test func ignoredInputCannotCrossADelayedAppSwitch() throws {
        var scope = InputScope()
        scope.allow(processID: 42)
        let earlierCapture = scope.capture(processID: 42)
        let earlier = try #require(earlierCapture)
        // The tap sees the ignored destination before the main actor sees its activation.
        #expect(scope.capture(processID: 99) == nil)
        #expect(!scope.accepts(generation: earlier))
        #expect(scope.capture(processID: 42) == nil)
        scope.allow(processID: 42)
        #expect(!scope.accepts(generation: earlier))
        #expect(scope.capture(processID: 42) != nil)
    }

    @Test func snoozeAndResumeDiscardAlreadyQueuedCounts() throws {
        var scope = InputScope()
        scope.allow(processID: 42)
        let queuedCapture = scope.capture(processID: 42)
        let queued = try #require(queuedCapture)
        scope.allow(processID: nil)
        scope.allow(processID: 42)
        #expect(!scope.accepts(generation: queued))
        let resumedCapture = scope.capture(processID: 42)
        let resumed = try #require(resumedCapture)
        #expect(scope.accepts(generation: resumed))
    }

    @Test func unchangedPermissionKeepsCurrentCountsValid() throws {
        var scope = InputScope()
        scope.allow(processID: 42)
        let queuedCapture = scope.capture(processID: 42)
        let queued = try #require(queuedCapture)
        scope.allow(processID: 42)
        #expect(scope.accepts(generation: queued))
        scope.allow(processID: 77)
        #expect(!scope.accepts(generation: queued))
    }
}
