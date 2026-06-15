public extension AsyncStream where Element: Sendable {
    /// Rate-limits the upstream to at most one element per `interval` window.
    ///
    /// - Parameters:
    ///   - latest: When `false` (leading edge), the first element of each window is emitted
    ///     immediately and later arrivals in that window are dropped. When `true` (trailing
    ///     edge), the most recent element of the window is emitted when the window **closes** —
    ///     driven by the clock, so it fires even if no further element arrives. A trailing value
    ///     still pending when the upstream completes is flushed.
    ///   - clock: The clock that times the window.
    func throttle<C: Clock>(
        for interval: C.Instant.Duration,
        clock: C,
        latest: Bool
    ) -> AsyncStream<Element> where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                await runThrottle(upstream: upstream, interval: interval, clock: clock, latest: latest, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private enum ThrottleEvent<Element: Sendable>: Sendable {
    case upstream(Element?)
    case tick
}

private func runThrottle<Element: Sendable, C: Clock & Sendable>(
    upstream: AsyncStream<Element>,
    interval: C.Instant.Duration,
    clock: C,
    latest: Bool,
    continuation: AsyncStream<Element>.Continuation
) async {
    let upBox = IteratorBox(upstream)
    var windowOpen = false
    var pending: Element?

    await withTaskGroup(of: ThrottleEvent<Element>.self) { group in
        group.addTask { .upstream(await upBox.next()) }
        loop: while let event = await group.next() {
            switch event {
            case .upstream(let maybe):
                guard let value = maybe else {
                    if latest, let value = pending { _ = continuation.yield(value) }
                    break loop
                }
                let opening = !windowOpen
                windowOpen = true
                if latest { pending = value }
                if opening {
                    if !latest, case .terminated = continuation.yield(value) { break loop }
                    group.addTask {
                        try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                        return .tick
                    }
                }
                group.addTask { .upstream(await upBox.next()) }
            case .tick:
                windowOpen = false
                if latest, let value = pending {
                    pending = nil
                    if case .terminated = continuation.yield(value) { break loop }
                }
            }
        }
    }
    continuation.finish()
}
