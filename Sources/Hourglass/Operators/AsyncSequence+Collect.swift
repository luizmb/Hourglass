private enum _CollectEvent<E: Sendable>: Sendable {
    case element(E)
    case tick
    case upstreamDone
    case timerDone
}

public extension AsyncSequence where Self: Sendable, Element: Sendable {
    /// Groups elements into arrays, flushing at the end of each time window.
    /// Empty windows are skipped. A partial window at upstream completion is always flushed.
    func collect<C: Clock>(every interval: C.Instant.Duration, clock: C) -> AsyncStream<[Element]>
    where C: Sendable {
        let upstream = self

        return AsyncStream { continuation in
            let (ticks, ticksCont) = AsyncStream<Void>.makeStream()

            let timerTask = Task {
                var next = clock.now.advanced(by: interval)
                while !Task.isCancelled {
                    try? await clock.sleep(until: next, tolerance: nil)
                    guard !Task.isCancelled else { return }
                    ticksCont.yield(())
                    next = next.advanced(by: interval)
                }
                ticksCont.finish()
            }

            let mainTask = Task {
                // Convert self to AsyncStream so we can box the iterator for the task group.
                let upstreamStream = AsyncStream<Element> { cont in
                    let t = Task {
                        do {
                            for try await element in upstream {
                                guard !Task.isCancelled else { break }
                                cont.yield(element)
                            }
                        } catch {}
                        cont.finish()
                    }
                    cont.onTermination = { _ in t.cancel() }
                }

                let upBox = _IteratorBox(upstreamStream)
                let tickBox = _IteratorBox(ticks)

                var bucket: [Element] = []

                await withTaskGroup(of: _CollectEvent<Element>.self) { group in
                    group.addTask { if let v = await upBox.next() { .element(v) } else { .upstreamDone } }
                    group.addTask { (await tickBox.next()) != nil ? .tick : .timerDone }

                    outer: while let event = await group.next() {
                        switch event {
                        case .element(let v):
                            bucket.append(v)
                            group.addTask { if let e = await upBox.next() { .element(e) } else { .upstreamDone } }
                        case .tick:
                            if !bucket.isEmpty {
                                if case .terminated = continuation.yield(bucket) { break outer }
                                bucket = []
                            }
                            group.addTask { (await tickBox.next()) != nil ? .tick : .timerDone }
                        case .upstreamDone:
                            timerTask.cancel()
                            ticksCont.finish()
                            break outer
                        case .timerDone:
                            break outer
                        }
                    }
                }

                if !bucket.isEmpty { continuation.yield(bucket) }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                timerTask.cancel()
                mainTask.cancel()
                ticksCont.finish()
            }
        }
    }
}
