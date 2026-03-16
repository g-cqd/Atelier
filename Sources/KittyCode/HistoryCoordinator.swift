import Foundation
import KittyCodecs

extension EditorState {
    enum HistoryDomain {
        case buffer
        case fileTree
    }

    struct HistoryAvailability {
        var canUndo: Bool
        var canRedo: Bool
        var domain: HistoryDomain
        var atSaveBoundary: Bool
    }

    var activeHistoryDomain: HistoryDomain {
        mode == .editor ? .buffer : .fileTree
    }

    var historyAvailability: HistoryAvailability {
        switch activeHistoryDomain {
        case .buffer:
            let buffer = bufferManager.activeBuffer
            return HistoryAvailability(
                canUndo: buffer?.editHistory.hasUndo ?? false,
                canRedo: buffer?.editHistory.hasRedo ?? false,
                domain: .buffer,
                atSaveBoundary: buffer?.editHistory.isNextUndoAtSaveBoundary ?? false
            )
        case .fileTree:
            return HistoryAvailability(
                canUndo: fileTreeHistory.hasUndo,
                canRedo: fileTreeHistory.hasRedo,
                domain: .fileTree,
                atSaveBoundary: false
            )
        }
    }

    func performUndo() {
        switch activeHistoryDomain {
        case .buffer:
            let wasAtSaveBoundary =
                bufferManager.activeBuffer?.editHistory.isNextUndoAtSaveBoundary ?? false
            undoActiveBuffer()
            if wasAtSaveBoundary, statusMessage.hasPrefix("Undo ") {
                statusMessage += " (at saved state)"
            }
        case .fileTree:
            Task { @MainActor in
                await undoFileTreeOperation()
            }
        }
    }

    func performRedo() {
        switch activeHistoryDomain {
        case .buffer:
            redoActiveBuffer()
        case .fileTree:
            Task { @MainActor in
                await redoFileTreeOperation()
            }
        }
    }
}
