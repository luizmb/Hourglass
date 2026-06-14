// Boxes a sequence iterator for use in AsyncStream(unfolding:), which captures a @Sendable closure.
// @unchecked Sendable: safe because AsyncStream guarantees single-consumer iteration.
private final class _SequenceBox<S: Sequence & Sendable>: @unchecked Sendable {
    private var _iter: S.Iterator
    init(_ sequence: S) { _iter = sequence.makeIterator() }
    func next() -> S.Element? { _iter.next() }
}

public extension AsyncStream {
    /// Creates an `AsyncStream` that emits all elements of `values` then finishes.
    static func sequence<S: Sequence & Sendable>(_ values: S) -> AsyncStream<Element>
    where S.Element == Element {
        let box = _SequenceBox(values)
        return AsyncStream(unfolding: { box.next() })
    }
}
