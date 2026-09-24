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
    }
}
