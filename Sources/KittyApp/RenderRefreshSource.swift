import KittyInput
import KittySync

public final class RenderRefreshSource: Sendable {
    private let lock = StateLock<(@Sendable () -> Void)?>(initialState: nil)

    public init() {}

    public func bind(inputSource: InputSource) {
        lock.withLock { invalidate in
            invalidate = {
                inputSource.inject(.refresh)
            }
        }
    }

    public func invalidate() {
        lock.withLock { invalidate in
            invalidate?()
        }
    }
}
