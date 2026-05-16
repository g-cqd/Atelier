import Foundation
import KittyCodecs

public extension EditorState {
    public enum HistoryDomain {
        case buffer
        case fileTree
    }

    public struct HistoryAvailability {
        public var canUndo: Bool
        public var canRedo: Bool
        public var domain: HistoryDomain
        public var atSaveBoundary: Bool
    }

    public var activeHistoryDomain: HistoryDomain {
        mode == .editor ? .buffer : .fileTree
    }

    public var historyAvailability: HistoryAvailability {
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

    public func performUndo() {
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

    public func performRedo() {
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
