# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/luizmb/Hourglass/compare/v0.7.0...main
[0.7.0]: https://github.com/luizmb/Hourglass/compare/v0.6.2...v0.7.0
[0.6.2]: https://github.com/luizmb/Hourglass/compare/v0.5.0...v0.6.2
[0.5.0]: https://github.com/luizmb/Hourglass/compare/v0.1.0...v0.5.0
[0.1.0]: https://github.com/luizmb/Hourglass/releases/tag/v0.1.0
