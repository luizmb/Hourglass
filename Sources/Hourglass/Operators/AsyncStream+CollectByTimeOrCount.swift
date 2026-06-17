private enum CollectByTimeOrCountEvent<Element: Sendable>: Sendable {
    case value(Element?)
    case tick(Int)  // window generation — stale ticks (from a window already flushed by count) are ignored
}

public extension AsyncStream where Element: Sendable {
    /// Groups elements into arrays, flushing when the time window elapses **or** the buffer
    /// reaches `count`, whichever comes first. Each flush starts a fresh window (a count-flush
    /// resets the timer). Empty time-windows are skipped; a partial window at upstream completion
    /// is flushed.
    func collect<C: Clock>(
        every interval: C.Instant.Duration,
        orCount count: Int,
        clock: C
    ) -> AsyncStream<[Element]> where C: Sendable {
        let upstream = self
        return AsyncStream<[Element]> { continuation in
            let task = Task {
                await runCollectByTimeOrCount(
                    upstream: upstream,
                    interval: interval,
                    count: Swift.max(1, count),
                    clock: clock,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

private func runCollectByTimeOrCount<Element: Sendable, C: Clock & Sendable>(
    upstream: AsyncStream<Element>,
    interval: C.Instant.Duration,
    count: Int,
    clock: C,
    continuation: AsyncStream<[Element]>.Continuation
) async {
    let upBox = IteratorBox(upstream)
    var bucket: [Element] = []
    var generation = 0

    await withTaskGroup(of: CollectByTimeOrCountEvent<Element>.self) { group in
        group.addTask { .value(await upBox.next()) }
        let initial = generation
        group.addTask {
            try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
            return .tick(initial)
        }

        outer: while let event = await group.next() {
            switch event {
            case .value(let maybe):
                guard let value = maybe else { break outer }  // upstream finished
                bucket.append(value)
                if bucket.count >= count {
                    if case .terminated = continuation.yield(bucket) { break outer }
                    bucket = []
                    generation += 1
                    let gen = generation  // count flush resets the time window
                    group.addTask {
                        try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                        return .tick(gen)
                    }
                }
                group.addTask { .value(await upBox.next()) }
            case .tick(let gen):
                guard gen == generation else { continue }  // stale tick from an already-flushed window
                if !bucket.isEmpty {
                    if case .terminated = continuation.yield(bucket) { break outer }
                    bucket = []
                }
                generation += 1
                let next = generation
                group.addTask {
                    try? await clock.sleep(until: clock.now.advanced(by: interval), tolerance: nil)
                    return .tick(next)
                }
            }
        }
        group.cancelAll()
    }

    if !bucket.isEmpty { continuation.yield(bucket) }
    continuation.finish()
}
