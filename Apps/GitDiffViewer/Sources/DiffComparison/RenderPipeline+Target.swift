extension RenderPipeline {
    /// What a render shows: one file on its own, or a card per file.
    package enum Target: Equatable {
        case file(FilePair)
        case cards([FilePair])

        package var pairs: [FilePair] {
            switch self {
                case .file(let pair): [pair]
                case .cards(let pairs): pairs
            }
        }

        package var isCards: Bool {
            if case .cards = self { true } else { false }
        }

        /// Whether both are card lists of the same files, in the same order, whatever their content.
        func showsSameFiles(as other: Target) -> Bool {
            guard case .cards(let pairs) = self, case .cards(let others) = other else { return false }
            return pairs.map(\.path) == others.map(\.path)
        }
    }
}
