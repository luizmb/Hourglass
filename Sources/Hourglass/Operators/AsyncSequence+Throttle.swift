public extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Rate-limits the upstream to at most one element per `interval` window.
    ///
    /// - Parameters:
    ///   - latest: When `false` (leading edge), the first element in each window is emitted
    ///     immediately and subsequent arrivals are dropped until the window closes.
    ///     When `true` (trailing edge), the most recent element is emitted at window end.
    func throttle<C: Clock>(
        for interval: C.Instant.Duration,
        clock: C,
        latest: Bool
    ) -> AsyncStream<Element> where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                var windowStart = clock.now
                var latestValue: Element?
                var hasEmittedInWindow = false

                do {
                    for try await value in upstream {
                        let now = clock.now
                        if now >= windowStart.advanced(by: interval) {
                            if latest, let v = latestValue, hasEmittedInWindow {
                                if case .terminated = continuation.yield(v) { return }
                            }
                            windowStart = now
                            hasEmittedInWindow = false
                            latestValue = value
                        } else {
                            latestValue = value
                        }
                        if !hasEmittedInWindow && !latest {
                            if case .terminated = continuation.yield(value) { return }
                            hasEmittedInWindow = true
                        } else if !hasEmittedInWindow && latest {
                            hasEmittedInWindow = true
                        }
                    }
                } catch {}
                if latest, let v = latestValue, hasEmittedInWindow {
                    continuation.yield(v)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
