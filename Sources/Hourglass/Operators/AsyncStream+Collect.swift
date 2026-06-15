private enum CollectEvent<Element: Sendable>: Sendable {
    case value(Element)
    case upstreamDone
    case tick
    case timerDone
}

public extension AsyncStream where Element: Sendable {
    /// Groups elements into arrays, flushing at the end of each time window.
    /// Empty windows are skipped. A partial window at upstream completion is always flushed.
    func collect<C: Clock>(every interval: C.Instant.Duration, clock: C) -> AsyncStream<[Element]>
    where C: Sendable {
        let upstream = self
        return AsyncStream<[Element]> { continuation in
            let (ticks, ticksContinuation) = AsyncStream<Void>.makeStream()

            let timerTask = Task {
                var next = clock.now.advanced(by: interval)
                while !Task.isCancelled {
                    try? await clock.sleep(until: next, tolerance: nil)
                    guard !Task.isCancelled else { return }
                    ticksContinuation.yield(())
                    next = next.advanced(by: interval)
                }
                ticksContinuation.finish()
            }

            let mainTask = Task {
                await runCollect(
                    upstream: upstream,
                    ticks: ticks,
                    timerTask: timerTask,
                    ticksContinuation: ticksContinuation,
                    continuation: continuation
                )
            }

            continuation.onTermination = { _ in
                timerTask.cancel()
                mainTask.cancel()
                ticksContinuation.finish()
            }
        }
    }
}

private func runCollect<Element: Sendable>(
    upstream: AsyncStream<Element>,
    ticks: AsyncStream<Void>,
    timerTask: Task<Void, Never>,
    ticksContinuation: AsyncStream<Void>.Continuation,
    continuation: AsyncStream<[Element]>.Continuation
) async {
    let upBox = IteratorBox(upstream)
    let tickBox = IteratorBox(ticks)
    var bucket: [Element] = []

    await withTaskGroup(of: CollectEvent<Element>.self) { group in
        group.addTask { if let value = await upBox.next() { .value(value) } else { .upstreamDone } }
        group.addTask { (await tickBox.next()) != nil ? .tick : .timerDone }

        outer: while let event = await group.next() {
            switch event {
            case .value(let value):
                bucket.append(value)
                group.addTask { if let value = await upBox.next() { .value(value) } else { .upstreamDone } }
            case .tick:
                if !bucket.isEmpty {
                    if case .terminated = continuation.yield(bucket) { break outer }
                    bucket = []
                }
                group.addTask { (await tickBox.next()) != nil ? .tick : .timerDone }
            case .upstreamDone:
                timerTask.cancel(); ticksContinuation.finish()
                break outer
            case .timerDone:
                break outer
            }
        }
    }

    if !bucket.isEmpty { continuation.yield(bucket) }
    continuation.finish()
}
