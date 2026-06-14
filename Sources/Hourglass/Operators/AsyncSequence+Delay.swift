public extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Shifts every element forward in time by `interval` before forwarding it downstream.
    func delay<C: Clock>(for interval: C.Instant.Duration, clock: C) -> AsyncStream<Element>
    where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await value in upstream {
                        try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                        guard !Task.isCancelled else { return }
                        if case .terminated = continuation.yield(value) { return }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
