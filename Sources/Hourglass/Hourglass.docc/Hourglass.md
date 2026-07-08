# ``Hourglass``

Cross-platform Swift clock utilities and time-based `AsyncStream` operators — with zero runtime
dependencies and fully deterministic testing.

## Overview

Time is the hardest thing to test. `sleep`, wall-clock reads, and timers make tests slow and flaky,
and they leak ambient state into otherwise pure code. Hourglass fixes that by making **time an
injected value**.

It gives you two things:

- **A complete family of clocks** — from the standard library's precise production clocks to
  purpose-built test clocks — all behind the one `Clock` protocol, so you swap real time for virtual
  time without touching your logic.
- **Clock-injected `AsyncStream` operators** (`debounce`, `throttle`, `delay`, `timeout`, `collect`,
  …) that take a `Clock` and therefore run in real time in production and in virtual time in tests.

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

Because every clock conforms to `Clock`, the same call site accepts a live `ContinuousClock` in
production and a `TestClock`/`ImmediateClock` in tests — or an ``AnyClock`` when you want to store one
behind a single type.

It runs on macOS, iOS, tvOS, watchOS, visionOS, Linux, Windows, and Android.

## The clock menu

| Clock | Kind | Use it when |
|---|---|---|
| `ContinuousClock` (stdlib) | Precise, monotonic, counts while suspended | Production timing that must include time the machine slept |
| `SuspendingClock` (stdlib) | Precise, monotonic, pauses while suspended | Production timing that should exclude sleep |
| ``WallClock`` | Real calendar `Date`s | You need actual dates — schedule at a moment, log timestamps — still injectable |
| ``TestClock`` | Virtual, you advance it | Driving timing operators deterministically in tests |
| ``ImmediateClock`` | Virtual, sleeps return at once | Fast tests that care about pass-through, not delay |
| ``UnimplementedClock`` | Fails on use | Asserting a code path never touches time |

See <doc:ChoosingAClock> for the full decision guide.

## Topics

### Getting Started
- <doc:GettingStarted>
- <doc:ChoosingAClock>
- <doc:TestingTimingCode>
- <doc:Operators>

### Controlling Time in Tests
- ``TestClock``
- ``ImmediateClock``

### Production Clocks
- ``WallClock``

### Testing Assertions
- ``UnimplementedClock``

### Type Erasure
- ``AnyClock``

### Timers
- ``timerSequence(every:clock:)``
