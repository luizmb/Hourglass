# Choosing a Clock

Pick the right clock for production and for tests.

## Overview

Hourglass leans on the standard library's `Clock` protocol so that a single call site can accept
real time or virtual time. This article walks the whole menu — the two precise production clocks
from the standard library, the calendar-aware ``WallClock``, and the three test clocks — and says
when to reach for each.

The golden rule: **never read time ambiently.** Don't call `Date()`, `ContinuousClock().now`, or
`sleep` deep inside your logic. Accept a `Clock` (or a `() -> Date`) as a parameter, and let the
composition root decide what time means.

## Production clocks

### `ContinuousClock` (standard library)

Precise and monotonic, and it *keeps counting while the device is asleep*. This is the default
choice for most production timing — debounce, throttle, timeouts, polling intervals.

```swift
let ticks = timerSequence(every: .seconds(30), clock: ContinuousClock())
```

### `SuspendingClock` (standard library)

Precise and monotonic, but it *pauses while the device is suspended*. Choose it when you want to
measure active time only — e.g. an animation or a foreground-only timer that should not "catch up"
after the device wakes.

### ``WallClock``

The standard clocks are monotonic but their instants are opaque — you cannot get a calendar `Date`
back out. ``WallClock`` is the bridge: its ``WallClock/Instant`` wraps a real `Date`, so you can
schedule against actual calendar moments and log real timestamps, while staying injectable.

```swift
// Production: the system clock
let clock = WallClock()

// Test: time is exactly what you say it is
var now = Date(timeIntervalSince1970: 0)
let fake = WallClock(now: { now })
```

Its `sleep` waits the measured interval on a monotonic clock, so an in-flight sleep is unaffected by
system-clock changes (NTP steps, the user editing the date).

## Test clocks

### ``TestClock`` — control time by hand

Virtual time that only moves when you tell it to. This is the workhorse for testing timing
operators: advance the clock and assert exactly what was emitted.

- ``TestClock/advance(by:)`` — move forward by a duration.
- ``TestClock/advance(to:)`` — move to an absolute instant (monotonic; a no-op if already past it).
- ``TestClock/run()`` — exhaust every pending sleep, draining chained sleeps, without counting steps.
- ``TestClock/waitForSleepers(count:)`` — wait until the expected number of tasks are sleeping
  before you advance, avoiding races.

See <doc:TestingTimingCode> for the full patterns.

### ``ImmediateClock`` — skip the waiting

Every `sleep` returns immediately, but `now` still advances to each sleep's deadline. Use it when you
want an operator's *pass-through* behaviour without simulating real delays, and still want elapsed
time (`measureInterval`, timer instants) to be meaningful.

### ``UnimplementedClock`` — prove time is untouched

A clock that reports a failure the instant any of its members is used. Inject it where you expect *no*
timing to happen; if the code sleeps or reads `now`, your test fails.

```swift
import Testing

let clock = UnimplementedClock("cache hit must not sleep") { message in
    Issue.record(Comment(rawValue: message))
}
```

## Erasing the choice: ``AnyClock``

`Clock` has two associated types (`Instant` and `Duration`), which makes `any Clock` nearly unusable —
it erases `Duration`, so you can't `sleep(for: .seconds(1))`. ``AnyClock`` fixes `Duration` as its one
generic parameter and supplies its own canonical instant, so `ContinuousClock`, `TestClock`, and
``ImmediateClock`` all erase into the *same* swappable type:

```swift
let live: AnyClock<Duration> = ContinuousClock().eraseToAnyClock()
let test: AnyClock<Duration> = TestClock().eraseToAnyClock()   // same type — interchangeable
try await live.sleep(for: .milliseconds(300))
```

Store an `AnyClock` in a type that shouldn't leak which concrete clock it holds.

## Quick reference

| Need | Clock |
|---|---|
| Production timing, count through sleep | `ContinuousClock` |
| Production timing, active time only | `SuspendingClock` |
| Real calendar dates, injectable | ``WallClock`` |
| Deterministic tests you drive by hand | ``TestClock`` |
| Fast tests, delays don't matter | ``ImmediateClock`` |
| Assert a path never uses time | ``UnimplementedClock`` |
| Hide the concrete clock behind one type | ``AnyClock`` |
