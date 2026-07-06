// SPDX-License-Identifier: Apache-2.0

/// A type-erased `Clock` that hides the concrete clock and its `Instant` type, keeping only the
/// `Duration` visible.
///
/// `Clock` has *two* associated types — `Instant` and `Duration` — and `Instant` is itself
/// constrained to `InstantProtocol`. That makes `any Clock` nearly useless: it erases `Duration`,
/// so you can't `sleep(for: .seconds(1))` or compare two instants' separation in a concrete unit.
///
/// `AnyClock` resolves this the way `AnySchedulerOf` does for Combine schedulers: it fixes
/// `Duration` as the single generic parameter and supplies its **own** canonical `Instant` —
/// a `Duration`-offset from the moment the wrapped clock was erased. Any conforming clock whose
/// `Duration` matches can be erased into it, regardless of its native `Instant`:
///
/// ```swift
/// let live: AnyClock<Duration> = ContinuousClock().eraseToAnyClock()
/// let test: AnyClock<Duration> = TestClock().eraseToAnyClock()   // same type — swappable
/// try await live.sleep(for: .milliseconds(300))
/// ```
///
/// Because `ContinuousClock`, `TestClock`, and `ImmediateClock` each declare a *distinct* nested
/// `Instant`, you cannot unify them by fixing `Instant`; you can only fix `Duration`. `AnyClock`
/// captures `origin = base.now` at erasure and translates every instant to/from an offset against
/// it, so `now`, `sleep`, and instant arithmetic all route back to the wrapped clock faithfully.
public struct AnyClock<Duration: DurationProtocol & Hashable & Sendable>: Clock, Sendable {
    /// `AnyClock`'s canonical instant: a `Duration` offset measured from the wrapped clock's
    /// `now` at the moment of erasure. Monotonic whenever the underlying clock is.
    public struct Instant: InstantProtocol, Sendable, Hashable {
        /// Offset from the erasure origin. Two `AnyClock` instants are only comparable when they
        /// come from the same erased clock.
        public var offset: Duration

        public init(offset: Duration) { self.offset = offset }

        public func advanced(by duration: Duration) -> Self { .init(offset: offset + duration) }
        public func duration(to other: Self) -> Duration { other.offset - offset }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private let _now: @Sendable () -> Instant
    private let _minimumResolution: @Sendable () -> Duration
    private let _sleep: @Sendable (Instant, Duration?) async throws -> Void

    /// Erases `base`, capturing its current instant as the offset origin.
    ///
    /// - Parameter base: Any `Sendable` clock whose `Duration` matches this `AnyClock`'s.
    public init<Base: Clock & Sendable>(_ base: Base) where Base.Duration == Duration {
        let origin = base.now
        _now = { Instant(offset: origin.duration(to: base.now)) }
        _minimumResolution = { base.minimumResolution }
        _sleep = { deadline, tolerance in
            try await base.sleep(until: origin.advanced(by: deadline.offset), tolerance: tolerance)
        }
    }

    public var now: Instant { _now() }
    public var minimumResolution: Duration { _minimumResolution() }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await _sleep(deadline, tolerance)
    }
}

public extension Clock where Self: Sendable {
    /// Erases this clock into an ``AnyClock`` keyed on its `Duration`.
    ///
    /// Lets call sites store or pass a concrete clock without leaking its type — swap a live
    /// `ContinuousClock` for a `TestClock`/`ImmediateClock` of the same `Duration` behind one type.
    func eraseToAnyClock() -> AnyClock<Duration> where Duration: Hashable { AnyClock(self) }
}
