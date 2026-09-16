import AppKit
import DiffCore
import DiffGit
package import Foundation

/// A request from the model to bring a row (or a card, in a file list) into view.
package struct ScrollRequest: Equatable {
    package let id = UUID()
    package let row: Int

    package init(row: Int) {
        self.row = row
    }
}
