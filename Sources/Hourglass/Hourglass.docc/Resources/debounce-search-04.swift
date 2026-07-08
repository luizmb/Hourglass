import Hourglass
import Testing

@Test func debounceEmitsOnlyTheLastQuery() async {
    let clock = TestClock()
    let model = SearchModel(clock: clock)
    let (keystrokes, cont) = AsyncStream<String>.makeStream()
    let emitted = Box<String>()

    let task = Task {
        for await query in model.debouncedQueries(keystrokes) {
            emitted.append(query)
        }
    }

    // Type a burst — each keystroke resets the 300ms window.
    cont.yield("c"); cont.yield("ca"); cont.yield("cat")
    await clock.waitForSleepers()      // the debounce timer has registered

    // Advance past the idle window. Only the last query survives.
    await clock.advance(by: .milliseconds(300))
    await poll { emitted.values.count == 1 }
    #expect(emitted.values == ["cat"])

    cont.finish()
    task.cancel()
}
