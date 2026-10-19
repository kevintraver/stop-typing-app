/// Authorizes one destination process at a time. Only the generation travels with queued counts.
public struct InputScope: Sendable {
    private var processID: Int32?
    private var generation: UInt64 = 0

    public init() {}

    public mutating func allow(processID: Int32?) {
        guard self.processID != processID else { return }
        self.processID = processID
        generation += 1
    }

    /// A different destination closes the scope immediately, even if the UI has not handled
    /// the app-switch notification yet. Earlier queued counts then become invalid too.
    public mutating func capture(processID: Int32) -> UInt64? {
        guard processID > 0, self.processID == processID else {
            allow(processID: nil)
            return nil
        }
        return generation
    }

    public func accepts(generation: UInt64) -> Bool {
        processID != nil && self.generation == generation
    }
}
