# Getting Started

Install Hourglass and write your first deterministic timing test.

## Installation

Add the package to your `Package.swift`:

```swift
.package(url: "https://github.com/luizmb/Hourglass.git", from: "0.6.2")
```

Then add the product to your target:

```swift
.product(name: "Hourglass", package: "Hourglass")
```

## Deterministic timing with `TestClock`

``TestClock`` only advances when you call `advance(by:)`, so timing operators become fully
deterministic — no `sleep`, no wall-clock flakiness.

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
delay, only the passthrough behaviour.

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

``timerSequence(every:clock:)`` emits the current instant at a fixed cadence — real time in
production, virtual time in tests.

```swift
for await instant in timerSequence(every: .seconds(5), clock: ContinuousClock()) {
    print("tick at \(instant)")
}
```

## Operators at a glance

Every operator extends `AsyncStream where Element: Sendable`, returns an `AsyncStream`, and takes a
`Clock`:

- `debounce(for:clock:)` — emit the last value after the stream is idle for the interval
- `delay(for:clock:)` — shift every element forward
- `throttle(for:clock:latest:)` — leading- or trailing-edge rate limiter
- `measureInterval(using:)` — replace each element with the elapsed duration since the previous one
- `collect(every:clock:)` — batch elements into arrays flushed at each window boundary
