# Operators

Time-based `AsyncStream` operators, each with a runnable example and its timing semantics.

## Overview

Every operator extends `AsyncStream where Element: Sendable`, returns an `AsyncStream`, and takes a
`Clock` — so the same pipeline runs in real time in production and in virtual time in tests. The
operators are pure, non-throwing passthroughs: they never `throw`. When you need to model failure,
carry it as a value in `Element` (e.g. `AsyncStream<Result<T, E>>`) — which is exactly what
`timeout(_:clock:error:)` does.

The examples below use ``TestClock`` and elide the test scaffolding (collecting values, polling);
see <doc:TestingTimingCode> for the full harness.

## debounce

`debounce(for:clock:)` waits until the upstream is idle for `interval`, then emits the
**last** value seen. Each new value resets the timer — so a burst collapses to one emission.

```swift
for await v in stream.debounce(for: .milliseconds(300), clock: clock) {
    // after 300ms of silence, receives only the most recent value
}
```

Use it for search-as-you-type, resize handlers, or any "settle before acting" behaviour.

## throttle

`throttle(for:clock:latest:)` rate-limits to at most one value per `interval` window.

- `latest: false` (**leading edge**) — emit the first value of each window immediately; drop the
  rest of the window.
- `latest: true` (**trailing edge**) — emit the most recent value when the window *closes*. The
  close is driven by the clock, so it fires even if no further value arrives; a value still pending
  when the upstream completes is flushed.

```swift
// Leading: react instantly, then ignore for a second
stream.throttle(for: .seconds(1), clock: clock, latest: false)

// Trailing: report the freshest value once per second
stream.throttle(for: .seconds(1), clock: clock, latest: true)
```

## delay

`delay(for:clock:)` shifts every element forward by `interval`. Each element's deadline
is stamped at **arrival** (`arrival + interval`), so the original inter-arrival spacing is preserved
and a slow consumer never compounds the delay.

```swift
for await v in stream.delay(for: .seconds(1), clock: clock) {
    // each value arrives exactly one second after it was produced
}
```

## timeout

`timeout(_:clock:error:)` forwards each element as `.success`, but if the upstream goes
quiet for `interval` it emits `.failure(error())` and finishes. The deadline is armed at subscription
and re-armed after every element. Normal completion finishes without a failure.

The failure is carried as a **typed value** (`Result<Element, E>`) rather than thrown, so iteration
never surfaces an untyped `any Error` — the error type `E` is preserved end to end.

```swift
struct Timedout: Error {}

for await result in stream.timeout(.seconds(5), clock: clock, error: { Timedout() }) {
    switch result {
    case let .success(v): handle(v)
    case .failure:        showStalledUI()
    }
}
```

## measureInterval

`measureInterval(using:)` replaces each element with the elapsed duration since the
previous element (or since subscription for the first).

```swift
for await gap in taps.measureInterval(using: clock) {
    // gap is the time between consecutive taps
}
```

## collect (by time)

`collect(every:clock:)` groups elements into arrays, flushing at the end of each time
window. Empty windows are skipped; a partial window at completion is always flushed.

```swift
for await batch in events.collect(every: .seconds(1), clock: clock) {
    send(batch)   // one network call per second's worth of events
}
```

## collect (by time or count)

`collect(every:orCount:clock:)` flushes when the window elapses **or** the buffer
reaches `count`, whichever comes first. A count-flush resets the timer, so the next window is a full
`interval` again.

```swift
for await batch in events.collect(every: .seconds(1), orCount: 50, clock: clock) {
    send(batch)   // at most 50 items, or once a second — whichever fills first
}
```

## Building a stream: sequence

`sequence(_:)` turns any `Sequence` into an `AsyncStream` that emits every element then
finishes — handy for feeding fixtures into an operator under test.

```swift
let stream = AsyncStream.sequence(1...3)
```
