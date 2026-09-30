import DiffTextKit
import Foundation
import SwiftUI

extension FocusedValues {
    /// The text engine of the focused comparison window, which the Develop menu switches (text-renderer.md §4.3).
    @Entry var textBackend: Binding<TextBackendKind>?
}

/// The Beta menu: the text engine of the focused comparison window. Shown in every build (book D44: no `#if DEBUG`
/// feature gate); its one choice, CoreText, is off by default and labelled as drawing only.
struct DevelopCommands: Commands {
    @FocusedBinding(\.textBackend) private var textBackend

    var body: some Commands {
        CommandMenu("Beta") {
            Picker("Text Engine", selection: $textBackend) {
                ForEach(TextBackendKind.allCases) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
            .disabled(textBackend == nil)
        }
    }
}
