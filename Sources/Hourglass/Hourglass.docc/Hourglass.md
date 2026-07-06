# ``Hourglass``

Cross-platform Swift clock utilities and time-based `AsyncStream` operators — with zero runtime
dependencies and fully deterministic testing.

## Overview

Hourglass gives you two things: **test clocks** that make timing deterministic, and a set of
**clock-injected `AsyncStream` operators** (`debounce`, `throttle`, `delay`, `collect`, …). Because
every operator takes a `Clock`, you drive real time in production and virtual time in tests — no
`sleep`, no flakiness.

```swift
import Hourglass

let clock = TestClock()
let (stream, cont) = AsyncStream<Int>.makeStream()

let task = Task {
    for await value in stream.debounce(for: .milliseconds(300), clock: clock) {
        print(value)   // receives 3 — the last value before the idle window elapsed
    }
}

cont.yield(1); cont.yield(2); cont.yield(3)
await clock.advance(by: .milliseconds(300))
```

It runs on macOS, iOS, tvOS, watchOS, visionOS, Linux, Windows, and Android.

## Topics

### Getting Started
- <doc:GettingStarted>

### Test Clocks
- ``ImmediateClock``
- ``TestClock``

### Timers & Operators
- ``timerSequence(every:clock:)``
