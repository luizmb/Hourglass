import Foundation

/// A clock whose time only advances when you call `advance(by:)`.
/// Use in tests to drive timing operators (`debounce`, `delay`, `timer`, etc.) deterministically.
public final class TestClock: Clock, @unchecked Sendable {
    public typealias Duration = Swift.Duration

    public struct Instant: InstantProtocol, Sendable, Hashable {
        public var offset: Duration

        public init(offset: Duration = .zero) { self.offset = offset }

        public func advanced(by duration: Duration) -> Self { .init(offset: offset + duration) }
        public func duration(to other: Self) -> Duration { other.offset - offset }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private struct _State {
        var now: Instant = .init()
        var nextID: Int = 0
        var sleepers: [(id: Int, deadline: Instant, continuation: CheckedContinuation<Void, Error>)] = []
    }

    private let _lock = NSLock()
    private var _state = _State()

    public var now: Instant { _lock.withLock { _state.now } }
    public var minimumResolution: Duration { .nanoseconds(1) }

    public init() {}

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        let id: Int = _lock.withLock { _state.nextID; _state.nextID += 1; return _state.nextID - 1 }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                _lock.withLock {
                    if _state.now >= deadline {
                        c.resume()
                    } else if Task.isCancelled {
                        // Handles the narrow race: task was cancelled after the initial
                        // checkCancellation() but before withTaskCancellationHandler registered
                        // the onCancel handler, so onCancel already fired without finding us.
                        c.resume(throwing: CancellationError())
                    } else {
                        _state.sleepers.append((id: id, deadline: deadline, continuation: c))
                        _state.sleepers.sort { $0.deadline < $1.deadline }
                    }
                }
            }
        } onCancel: {
            let toResume: CheckedContinuation<Void, Error>? = _lock.withLock {
                guard let idx = _state.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                let c = _state.sleepers[idx].continuation
                _state.sleepers.remove(at: idx)
                return c
            }
            toResume?.resume(throwing: CancellationError())
        }
        try Task.checkCancellation()
    }

    /// Suspends until at least `count` tasks are sleeping in this clock.
    /// Call this before `advance(by:)` in tests to ensure all expected sleepers
    /// have registered before virtual time moves. Defaults to 1.
    public func waitForSleepers(count: Int = 1) async {
        while _lock.withLock({ _state.sleepers.count }) < count {
            await Task.yield()
        }
    }

    /// Advance virtual time by `duration`, waking all tasks sleeping past the new `now`.
    /// Yields between each woken task so they can run and register new sleeps before
    /// the next `advance` call.
    public func advance(by duration: Duration) async {
        let toResume = _lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            // Capture 'now' as a local before any mutating call to avoid Swift exclusivity
            // violations (removeAll closure would read _state.now while _state is mutably borrowed).
            let now = _state.now.advanced(by: duration)
            _state.now = now
            let ready = _state.sleepers.filter { $0.deadline <= now }.map(\.continuation)
            _state.sleepers.removeAll { $0.deadline <= now }
            return ready
        }
        for continuation in toResume {
            continuation.resume()
            await Task.yield()
        }
    }
}
