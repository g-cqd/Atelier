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
    case unknown([UInt8])
}
