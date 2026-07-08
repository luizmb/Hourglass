# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-07-08

First stable release. The clock surface is now complete and the documentation is comprehensive.

### Added
- `WallClock` — a `Clock` whose instants are real calendar `Date`s, with an injectable `() -> Date`
  provider (system clock by default) and a monotonic sleep that is robust to system-clock changes.
- `UnimplementedClock` — a `Clock` that reports a failure via an injected reporter whenever any member
  is used, for asserting a code path never consults time. Stays dependency-free (no test framework is
  imported); wire the reporter to `Issue.record`/`XCTFail` at the call site.
- `TestClock.advance(to:)` — advance to an absolute instant (monotonic).
- `TestClock.run()` — exhaust every pending sleep, draining chained sleeps, without counting steps.
- `Clock.timer(every:)` — method-form convenience for `timerSequence(every:clock:)`.
- Documentation: full DocC curation of every symbol; new articles (**Choosing a Clock**, **Testing
  Timing Code**, **Operators**); an interactive **Debouncing with a Test Clock** tutorial; and README
  coverage for `timeout` and `collect(every:orCount:clock:)`.

### Changed
- **`ImmediateClock.now` now advances.** Each `sleep` still returns immediately, but the clock jumps
  `now` forward to the sleep's deadline (monotonically). This makes `measureInterval` and timer
  instants meaningful under an `ImmediateClock`. Previously `now` was frozen at zero — code that relied
  on that will now observe advancing time.

### Fixed
- Documentation site landing page: the root redirect pointed at `/documentation/`, which DocC static
  hosting never emits — it now points at the module landing at `/documentation/hourglass/`, so
  `https://ios.lu/Hourglass/` resolves to content. Docs also enable overloaded-symbol presentation.

## [0.7.0] - 2026-07-06

### Changed
- Library standardization: SwiftFormat, SPDX headers, Apache license, and the full dotfile/meta set.

## [0.6.2] - 2026-06-17

### Added
- Cross-platform CI: Windows and Android build + test jobs (also exercised in the RC stage).

## [0.5.0] - 2026-06-17

### Added
- Linux CI and toolchain support; the full clock/operator surface is verified off-Apple.

## [0.1.0] - 2026-06-14

- Initial release: `ImmediateClock`, `TestClock`, `timerSequence(every:clock:)`, and the time-based
  `AsyncStream` operators (`debounce`, `delay`, `throttle`, `measureInterval`, `collect`).

[Unreleased]: https://github.com/luizmb/Hourglass/compare/v1.0.0...main
[1.0.0]: https://github.com/luizmb/Hourglass/compare/v0.7.0...v1.0.0
[0.7.0]: https://github.com/luizmb/Hourglass/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/luizmb/Hourglass/compare/v0.5.0...v0.6.2
[0.5.0]: https://github.com/luizmb/Hourglass/compare/v0.1.0...v0.5.0
[0.1.0]: https://github.com/luizmb/Hourglass/releases/tag/v0.1.0
