// SPDX-License-Identifier: Apache-2.0

/// Returns an `AsyncStream` that emits the current clock instant at every `interval`.
/// The first tick fires after one full `interval` from the call site.
/// The stream runs until cancelled.
public func timerSequence<C: Clock>(every interval: C.Instant.Duration, clock: C) -> AsyncStream<C.Instant>
where C: Sendable {
    AsyncStream { continuation in
        let task = Task {
            var next = clock.now.advanced(by: interval)
            while !Task.isCancelled {
                try? await clock.sleep(until: next, tolerance: nil)
                guard !Task.isCancelled else { return }
                if case .terminated = continuation.yield(clock.now) { return }
                next = next.advanced(by: interval)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
