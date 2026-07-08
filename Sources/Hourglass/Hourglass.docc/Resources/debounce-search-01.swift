import Hourglass

// A search box streams every keystroke. We want to run the query only once the
// user pauses typing — a classic debounce.
struct SearchModel {
    func debouncedQueries(_ keystrokes: AsyncStream<String>) -> AsyncStream<String> {
        keystrokes.debounce(for: .milliseconds(300), clock: ContinuousClock())
    }
}
