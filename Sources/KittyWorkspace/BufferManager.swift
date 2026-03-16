import KittyText

@MainActor
public final class BufferManager {
    public enum CloseResult {
        case closed
        case promptSave
    }

    public private(set) var buffers: [DocumentBuffer] = []
    public private(set) var activeIndex: Int = -1

    public var activeBuffer: DocumentBuffer? {
        guard activeIndex >= 0, activeIndex < buffers.count else { return nil }
        return buffers[activeIndex]
    }

    public var count: Int { buffers.count }

    public var isEmpty: Bool { buffers.isEmpty }

    public init() {}

    @discardableResult
    public func open(
        filePath: String,
        fileName: String,
        content: String,
        language: String?,
        lineEnding: TextDocument.LineEnding = .lineFeed,
        maxUndoSteps: Int = 200
    ) -> Int {
        if let existing = bufferIndex(forPath: filePath) {
            activeIndex = existing
            return existing
        }

        let buffer = DocumentBuffer(
            filePath: filePath,
            fileName: fileName,
            content: content,
            language: language,
            lineEnding: lineEnding,
            maxUndoSteps: maxUndoSteps
        )
        buffers.append(buffer)
        activeIndex = buffers.count - 1
        return activeIndex
    }

    public func close(at index: Int) -> CloseResult {
        guard index >= 0, index < buffers.count else { return .closed }
        if buffers[index].isDirty {
            return .promptSave
        }
        buffers.remove(at: index)
        if buffers.isEmpty {
            activeIndex = -1
        } else if activeIndex >= buffers.count {
            activeIndex = buffers.count - 1
        } else if activeIndex > index {
            activeIndex -= 1
        }
        return .closed
    }

    public func forceClose(at index: Int) {
        guard index >= 0, index < buffers.count else { return }
        buffers.remove(at: index)
        if buffers.isEmpty {
            activeIndex = -1
        } else if activeIndex >= buffers.count {
            activeIndex = buffers.count - 1
        } else if activeIndex > index {
            activeIndex -= 1
        }
    }

    public func switchTo(index: Int) {
        guard index >= 0, index < buffers.count else { return }
        activeIndex = index
    }

    public func nextTab() {
        guard buffers.count > 1 else { return }
        activeIndex = (activeIndex + 1) % buffers.count
    }

    public func prevTab() {
        guard buffers.count > 1 else { return }
        activeIndex = (activeIndex - 1 + buffers.count) % buffers.count
    }

    public func bufferIndex(forPath path: String) -> Int? {
        buffers.firstIndex(where: { $0.filePath == path })
    }

    public var previewIndex: Int? {
        buffers.firstIndex(where: { $0.isPreview })
    }

    @discardableResult
    public func openPreview(
        filePath: String,
        fileName: String,
        content: String,
        language: String?,
        lineEnding: TextDocument.LineEnding = .lineFeed,
        maxUndoSteps: Int = 200
    ) -> Int {
        if let existing = bufferIndex(forPath: filePath) {
            activeIndex = existing
            return existing
        }

        // Replace existing preview buffer
        if let previewIdx = previewIndex {
            buffers.remove(at: previewIdx)
            if activeIndex >= buffers.count {
                activeIndex = max(0, buffers.count - 1)
            } else if activeIndex > previewIdx {
                activeIndex -= 1
            }
        }

        let buffer = DocumentBuffer(
            filePath: filePath,
            fileName: fileName,
            content: content,
            language: language,
            lineEnding: lineEnding,
            maxUndoSteps: maxUndoSteps
        )
        buffer.isPreview = true
        buffers.append(buffer)
        activeIndex = buffers.count - 1
        return activeIndex
    }

    public func pinBuffer(at index: Int) {
        guard index >= 0, index < buffers.count else { return }
        buffers[index].isPreview = false
    }
}
