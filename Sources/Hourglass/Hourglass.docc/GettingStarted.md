# Getting Started

Install Hourglass and write your first deterministic timing test.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/luizmb/Hourglass.git", from: "1.0.1")
```

Then add the product to your target:

```swift
.product(name: "Hourglass", package: "Hourglass")
```

## The idea: inject the clock

Every timing API in Hourglass takes a `Clock`. In production you pass a real one
(`ContinuousClock`); in tests you pass a virtual one. Your logic never changes — only the clock does.

```swift
func liveTicks() -> AsyncStream<ContinuousClock.Instant> {
    timerSequence(every: .seconds(1), clock: ContinuousClock())
}
```

Swapping in a ``TestClock`` at the call site makes that exact code deterministic. See
<doc:ChoosingAClock> for which clock to reach for.

## Deterministic timing with `TestClock`

``TestClock`` only advances when you call `advance(by:)` (or `advance(to:)`, or `run()`), so timing
operators become fully deterministic — no `sleep`, no wall-clock flakiness.

```swift
import Hourglass
import Testing

@Test func debounceEmitsLastValue() async {
    let clock = TestClock()
    let (stream, cont) = AsyncStream<Int>.makeStream()

    let task = Task {
        for await value in stream.debounce(for: .milliseconds(300), clock: clock) {
            #expect(value == 3)   // last value before the idle window elapsed
        }
    }

    cont.yield(1); cont.yield(2); cont.yield(3)
    await Task.yield()
    await clock.advance(by: .milliseconds(300))
    await Task.yield()

    cont.finish()
    task.cancel()
}
```

## Fast tests with `ImmediateClock`

``ImmediateClock`` makes every `sleep` return immediately — perfect when you don't care about the
delay, only the passthrough behaviour. Its `now` still advances to each sleep's deadline, so elapsed
time stays meaningful.

```swift
@Test func delayPassesThroughImmediately() async {
    var result: [Int] = []
    for await v in AsyncStream.sequence(1...3).delay(for: .seconds(10), clock: ImmediateClock()) {
        result.append(v)
    }
    #expect(result == [1, 2, 3])
}
```

## Timers

``timerSequence(every:clock:)`` (or the method form `clock.timer(every:)`) emits the current instant
at a fixed cadence — real time in production, virtual time in tests.

```swift
for await instant in timerSequence(every: .seconds(5), clock: ContinuousClock()) {
    print("tick at \(instant)")
}
```

## Next steps

- <doc:ChoosingAClock> — pick the right clock for the job
- <doc:TestingTimingCode> — patterns for driving virtual time and asserting on it
- <doc:Operators> — every operator, with examples and timing semantics
