// SPDX-License-Identifier: Apache-2.0

public extension AsyncStream where Element: Sendable {
    /// Shifts every element forward in time by `interval` before forwarding it downstream.
    ///
    /// Each element's emission deadline is stamped at **arrival** (`arrival + interval`), so the
    /// original inter-arrival spacing is preserved — a slow consumer never compounds the delay.
    func delay<C: Clock>(for interval: C.Instant.Duration, clock: C) -> AsyncStream<Element>
    where C: Sendable {
        let upstream = self
        return AsyncStream { continuation in
            let task = Task {
                // The producer stamps each element with an absolute deadline at the moment it
                // arrives; the consumer sleeps until each (monotonic) deadline in order. Past
                // deadlines resume immediately, so the per-element shift never accumulates.
                let (timed, timedContinuation) = AsyncStream<(C.Instant, Element)>.makeStream()
                let producer = Task {
                    for await value in upstream {
                        timedContinuation.yield((clock.now.advanced(by: interval), value))
                    }
                    timedContinuation.finish()
                }
                for await (deadline, value) in timed {
                    try? await clock.sleep(until: deadline, tolerance: nil)
                    guard !Task.isCancelled else { break }
                    if case .terminated = continuation.yield(value) { break }
                }
                producer.cancel()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
