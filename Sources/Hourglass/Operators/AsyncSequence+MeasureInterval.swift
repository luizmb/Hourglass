public extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Replaces each element with the elapsed duration since the previous element (or subscription).
    func measureInterval<C: Clock>(using clock: C) -> AsyncStream<C.Instant.Duration>
    where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                var last = clock.now
                do {
                    for try await _ in upstream {
                        let now = clock.now
                        let elapsed = last.duration(to: now)
                        last = now
                        if case .terminated = continuation.yield(elapsed) { return }
                    }
                } catch {}
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
