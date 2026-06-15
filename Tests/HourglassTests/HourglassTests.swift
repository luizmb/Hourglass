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
    for _ in 0..<12 { await Task.yield() }
}

// MARK: - ImmediateClock

@Suite struct ImmediateClockTests {
    @Test func sleepReturnsImmediately() async {
        let clock = ImmediateClock()
        let start = clock.now
        try? await clock.sleep(until: start.advanced(by: .seconds(60)), tolerance: nil)
    }

    @Test func nowIsAlwaysZero() {
        let clock = ImmediateClock()
        #expect(clock.now.offset == .zero)
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
        await settle()
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
        await clock.advance(by: .seconds(2))
        await settle()

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
        await settle()
        task.cancel()

        #expect(instants.values.count == 3)
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
        await clock.waitForSleepers()  // wait for delay's internal sleep to register
        #expect(values.values.isEmpty)

        await clock.advance(by: .seconds(1))
        await settle()
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
        await settle()  // outer task processes all 3 values and creates final pendingTask
        await clock.waitForSleepers()
        #expect(values.values.isEmpty)

        await clock.advance(by: .milliseconds(300))
        await settle()
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
        await settle()  // outer task cancels pendingTask1 (removes from sleepers) and creates pendingTask2
        await clock.waitForSleepers()  // wait for pendingTask2 to register its sleep
        await clock.advance(by: .milliseconds(300))
        await settle()
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
        await settle()
        #expect(values.values == [1])

        cont.finish()
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
        await settle()  // let collect task group pick up both values into the bucket
        await clock.advance(by: .seconds(1))
        await settle()

        cont.yield(3)
        await settle()  // let collect task group pick up value 3
        await clock.advance(by: .seconds(1))
        await settle()

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
        await settle()  // let collect task group pick up value 1 before next tick
        await clock.advance(by: .seconds(1))
        await settle()
        #expect(windows.values == [[1]])

        cont.finish()
        task.cancel()
    }
}
