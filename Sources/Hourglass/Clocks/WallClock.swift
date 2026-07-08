// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A `Clock` whose instants are real wall-clock `Date`s.
///
/// The standard library's `ContinuousClock` and `SuspendingClock` are precise and monotonic, but
/// their instants are opaque — you cannot recover a calendar `Date` from them. `WallClock` fills
/// that gap: its ``Instant`` wraps a `Date`, so you can schedule against and log real calendar
/// moments while keeping the clock injectable and testable.
///
/// ## Purity
///
/// Reading the system clock is an effect. Rather than call `Date()` ambiently, `WallClock` takes a
/// `now` provider — the one place the effect lives. Production uses the default (the system clock);
/// tests inject a fixed or scripted `() -> Date` for full determinism:
///
/// ```swift
/// // Production
/// let clock = WallClock()
///
/// // Test — time is whatever you say it is
/// var t = Date(timeIntervalSince1970: 0)
/// let clock = WallClock(now: { t })
/// ```
///
/// ## Sleeping
///
/// `sleep(until:)` measures the interval from `now` to the deadline and waits it out on a monotonic
/// `ContinuousClock`, so an in-flight sleep is unaffected by system-clock adjustments (NTP steps,
/// the user changing the date). A deadline already in the past returns immediately.
public struct WallClock: Clock, Sendable {
    public typealias Duration = Swift.Duration

    /// A wall-clock instant: a wrapper around a Foundation `Date`.
    public struct Instant: InstantProtocol, Sendable, Hashable {
        /// The wrapped calendar date.
        public var date: Date

        public init(_ date: Date) { self.date = date }

        public func advanced(by duration: Duration) -> Self {
            .init(date.addingTimeInterval(duration.timeInterval))
        }

        public func duration(to other: Self) -> Duration {
            .seconds(other.date.timeIntervalSince(date))
        }

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.date < rhs.date }
    }

    private let _now: @Sendable () -> Date

    /// Creates a wall clock.
    ///
    /// - Parameter now: The system-clock read, isolated here as the clock's only effect. Defaults
    ///   to the live system clock; inject a controlled closure in tests.
    public init(now: @escaping @Sendable () -> Date = { Date() }) { _now = now }

    public var now: Instant { .init(_now()) }
    public var minimumResolution: Duration { .nanoseconds(1) }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let remaining = now.duration(to: deadline)
        guard remaining > .zero else {
            try Task.checkCancellation()
            return
        }
        // Wait the measured interval on a monotonic clock so system-clock changes mid-sleep don't
        // stretch or collapse the wait.
        try await ContinuousClock().sleep(for: remaining, tolerance: tolerance)
    }
}

private extension Duration {
    /// This duration as a `TimeInterval` (seconds), combining the whole-second and attosecond
    /// components so sub-second precision survives the conversion to `Date` arithmetic.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) * 1e-18
    }
}
