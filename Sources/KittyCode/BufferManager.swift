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
}
