# Hourglass

[![CI](https://github.com/luizmb/Hourglass/actions/workflows/ci.yml/badge.svg)](https://github.com/luizmb/Hourglass/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-online-blue)](https://ios.lu/Hourglass)
[![Swift 6.3+](https://img.shields.io/badge/swift-6.3%2B-orange)](https://swift.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)

**[→ Full API Documentation](https://ios.lu/Hourglass)** · [Installation](#installation)

Cross-platform Swift clock utilities and time-based `AsyncStream` operators.

Zero dependencies beyond the Swift standard library and Foundation. Supports macOS, iOS, tvOS, watchOS, visionOS, Linux, Windows, and Android.

---

## What's inside

### Clocks

A complete family behind the standard `Clock` protocol, so one call site takes real time in production
and virtual time in tests.

| Clock | Kind | Use it when |
|---|---|---|
| `ContinuousClock` / `SuspendingClock` (stdlib) | Precise, monotonic | Production timing (counts through / pauses on device sleep) |
| **`WallClock`** | Real calendar `Date`s, injectable `() -> Date` | You need actual dates — schedule at a moment, log timestamps — still testable |
| **`TestClock`** | Virtual — you advance it | Driving timing operators deterministically in tests |
| **`ImmediateClock`** | Virtual — `sleep` returns at once, `now` still advances | Fast tests that care about pass-through, not delay |
| **`UnimplementedClock`** | Reports a failure on any use | Asserting a code path never touches time |
| **`AnyClock<Duration>`** | Type-erased | Hiding the concrete clock behind one swappable type |

`TestClock` advances via `advance(by:)`, `advance(to:)` (absolute), or `run()` (exhaust all pending
sleeps); `waitForSleepers(count:)` avoids races before advancing.

### Timer

**`timerSequence(every:clock:)`** (or the method form `clock.timer(every:)`) — Returns an
`AsyncStream<C.Instant>` that emits the current clock instant at a fixed cadence. The stream runs until
cancelled.

### `AsyncStream` operators

All operators extend `AsyncStream where Element: Sendable` and return `AsyncStream<_>` — pure, non-throwing passthrough timing. (Errors, if you model them, ride along as values in `Element`, e.g. `AsyncStream<Result<T, E>>`, and you compose terminal/error handling separately.) They are clock-injected — pass any `Clock` conformer (including `TestClock`) to make behaviour fully deterministic in tests.

| Operator | Description |
|---|---|
| `debounce(for:clock:)` | Emits the last value after the upstream is idle for `interval` |
| `delay(for:clock:)` | Shifts every element forward by `interval` |
| `throttle(for:clock:latest:)` | Leading edge (`latest: false`) or trailing edge (`latest: true`) rate-limiter |
| `timeout(_:clock:error:)` | Fails (as a typed `Result` value) if the upstream goes quiet for `interval` |
| `measureInterval(using:)` | Replaces each element with elapsed duration since the previous one |
| `collect(every:clock:)` | Groups elements into arrays, flushed at each window boundary |
| `collect(every:orCount:clock:)` | Flushes on the window **or** when the buffer reaches `count`, whichever first |

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/Hourglass.git", from: "1.0.0")

// target dependency
.product(name: "Hourglass", package: "Hourglass")
```

---

## Usage

### TestClock — deterministic timing tests

```swift
import Hourglass
import Testing

@Test func debounceEmitsLastValue() async {
    let clock = TestClock()
    let (stream, cont) = AsyncStream<Int>.makeStream()

    let task = Task {
        for await value in stream.debounce(for: .milliseconds(300), clock: clock) {
            // receives 3, not 1 or 2
            #expect(value == 3)
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

### ImmediateClock — fast tests

```swift
@Test func delayPassesThroughImmediately() async {
    var result: [Int] = []
    for await v in AsyncStream.sequence(1...3).delay(for: .seconds(10), clock: ImmediateClock()) {
        result.append(v)
    }
    #expect(result == [1, 2, 3])
}
```

### timerSequence — clock-injected intervals

```swift
// Production: real time
for await instant in timerSequence(every: .seconds(5), clock: ContinuousClock()) {
    print("tick at \(instant)")
}

// Tests: deterministic
let clock = TestClock()
let task = Task {
    for await _ in timerSequence(every: .seconds(1), clock: clock) {
        // handle tick
    }
}
await clock.advance(by: .seconds(3)) // fires 3 ticks
task.cancel()
```

### collect(every:clock:) — time-windowed batching

```swift
let clock = TestClock()
let (events, cont) = AsyncStream<String>.makeStream()

let task = Task {
    for await batch in events.collect(every: .seconds(1), clock: clock) {
        print(batch) // prints ["a", "b"] then ["c"]
    }
}

cont.yield("a"); cont.yield("b")
await clock.advance(by: .seconds(1))
cont.yield("c")
await clock.advance(by: .seconds(1))
cont.finish()
task.cancel()
```

### timeout — fail as a typed value when upstream stalls

```swift
struct Timedout: Error {}

for await result in stream.timeout(.seconds(5), clock: ContinuousClock(), error: { Timedout() }) {
    switch result {
    case let .success(value): handle(value)
    case .failure:            showStalledUI()   // no `try`/`catch` — the error is a value
    }
}
```

### collect(every:orCount:) — batch by time OR size

```swift
// Flush at most 50 events, or once a second — whichever comes first.
for await batch in events.collect(every: .seconds(1), orCount: 50, clock: ContinuousClock()) {
    upload(batch)
}
```

### WallClock — injectable calendar time

```swift
// Production: the system clock
let clock = WallClock()

// Test: pin time to whatever you want — no ambient Date()
var now = Date(timeIntervalSince1970: 0)
let fake = WallClock(now: { now })
```

### UnimplementedClock — assert a path never touches time

```swift
import Testing

let clock = UnimplementedClock("cache hit must not sleep") { message in
    Issue.record(Comment(rawValue: message))   // wired to your test framework at the call site
}
```

See the [documentation](https://ios.lu/Hourglass) for the **Choosing a Clock** and **Testing Timing
Code** guides, and the interactive **Debouncing with a Test Clock** tutorial.

---

## Platform support

| Platform | Minimum |
|---|---|
| macOS | 13.0 |
| iOS | 16.0 |
| tvOS | 16.0 |
| watchOS | 9.0 |
| visionOS | 1.0 |
| Linux | Swift 6.0+ toolchain |
| Windows | Swift 6.0+ toolchain |
| Android | Swift 6.0+ toolchain |

Minimum Apple targets are set by the `Clock` protocol (Swift 5.7 / Xcode 14).

---

## License

Licensed under the Apache License 2.0. See [LICENSE](LICENSE) for details.
