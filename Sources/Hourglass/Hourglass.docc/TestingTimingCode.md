# Testing Timing Code

Drive virtual time and assert on it — deterministically, with no `sleep`.

## Overview

Timing tests fail in two directions: they're *slow* (real `sleep`s add up) and *flaky* (wall-clock
races). Hourglass removes both by letting you advance a virtual clock explicitly. This article
collects the patterns that make those tests reliable.

## Advancing the clock

``TestClock`` starts at zero and only moves when you advance it. Three ways to move it:

```swift
let clock = TestClock()

await clock.advance(by: .seconds(1))              // relative
await clock.advance(to: .init(offset: .seconds(5))) // absolute (monotonic; no-op if already past)
await clock.run()                                  // exhaust all pending sleeps
```

Use `advance(by:)` to step through windows one at a time (the clearest way to assert *when* things
happen). Use `run()` when a task chains several sleeps and you just want them all to complete:

```swift
@Test func drainsChainedSleeps() async {
    let clock = TestClock()
    let steps = Counter()
    let task = Task {
        for _ in 0..<3 {
            try? await clock.sleep(until: clock.now.advanced(by: .seconds(1)), tolerance: nil)
            steps.increment()
        }
    }
    await clock.waitForSleepers()
    await clock.run()            // all three sleeps resolve
    #expect(steps.current == 3)
}
```

> Don't call `run()` on a clock driving an unbounded producer like ``timerSequence(every:clock:)`` —
> it re-registers a sleeper forever, so `run()` would never return. Step it with `advance(by:)`.

## Avoiding races: `waitForSleepers`

Operators register their sleeps asynchronously. If you advance the clock *before* the operator has
gone to sleep, the tick is missed. ``TestClock/waitForSleepers(count:)`` suspends until the expected
number of tasks are sleeping, so advancing is deterministic:

```swift
cont.yield(1)
await clock.waitForSleepers()      // the operator's timer is now registered
await clock.advance(by: .seconds(1))
```

## Asserting emissions safely

Collect emitted values in a small locked box and poll for the expected count rather than assuming
instant delivery — value delivery crosses async hops:

```swift
final class Box<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock(); private var items: [T] = []
    var values: [T] { lock.withLock { items } }
    func append(_ x: T) { lock.withLock { items.append(x) } }
}
```

## Fast pass-through with `ImmediateClock`

When you only care that values flow through an operator (not the delay), ``ImmediateClock`` returns
from every `sleep` at once — no advancing needed:

```swift
@Test func passesThrough() async {
    var out: [Int] = []
    for await v in AsyncStream.sequence(1...3).delay(for: .seconds(10), clock: ImmediateClock()) {
        out.append(v)
    }
    #expect(out == [1, 2, 3])
}
```

Because its `now` advances to each deadline, `measureInterval(using:)` still reports real elapsed
durations under an `ImmediateClock`.

## Proving a path never sleeps with `UnimplementedClock`

Sometimes the assertion is *negative*: this branch must not consult time at all (a cache hit, a
short-circuit). Inject an ``UnimplementedClock`` wired to your test framework — any use fails the
test:

```swift
import Testing

@Test func cacheHitDoesNotSleep() async {
    let clock = UnimplementedClock("cache hit must not sleep") { message in
        Issue.record(Comment(rawValue: message))
    }
    _ = await subject.value(using: clock)   // reads cache; never touches the clock
}
```

The reporter is injected on purpose: the library imports no test framework, so it stays dependency-
free and portable to Linux, Windows, and Android. Wire `onUse` to `Issue.record` (Swift Testing) or
`XCTFail` (XCTest) at the call site.

## Deterministic dates with `WallClock`

For code that reads calendar dates, inject the `now` provider instead of calling `Date()`:

```swift
var clock = Date(timeIntervalSince1970: 1_700_000_000)
let wall = WallClock(now: { clock })
#expect(wall.now.date == clock)
```
