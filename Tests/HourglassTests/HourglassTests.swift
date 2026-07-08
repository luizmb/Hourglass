// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import Hourglass
import Testing

// MARK: - Test helpers

final class Collector<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    var values: [T] { lock.withLock { _values } }
    func append(_ value: T) { lock.withLock { _values.append(value) } }
}

final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var current: Int { lock.withLock { _value } }
    @discardableResult
    func increment() -> Int { lock.withLock { _value += 1; return _value } }
}

// Yields enough times for tasks spawned inside other tasks to register their state.
// collect has 3 layers of async indirection under concurrent test load, so 12 yields
// is the safe margin for all operators in this suite.
private func settle() async {
    for _ in 0..<12 {
        await Task.yield()
    }
}

// Polls a condition instead of relying on a fixed yield count — value delivery crosses two
// async hops (the operator's loop and the test's consumer), which can be scheduled late under
// parallel test load. Used for positive "value arrived" assertions.
private func poll(timeoutMs: Int = 2_000, until condition: @Sendable () -> Bool) async {
    for _ in 0..<(timeoutMs / 2) {
        if condition() { return }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
}

// Consumption barrier: waits for already-sent values to be drained into the operator's state
// before the clock is advanced. Used only while the clock has NOT advanced — no timer tick can
// fire yet — so it can't race a flush; it purely ensures the operator has consumed the values
// (e.g. so collect buckets them, or debounce/throttle's pending reflects the latest) before the
// advance triggers a window/flush. Generous and fixed because consumption has no pollable signal.
private func drainSentValues() async {
    for _ in 0..<60 {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

// MARK: - ImmediateClock

@Suite struct ImmediateClockTests {
    @Test func sleepReturnsImmediately() async {
        let clock = ImmediateClock()
        let start = clock.now
        try? await clock.sleep(until: start.advanced(by: .seconds(60)), tolerance: nil)
    }

    @Test func nowAdvancesToSleepDeadline() async {
        let clock = ImmediateClock()
        #expect(clock.now.offset == .zero)
        try? await clock.sleep(until: clock.now.advanced(by: .seconds(5)), tolerance: nil)
        #expect(clock.now.offset == .seconds(5))
        try? await clock.sleep(until: clock.now.advanced(by: .seconds(3)), tolerance: nil)
        #expect(clock.now.offset == .seconds(8))
    }

    @Test func nowStaysMonotonicOnPastDeadline() async {
        let clock = ImmediateClock()
        try? await clock.sleep(until: clock.now.advanced(by: .seconds(10)), tolerance: nil)
        // Sleeping to an earlier instant must not move `now` backwards.
        try? await clock.sleep(until: ImmediateClock.Instant(offset: .seconds(2)), tolerance: nil)
        #expect(clock.now.offset == .seconds(10))
    }

    @Test func measureIntervalSeesElapsedTime() async {
        // With an advancing `now`, measureInterval observes real elapsed time under an ImmediateClock.
        // The per-element gaps telescope, so their sum equals the total advance from subscription to
        // the last element regardless of how the consumer task interleaves — a race-free invariant.
        let clock = ImmediateClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let durations = Collector<Duration>()
        let task = Task {
            for await d in stream.measureInterval(using: clock) {
                durations.append(d)
            }
        }
        await settle() // measureInterval captures its subscription instant (0) before the clock moves
        cont.yield(1)
        try? await clock.sleep(until: clock.now.advanced(by: .seconds(2)), tolerance: nil)
        cont.yield(2)
        cont.finish()
        await task.value
        #expect(durations.values.count == 2)
        #expect(durations.values.reduce(Duration.zero, +) == .seconds(2))
    }

    @Test func delayWithImmediateClockPassesThrough() async {
        var result: [Int] = []
        for await value in AsyncStream.sequence(1...3).delay(for: .seconds(10), clock: ImmediateClock()) {
            result.append(value)
        }
        #expect(result == [1, 2, 3])
    }
}

// MARK: - TestClock

@Suite struct TestClockTests {
    @Test func initialNowIsZero() {
        let clock = TestClock()
        #expect(clock.now.offset == .zero)
    }

    @Test func advanceMovesNow() async {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))
        #expect(clock.now.offset == .seconds(5))
    }

    @Test func advanceToMovesToAbsoluteInstant() async {
        let clock = TestClock()
        await clock.advance(to: .init(offset: .seconds(7)))
        #expect(clock.now.offset == .seconds(7))
    }

    @Test func advanceToIsNoOpWhenNotInFuture() async {
        let clock = TestClock()
        await clock.advance(by: .seconds(5))
        await clock.advance(to: .init(offset: .seconds(2))) // earlier than now
        #expect(clock.now.offset == .seconds(5)) // unchanged, monotonic
    }

    @Test func advanceToWakesSleepersAtOrBeforeDeadline() async {
        let clock = TestClock()
        let awoke = AtomicCounter()
        let task = Task {
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(3)), tolerance: nil)
            awoke.increment()
        }
        await clock.waitForSleepers()
        await clock.advance(to: .init(offset: .seconds(3)))
        await poll { awoke.current >= 1 }
        #expect(awoke.current == 1)
        task.cancel()
    }

    @Test func runDrainsChainedSleeps() async {
        // A task that sleeps three times in a row; run() should exhaust all of them without the
        // test counting individual advances.
        let clock = TestClock()
        let steps = AtomicCounter()
        let task = Task {
            for _ in 0..<3 {
                try? await clock.sleep(until: clock.now.advanced(by: .seconds(1)), tolerance: nil)
                steps.increment()
            }
        }
        await clock.waitForSleepers()
        await clock.run()
        await poll { steps.current >= 3 }
        #expect(steps.current == 3)
        #expect(clock.now.offset == .seconds(3)) // advanced exactly to the last deadline
        task.cancel()
    }

    @Test func runReturnsImmediatelyWhenNoSleepers() async {
        let clock = TestClock()
        await clock.run() // must not hang
        #expect(clock.now.offset == .zero)
    }

    @Test func sleepSuspendsUntilAdvanced() async {
        let clock = TestClock()
        let awoke = AtomicCounter()

        let task = Task {
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(1)), tolerance: nil)
            awoke.increment()
        }

        await clock.waitForSleepers()
        #expect(awoke.current == 0)

        await clock.advance(by: .seconds(1))
        await poll { awoke.current >= 1 }
        #expect(awoke.current == 1)
        task.cancel()
    }

    @Test func advanceWakesMultipleSleepersInOrder() async {
        let clock = TestClock()
        let order = Collector<Int>()

        let t1 = Task {
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(1)), tolerance: nil)
            order.append(1)
        }
        let t2 = Task {
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(2)), tolerance: nil)
            order.append(2)
        }

        await clock.waitForSleepers(count: 2)

        // Cross the deadlines one at a time. A single advance past both would resume t1 and t2
        // in deadline order, but their *bodies* run as independent tasks that the executor can
        // interleave freely — so observing append order from one advance is a race (it flaked
        // as [2, 1]). Stepping per-deadline and draining each wake makes the ordering a property
        // of the clock's deadlines, not of scheduler luck, and also proves t2 stays asleep at 1s.
        await clock.advance(by: .seconds(1))
        await poll { order.values.count >= 1 }
        #expect(order.values == [1])

        await clock.advance(by: .seconds(1))
        await poll { order.values.count >= 2 }
        #expect(order.values == [1, 2])

        t1.cancel(); t2.cancel()
    }
}

// MARK: - timerSequence

@Suite struct TimerSequenceTests {
    @Test func emitsWithImmediateClock() async {
        var count = 0
        for await _ in timerSequence(every: .seconds(1), clock: ImmediateClock()) {
            count += 1
            if count == 3 { break }
        }
        #expect(count == 3)
    }

    @Test func emitsWithTestClock() async {
        let clock = TestClock()
        let instants = Collector<TestClock.Instant>()

        let task = Task {
            for await instant in timerSequence(every: .seconds(1), clock: clock) {
                instants.append(instant)
            }
        }

        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await poll { instants.values.count >= 3 }
        #expect(instants.values.count == 3)
        task.cancel()
    }
}

// MARK: - AsyncSequence+Delay

@Suite struct DelayTests {
    @Test func delayHoldsValuesUntilClockAdvances() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.delay(for: .seconds(1), clock: clock) {
                values.append(v)
            }
        }

        // settle: consumer task starts → creates internalTask → internalTask starts iterating
        await settle()

        cont.yield(1)
        await clock.waitForSleepers() // wait for delay's internal sleep to register
        #expect(values.values.isEmpty)

        await clock.advance(by: .seconds(1))
        await poll { values.values.count >= 1 }
        #expect(values.values == [1])

        cont.finish()
        task.cancel()
    }

    @Test func delayPassesThroughWithImmediateClock() async {
        var result: [Int] = []
        for await v in AsyncStream.sequence(1...3).delay(for: .seconds(10), clock: ImmediateClock()) {
            result.append(v)
        }
        #expect(result == [1, 2, 3])
    }

    @Test func delayPreservesOrderWithoutAccumulating() async {
        // Two elements arrive at the same virtual instant, so both are stamped with the same
        // absolute deadline (t0 + 1s). A single advance fires both — a sequential delay that
        // slept *after* dequeuing would need two advances. Proves the shift never accumulates.
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.delay(for: .seconds(1), clock: clock) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2)
        await drainSentValues()
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await poll { values.values.count >= 2 }
        #expect(values.values == [1, 2])

        cont.finish()
        task.cancel()
    }
}

// MARK: - AsyncSequence+Debounce

@Suite struct DebounceTests {
    @Test func debounceEmitsLastValueAfterQuietPeriod() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.debounce(for: .milliseconds(300), clock: clock) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2); cont.yield(3)
        await drainSentValues() // all 3 consumed → final pendingTask is for value 3
        await clock.waitForSleepers()
        #expect(values.values.isEmpty)

        await clock.advance(by: .milliseconds(300))
        await poll { values.values.count >= 1 }
        #expect(values.values == [3])

        cont.finish()
        task.cancel()
    }

    @Test func debounceResetsTimerOnNewValue() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.debounce(for: .milliseconds(300), clock: clock) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1)
        await clock.waitForSleepers()
        await clock.advance(by: .milliseconds(200))
        await settle()
        #expect(values.values.isEmpty)

        cont.yield(2)
        await drainSentValues() // pendingTask1 cancelled, pendingTask2 (value 2) registered
        await clock.waitForSleepers() // wait for pendingTask2 to register its sleep
        await clock.advance(by: .milliseconds(300))
        await poll { values.values.count >= 1 }
        #expect(values.values == [2])

        cont.finish()
        task.cancel()
    }
}

// MARK: - AsyncSequence+Throttle

@Suite struct ThrottleTests {
    @Test func throttleLeadingEdgeEmitsFirstInWindow() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.throttle(for: .seconds(1), clock: clock, latest: false) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2); cont.yield(3)
        await poll { values.values.count >= 1 }
        #expect(values.values == [1])

        cont.finish()
        task.cancel()
    }

    @Test func throttleTrailingEdgeEmitsLastWhenWindowCloses() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.throttle(for: .seconds(1), clock: clock, latest: true) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2); cont.yield(3)
        await drainSentValues() // all consumed → pending latest is 3, window timer armed
        #expect(values.values.isEmpty) // trailing: nothing until the window closes

        await clock.waitForSleepers() // the window timer has registered its sleep
        await clock.advance(by: .seconds(1)) // close the window → emit the latest (3)
        await poll { values.values.count >= 1 }
        #expect(values.values == [3])

        cont.finish()
        task.cancel()
    }

    @Test func throttleTrailingFlushesPendingOnCompletion() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()

        let task = Task {
            for await v in stream.throttle(for: .seconds(1), clock: clock, latest: true) {
                values.append(v)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2)
        await drainSentValues() // both consumed → pending latest is 2
        cont.finish() // completes before the window closes → flush the pending latest (2)
        await poll { values.values.count >= 1 }
        #expect(values.values == [2])

        task.cancel()
    }
}

// MARK: - AsyncSequence+Collect

@Suite struct CollectByTimeTests {
    @Test func collectGroupsValuesIntoWindows() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let windows = Collector<[Int]>()

        let task = Task {
            for await w in stream.collect(every: .seconds(1), clock: clock) {
                windows.append(w)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2)
        await drainSentValues() // both values bucketed before the tick
        await clock.advance(by: .seconds(1))
        await poll { windows.values.count >= 1 }

        cont.yield(3)
        await drainSentValues() // value 3 bucketed before the next tick
        await clock.advance(by: .seconds(1))
        await poll { windows.values.count >= 2 }

        #expect(windows.values == [[1, 2], [3]])
        cont.finish()
        task.cancel()
    }

    @Test func collectFlushesPartialWindowOnCompletion() async {
        var result: [[Int]] = []
        for await w in AsyncStream.sequence([1, 2, 3]).collect(every: .seconds(10), clock: TestClock()) {
            result.append(w)
        }
        #expect(result == [[1, 2, 3]])
    }

    @Test func collectEmptyWindowsAreSkipped() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let windows = Collector<[Int]>()

        let task = Task {
            for await w in stream.collect(every: .seconds(1), clock: clock) {
                windows.append(w)
            }
        }

        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await settle()
        #expect(windows.values.isEmpty)

        cont.yield(1)
        await drainSentValues() // value 1 bucketed before the next tick
        await clock.advance(by: .seconds(1))
        await poll { windows.values.count >= 1 }
        #expect(windows.values == [[1]])

        cont.finish()
        task.cancel()
    }
}

// MARK: - AsyncStream+Timeout

private struct Timedout: Error, Equatable {}

@Suite struct TimeoutTests {
    @Test func timeoutFailsWhenUpstreamGoesQuiet() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()
        let timeouts = AtomicCounter()

        let task = Task {
            for await result in stream.timeout(.seconds(1), clock: clock, error: { Timedout() }) {
                switch result {
                case let .success(v): values.append(v)
                case .failure: timeouts.increment()
                }
            }
        }

        await clock.waitForSleepers() // initial deadline armed at subscription
        await clock.advance(by: .seconds(1)) // no value arrived → fire
        await poll { timeouts.current >= 1 }
        #expect(values.values.isEmpty)
        #expect(timeouts.current == 1)

        cont.finish()
        task.cancel()
    }

    @Test func timeoutForwardsValuesAndReArmsDeadline() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()
        let timeouts = AtomicCounter()

        let task = Task {
            for await result in stream.timeout(.seconds(1), clock: clock, error: { Timedout() }) {
                switch result {
                case let .success(v): values.append(v)
                case .failure: timeouts.increment()
                }
            }
        }

        await settle()
        cont.yield(1)
        await poll { values.values.count >= 1 }
        #expect(values.values == [1])

        // Re-armed at t0+1s; advancing only partway must not fire.
        await clock.waitForSleepers()
        await clock.advance(by: .milliseconds(500))
        await settle()
        #expect(timeouts.current == 0)

        cont.yield(2)
        await poll { values.values.count >= 2 }
        #expect(values.values == [1, 2])

        // Now stay quiet past the (re-armed) window → fire.
        await clock.waitForSleepers()
        await clock.advance(by: .seconds(1))
        await poll { timeouts.current >= 1 }
        #expect(timeouts.current == 1)

        cont.finish()
        task.cancel()
    }

    @Test func timeoutCompletesNormallyWithoutFailure() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let values = Collector<Int>()
        let timeouts = AtomicCounter()

        let task = Task {
            for await result in stream.timeout(.seconds(1), clock: clock, error: { Timedout() }) {
                switch result {
                case let .success(v): values.append(v)
                case .failure: timeouts.increment()
                }
            }
        }

        await settle()
        cont.yield(1); cont.yield(2)
        await poll { values.values.count >= 2 }
        cont.finish() // completes before the deadline → no failure
        await settle()
        #expect(values.values == [1, 2])
        #expect(timeouts.current == 0)

        task.cancel()
    }
}

// MARK: - AnyClock

@Suite struct AnyClockTests {
    @Test func instantArithmeticIsOffsetBased() {
        let a = AnyClock<Duration>.Instant(offset: .seconds(2))
        let b = a.advanced(by: .seconds(3))
        #expect(b.offset == .seconds(5))
        #expect(a.duration(to: b) == .seconds(3))
        #expect(a < b)
    }

    @Test func nowReflectsUnderlyingAdvance() async {
        let testClock = TestClock()
        let clock = testClock.eraseToAnyClock()
        #expect(clock.now.offset == .zero)
        await testClock.advance(by: .seconds(3))
        #expect(clock.now.offset == .seconds(3))
    }

    @Test func originIsCapturedAtErasureNotZero() async {
        let testClock = TestClock()
        await testClock.advance(by: .seconds(10)) // wrapped clock already at 10s
        let clock = testClock.eraseToAnyClock() // origin captured here
        #expect(clock.now.offset == .zero) // measured relative to erasure
        await testClock.advance(by: .seconds(4))
        #expect(clock.now.offset == .seconds(4))
    }

    @Test func sleepWakesWhenUnderlyingAdvancesPastDeadline() async {
        let testClock = TestClock()
        let clock = testClock.eraseToAnyClock()
        let woke = AtomicCounter()
        let task = Task {
            try? await clock.sleep(for: .seconds(2))
            woke.increment()
        }
        await testClock.waitForSleepers() // the erased sleep registered in the wrapped clock
        #expect(woke.current == 0)
        await testClock.advance(by: .seconds(2))
        await poll { woke.current == 1 }
        #expect(woke.current == 1)
        task.cancel()
    }

    @Test func immediateClockSleepReturnsImmediatelyButAdvancesNow() async {
        let clock = ImmediateClock().eraseToAnyClock()
        try? await clock.sleep(for: .seconds(60)) // returns at once, but virtual time advances
        #expect(clock.now.offset == .seconds(60))
    }

    // Proves AnyClock is a drop-in `C: Clock & Sendable` for the timing operators: drive a
    // `delay` through an erased TestClock by advancing the wrapped clock.
    @Test func erasedClockDrivesDelayOperator() async {
        let testClock = TestClock()
        let clock = testClock.eraseToAnyClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let out = Collector<Int>()
        let task = Task {
            for await v in stream.delay(for: .seconds(1), clock: clock) {
                out.append(v)
            }
        }
        await settle()
        cont.yield(1)
        await drainSentValues()
        #expect(out.values.isEmpty) // held until the deadline
        await testClock.advance(by: .seconds(1))
        await poll { out.values.count == 1 }
        #expect(out.values == [1])
        cont.finish()
        task.cancel()
    }
}

// MARK: - WallClock

@Suite struct WallClockTests {
    private let epoch = Date(timeIntervalSince1970: 0)

    @Test func nowReflectsInjectedProvider() {
        let fixed = Date(timeIntervalSince1970: 1_000)
        let clock = WallClock(now: { fixed })
        #expect(clock.now.date == fixed)
    }

    @Test func instantArithmeticMapsToDates() {
        let start = WallClock.Instant(epoch)
        let later = start.advanced(by: .seconds(90))
        #expect(later.date == epoch.addingTimeInterval(90))
        #expect(start.duration(to: later) == .seconds(90))
        #expect(start < later)
    }

    @Test func instantArithmeticPreservesSubsecondPrecision() {
        let start = WallClock.Instant(epoch)
        let later = start.advanced(by: .milliseconds(250))
        #expect(later.date == epoch.addingTimeInterval(0.25))
    }

    @Test func sleepToPastReturnsImmediately() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let clock = WallClock(now: { now })
        // Deadline already behind `now` → no real waiting.
        try? await clock.sleep(until: clock.now.advanced(by: .seconds(-5)), tolerance: nil)
    }

    @Test func sleepWaitsRealTimeForFutureDeadline() async {
        let clock = WallClock() // live system clock
        let start = ContinuousClock().now
        try? await clock.sleep(until: clock.now.advanced(by: .milliseconds(20)), tolerance: nil)
        let elapsed = ContinuousClock().now - start
        #expect(elapsed >= .milliseconds(10)) // actually waited (generous lower bound)
    }
}

// MARK: - UnimplementedClock

@Suite struct UnimplementedClockTests {
    @Test func reportsWhenNowIsRead() {
        let messages = Collector<String>()
        let clock = UnimplementedClock("must not read time") { messages.append($0) }
        _ = clock.now
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("now"))
        #expect(messages.values[0].contains("must not read time"))
    }

    @Test func reportsWhenMinimumResolutionIsRead() {
        let messages = Collector<String>()
        let clock = UnimplementedClock { messages.append($0) }
        _ = clock.minimumResolution
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("minimumResolution"))
    }

    @Test func reportsWhenSleepIsCalledThenReturns() async {
        let messages = Collector<String>()
        let clock = UnimplementedClock { messages.append($0) }
        try? await clock.sleep(until: .init(), tolerance: nil) // must not hang
        #expect(messages.values.count == 1)
        #expect(messages.values[0].contains("sleep"))
    }

    @Test func doesNotReportWhenUntouched() {
        let messages = Collector<String>()
        _ = UnimplementedClock { messages.append($0) }
        #expect(messages.values.isEmpty)
    }
}

// MARK: - Clock.timer convenience

@Suite struct ClockTimerConvenienceTests {
    @Test func timerMethodEmitsLikeTimerSequence() async {
        var count = 0
        for await _ in ImmediateClock().timer(every: .seconds(1)) {
            count += 1
            if count == 3 { break }
        }
        #expect(count == 3)
    }
}

// MARK: - AsyncStream+CollectByTimeOrCount

@Suite struct CollectByTimeOrCountTests {
    @Test func flushesWhenCountReachedBeforeTime() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let windows = Collector<[Int]>()

        let task = Task {
            for await w in stream.collect(every: .seconds(10), orCount: 3, clock: clock) {
                windows.append(w)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2); cont.yield(3) // count reached — flush without advancing the clock
        await poll { windows.values.count >= 1 }
        #expect(windows.values == [[1, 2, 3]])

        cont.finish()
        task.cancel()
    }

    @Test func flushesByTimeWhenCountNotReached() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let windows = Collector<[Int]>()

        let task = Task {
            for await w in stream.collect(every: .seconds(1), orCount: 5, clock: clock) {
                windows.append(w)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2)
        await drainSentValues()
        await clock.advance(by: .seconds(1))
        await poll { windows.values.count >= 1 }
        #expect(windows.values == [[1, 2]])

        cont.finish()
        task.cancel()
    }

    @Test func countFlushResetsTheTimeWindow() async {
        let clock = TestClock()
        let (stream, cont) = AsyncStream<Int>.makeStream()
        let windows = Collector<[Int]>()

        let task = Task {
            for await w in stream.collect(every: .seconds(1), orCount: 3, clock: clock) {
                windows.append(w)
            }
        }

        await settle()
        cont.yield(1); cont.yield(2); cont.yield(3) // count flush -> [1,2,3], window resets
        await poll { windows.values.count >= 1 }

        cont.yield(4) // partial window
        await drainSentValues()
        await clock.advance(by: .seconds(1)) // time flush -> [4]
        await poll { windows.values.count >= 2 }
        #expect(windows.values == [[1, 2, 3], [4]])

        cont.finish()
        task.cancel()
    }
}
