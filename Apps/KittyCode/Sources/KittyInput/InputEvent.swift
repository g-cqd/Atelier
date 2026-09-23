public import KittyCodecs
public import KittyTerminal

public enum InputEvent: Sendable {
    case key(KeyEvent)
    case mouse(MouseEvent)
    case resize(TerminalSize)
    case paste(String)
    case focusIn
    case focusOut
    case refresh
    /// A sequence that passed its cap; the router drops the rest of it up to its end, so none of it arrives as keys.
    case overflow(InputOverflow)
    case unknown([UInt8])
}

/// The kind of sequence an ``InputEvent/overflow(_:)`` dropped.
public enum InputOverflow: Sendable, Equatable {
    /// A bracketed paste over ``SequenceRouter/maxPasteSize``.
    case paste
    /// An OSC sequence over ``SequenceRouter/maxPasteSize``, such as a large clipboard reply. `command` is its leading
    /// number, 52 for the clipboard, or nil when it has none.
    case osc(command: Int?)
    /// A control sequence over ``SequenceRouter/maxControlSequenceSize``.
    case controlSequence
}
