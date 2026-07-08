// SPDX-License-Identifier: Apache-2.0

/// A `Clock` that reports a failure the moment any of its members is touched.
///
/// Use it to prove that a code path never consults time — that a branch does not sleep, poll `now`,
/// or otherwise depend on a clock. Inject an `UnimplementedClock` where you expect *no* timing to
/// happen; if the code reads `now`/`minimumResolution` or calls `sleep`, the injected reporter
/// fires with a describing message.
///
/// ## Reporting
///
/// To stay dependency-free and portable (Linux, Windows, Android), the clock does not import any
/// test framework. Instead you inject the reporter — wire it to your test framework at the call
/// site. With Swift Testing:
///
/// ```swift
/// import Testing
///
/// let clock = UnimplementedClock("payment path must not sleep") { message in
///     Issue.record(Comment(rawValue: message))
/// }
/// ```
///
/// `sleep` reports and then returns immediately (it never hangs or traps), so a stray timing call
/// surfaces as a recorded issue without deadlocking the test.
public struct UnimplementedClock: Clock, Sendable {
    public typealias Duration = Swift.Duration

    /// A never-advancing instant, structurally identical to the other Hourglass clocks' instants.
    public struct Instant: InstantProtocol, Sendable, Hashable {
        public var offset: Duration

        public init(offset: Duration = .zero) { self.offset = offset }

        public func advanced(by duration: Duration) -> Self { .init(offset: offset + duration) }
        public func duration(to other: Self) -> Duration { other.offset - offset }
        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    }

    private let label: String
    private let fileID: StaticString
    private let line: UInt
    private let onUse: @Sendable (String) -> Void

    /// Creates an unimplemented clock.
    ///
    /// - Parameters:
    ///   - label: A short description of the expectation (e.g. "must not sleep"), included in the
    ///     failure message.
    ///   - fileID: Source location captured for the message. Leave as the default.
    ///   - line: Source location captured for the message. Leave as the default.
    ///   - onUse: Invoked with a describing message whenever a clock member is used. Wire it to
    ///     your test framework (e.g. `Issue.record`).
    public init(
        _ label: String = "",
        fileID: StaticString = #fileID,
        line: UInt = #line,
        onUse: @escaping @Sendable (String) -> Void
    ) {
        self.label = label
        self.fileID = fileID
        self.line = line
        self.onUse = onUse
    }

    private func report(_ member: String) {
        let suffix = label.isEmpty ? "" : " — \(label)"
        onUse("UnimplementedClock.\(member) was used at \(fileID):\(line)\(suffix)")
    }

    public var now: Instant {
        report("now")
        return .init()
    }

    public var minimumResolution: Duration {
        report("minimumResolution")
        return .zero
    }

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        report("sleep(until:tolerance:)")
        try Task.checkCancellation()
    }
}
