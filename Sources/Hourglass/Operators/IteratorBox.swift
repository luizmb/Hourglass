// Boxes an AsyncStream iterator for use in task-group patterns where a single iterator
// is advanced by successive task-group children — exactly one child calls next() at a time.
// @unchecked Sendable: safe because the FIFO task-group pattern serialises all next() calls.
final class IteratorBox<Element: Sendable>: @unchecked Sendable {
    private var iterator: AsyncStream<Element>.AsyncIterator

    init(_ stream: AsyncStream<Element>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async -> Element? {
        await iterator.next()
    }
}
