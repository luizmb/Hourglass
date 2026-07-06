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

**`ImmediateClock`** — A `Clock` whose `sleep` returns immediately. Use in tests for operators that call timing APIs where you don't want real wall-clock delays.

**`TestClock`** — A `Clock` whose time only advances when you call `advance(by:)`. Use to drive timing operators deterministically in tests without `sleep` or `Task.sleep`.

### Timer

**`timerSequence(every:clock:)`** — Returns an `AsyncStream<C.Instant>` that emits the current clock instant at a fixed cadence. The stream runs until cancelled.

### `AsyncStream` operators

All operators extend `AsyncStream where Element: Sendable` and return `AsyncStream<_>` — pure, non-throwing passthrough timing. (Errors, if you model them, ride along as values in `Element`, e.g. `AsyncStream<Result<T, E>>`, and you compose terminal/error handling separately.) They are clock-injected — pass any `Clock` conformer (including `TestClock`) to make behaviour fully deterministic in tests.

| Operator | Description |
|---|---|
| `debounce(for:clock:)` | Emits the last value after the upstream is idle for `interval` |
| `delay(for:clock:)` | Shifts every element forward by `interval` |
| `throttle(for:clock:latest:)` | Leading edge (`latest: false`) or trailing edge (`latest: true`) rate-limiter |
| `measureInterval(using:)` | Replaces each element with elapsed duration since the previous one |
| `collect(every:clock:)` | Groups elements into arrays, flushed at each window boundary |

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/luizmb/Hourglass.git", from: "0.6.2")

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
