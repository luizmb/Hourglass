import Hourglass

// Hard-coding `ContinuousClock()` makes this impossible to test without real delays.
// Inject the clock instead — the logic is identical, but now the caller decides what
// time means.
struct SearchModel<C: Clock & Sendable> where C.Duration == Duration {
    let clock: C

    func debouncedQueries(_ keystrokes: AsyncStream<String>) -> AsyncStream<String> {
        keystrokes.debounce(for: .milliseconds(300), clock: clock)
    }
}
