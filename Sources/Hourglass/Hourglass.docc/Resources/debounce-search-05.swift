import Hourglass

// The exact same SearchModel now runs in production — just hand it a real clock.
// `ContinuousClock` keeps counting even while the device is asleep, so the debounce
// window is honoured across suspensions.
let model = SearchModel(clock: ContinuousClock())

for await query in model.debouncedQueries(liveKeystrokes) {
    await runSearch(query)
}
