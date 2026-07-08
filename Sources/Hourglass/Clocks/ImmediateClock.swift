// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A clock whose `sleep` returns immediately but whose `now` still advances.
///
/// Every `sleep(until:)` returns at once — no real wall-clock delay — yet the clock jumps its
/// `now` forward to the sleep's deadline. Virtual time therefore *accumulates* across sleeps even
/// though nothing waits, so operators that read the clock (`measureInterval(using:)`,
/// ``timerSequence(every:clock:)``) still observe meaningful, monotonically increasing instants.
///
/// Use it for fast tests where you care about an operator's pass-through behaviour and its notion
/// of elapsed time, but not about real delays. When you need to control *when* sleeps wake (rather
/// than have them all resolve instantly), use ``TestClock`` instead.
///
/// `@unchecked Sendable`: the only mutable state is `_now`, guarded by `_lock` on every access; a
/// reference type is required because `Clock.sleep` is non-mutating yet must move `now` forward.
public final class ImmediateClock: Clock, @unchecked Sendable {
    public typealias Duration = Swift.Duration

    public struct Instant: InstantProtocol, Sendable, Hashable {
        public var offset: Duration

        public init(offset: Duration = .zero) { self.offset = offset }

        public func advanced(by duration: Duration) -> Self { .init(offset: offset + duration) }
        public func duration(to other: Self) -> Duration { other.offset - offset }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private let _lock = NSLock()
    private var _now: Instant

    /// Creates an immediate clock starting at `offset` (default: zero).
    public init(offset: Duration = .zero) { _now = Instant(offset: offset) }

    public var now: Instant { _lock.withLock { _now } }
    public var minimumResolution: Duration { .zero }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        // Jump forward to the deadline without waiting. `max` keeps `now` monotonic even if a
        // caller sleeps to an instant in the past.
        _lock.withLock { _now = Swift.max(_now, deadline) }
    }
}
