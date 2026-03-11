import Foundation

public enum TerminalSymbolSupport {
    public static func prefersSFSymbolGlyphs() -> Bool {
        if let value = ProcessInfo.processInfo.environment["KITTYCODE_SF_SYMBOLS"] {
            return value != "0"
        }
        return true
    }
}
