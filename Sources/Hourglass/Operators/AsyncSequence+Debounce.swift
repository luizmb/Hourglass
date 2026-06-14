public extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Delays forwarding elements until the upstream is idle for `interval`.
    /// If new elements arrive within the window, the timer resets. Only the last
    /// element in each idle window is emitted.
    func debounce<C: Clock>(for interval: C.Instant.Duration, clock: C) -> AsyncStream<Element>
    where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                var pendingTask: Task<Void, Never>?
                defer { pendingTask?.cancel() }
                do {
                    for try await value in upstream {
                        pendingTask?.cancel()
                        pendingTask = Task {
                            try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                            guard !Task.isCancelled else { return }
                            _ = continuation.yield(value)
                        }
                    }
                } catch {}
                if let pending = pendingTask, !Task.isCancelled {
                    await pending.value
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
