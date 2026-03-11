@MainActor
final class BufferManager {
    enum CloseResult {
        case closed
        case promptSave
    }

    private(set) var buffers: [DocumentBuffer] = []
    private(set) var activeIndex: Int = -1

    var activeBuffer: DocumentBuffer? {
        guard activeIndex >= 0, activeIndex < buffers.count else { return nil }
        return buffers[activeIndex]
    }

    var count: Int { buffers.count }

    var isEmpty: Bool { buffers.isEmpty }

    @discardableResult
    func open(filePath: String, fileName: String, content: String, language: String?) -> Int {
        if let existing = bufferIndex(forPath: filePath) {
            activeIndex = existing
            return existing
        }

        let buffer = DocumentBuffer(
            filePath: filePath,
            fileName: fileName,
            content: content,
            language: language
        )
        buffers.append(buffer)
        activeIndex = buffers.count - 1
        return activeIndex
    }

    func close(at index: Int) -> CloseResult {
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

    func forceClose(at index: Int) {
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

    func switchTo(index: Int) {
        guard index >= 0, index < buffers.count else { return }
        activeIndex = index
    }

    func nextTab() {
        guard buffers.count > 1 else { return }
        activeIndex = (activeIndex + 1) % buffers.count
    }

    func prevTab() {
        guard buffers.count > 1 else { return }
        activeIndex = (activeIndex - 1 + buffers.count) % buffers.count
    }

    func bufferIndex(forPath path: String) -> Int? {
        buffers.firstIndex(where: { $0.filePath == path })
    }

    /// Index of the current preview buffer, if any.
    var previewIndex: Int? {
        buffers.firstIndex(where: { $0.isPreview })
    }

    /// Open a file as a preview tab, replacing any existing preview buffer.
    @discardableResult
    func openPreview(filePath: String, fileName: String, content: String, language: String?) -> Int {
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
            language: language
        )
        buffer.isPreview = true
        buffers.append(buffer)
        activeIndex = buffers.count - 1
        return activeIndex
    }

    /// Pin the buffer at the given index (remove its preview status).
    func pinBuffer(at index: Int) {
        guard index >= 0, index < buffers.count else { return }
        buffers[index].isPreview = false
    }
}
