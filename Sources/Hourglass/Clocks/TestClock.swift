// SPDX-License-Identifier: Apache-2.0

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
        let id: Int = _lock.withLock { let i = _state.nextID; _state.nextID += 1; return i }
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
        await advance(to: now.advanced(by: duration))
    }

    /// Advance virtual time to the absolute instant `deadline`, waking every task sleeping at or
    /// before it. A no-op when `deadline` is at or before the current `now` (virtual time never
    /// moves backwards). Yields between each woken task so they can run and register new sleeps
    /// before the next call.
    public func advance(to deadline: Instant) async {
        let toResume = _lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            // Bail before mutating if the target is not in the future — keeps `now` monotonic.
            guard deadline > _state.now else { return [] }
            _state.now = deadline
            let ready = _state.sleepers.filter { $0.deadline <= deadline }.map(\.continuation)
            _state.sleepers.removeAll { $0.deadline <= deadline }
            return ready
        }
        for continuation in toResume {
            continuation.resume()
            await Task.yield()
        }
    }

    /// Advance virtual time as far as needed to wake every currently-suspended sleeper, draining
    /// chained sleeps (a woken task that immediately sleeps again is also resumed). Returns once no
    /// task is sleeping in this clock.
    ///
    /// Use this to exhaust a finite sequence of sleeps without counting `advance` steps. Do **not**
    /// call it on a clock driving an unbounded producer (e.g. ``timerSequence(every:clock:)``),
    /// which re-registers a sleeper forever and would never let `run()` return.
    public func run() async {
        while true {
            if let deadline = _lock.withLock({ _state.sleepers.map(\.deadline).min() }) {
                await advance(to: deadline)
                continue
            }
            // No sleeper registered right now. A task just woken by the last `advance` may still be
            // running toward its next sleep, so we can't conclude the clock is idle after a single
            // hop. Yield generously; the moment a new sleeper appears, resume draining. Only when
            // the full budget passes with none registered do we treat the clock as quiescent.
            guard await hasSleeperWithinSettleBudget() else { return }
        }
    }

    /// Yields up to a generous budget, returning `true` as soon as a sleeper registers (so draining
    /// resumes immediately) and `false` if the budget elapses with none — a robust "is the clock
    /// still doing work?" check that tolerates scheduler latency across platforms.
    private func hasSleeperWithinSettleBudget() async -> Bool {
        for _ in 0 ..< 1000 {
            await Task.yield()
            if !_lock.withLock({ _state.sleepers.isEmpty }) { return true }
        }
        return false
    }
}
