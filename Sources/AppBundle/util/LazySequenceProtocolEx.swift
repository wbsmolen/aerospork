extension LazySequenceProtocol {
    func filterNotNil<Unwrapped>() -> [Unwrapped] where Element == Unwrapped? {
        compactMap { $0 }.map { $0 }
    }
}
