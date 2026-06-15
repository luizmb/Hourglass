public extension AsyncStream where Element: Sendable {
    /// Forwards each element as `.success`, but fails if the upstream goes quiet for too long.
    ///
    /// The deadline is armed at subscription and re-armed after every element. If `interval`
    /// elapses without a new element, `.failure(error())` is emitted and the stream finishes.
    /// Normal upstream completion finishes the stream without a failure.
    ///
    /// The failure is carried as a **typed value** (`Result<Element, E>`) rather than thrown, so
    /// iteration never surfaces an untyped `any Error` — the error type `E` is preserved end to
    /// end, mirroring the rest of Hourglass's `AsyncStream`-based operators.
    func timeout<C: Clock, E: Error>(
        _ interval: C.Instant.Duration,
        clock: C,
        error: @escaping @Sendable () -> E
    ) -> AsyncStream<Result<Element, E>> where C: Sendable {
        let upstream = self
        return AsyncStream<Result<Element, E>> { continuation in
            let task = Task {
                @Sendable func armTimer() -> Task<Void, Never> {
                    Task {
                        try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                        guard !Task.isCancelled else { return }
                        _ = continuation.yield(.failure(error()))
                        continuation.finish()
                    }
                }
                var timerTask = armTimer()
                defer { timerTask.cancel() }
                for await value in upstream {
                    timerTask.cancel()
                    if case .terminated = continuation.yield(.success(value)) { return }
                    timerTask = armTimer()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
