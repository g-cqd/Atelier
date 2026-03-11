import KittyInput
import KittySync

final class RenderRefreshSource: @unchecked Sendable {
    private let lock = StateLock<(@Sendable () -> Void)?>(initialState: nil)

    func bind(inputSource: InputSource) {
        lock.withLock { invalidate in
            invalidate = {
                inputSource.inject(.refresh)
            }
        }
    }

    func invalidate() {
        lock.withLock { invalidate in
            invalidate?()
        }
    }
}
