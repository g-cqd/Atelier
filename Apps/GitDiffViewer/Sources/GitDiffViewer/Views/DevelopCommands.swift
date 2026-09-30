import DiffTextKit
import Foundation
import SwiftUI

extension FocusedValues {
    /// The text engine of the focused comparison window, which the Develop menu switches (text-renderer.md §4.3).
    @Entry var textBackend: Binding<TextBackendKind>?
}

/// The Develop menu: the text engine of the focused comparison window. It shows in debug builds, or when the defaults
/// key ``TextBackendKind/showsDevelopMenuKey`` is set.
struct DevelopCommands: Commands {
    @FocusedBinding(\.textBackend) private var textBackend

    /// Whether the menu shows: always in a debug build, and in a release build when a developer asked for it.
    static var isShown: Bool {
        #if DEBUG
            true
        #else
            UserDefaults.standard.bool(forKey: TextBackendKind.showsDevelopMenuKey)
        #endif
    }

    var body: some Commands {
        if Self.isShown {
            CommandMenu("Develop") {
                Picker("Text Engine", selection: $textBackend) {
                    ForEach(TextBackendKind.allCases) { kind in
                        Text(kind.title).tag(Optional(kind))
                    }
                }
                .disabled(textBackend == nil)
            }
        }
    }
}
