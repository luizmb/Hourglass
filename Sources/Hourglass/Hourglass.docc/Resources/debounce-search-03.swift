import Hourglass
import Testing

@Test func debounceEmitsOnlyTheLastQuery() async {
    // A TestClock never moves on its own — perfect for driving the debounce.
    let clock = TestClock()
    let model = SearchModel(clock: clock)
    let (keystrokes, cont) = AsyncStream<String>.makeStream()
    let emitted = Box<String>()

    let task = Task {
        for await query in model.debouncedQueries(keystrokes) {
            emitted.append(query)
        }
    }
}
