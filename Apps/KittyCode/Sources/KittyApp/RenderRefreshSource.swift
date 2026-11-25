import Synchronization
public import TerminalKitInput

public final class RenderRefreshSource: Sendable {
    private let lock = Mutex<(@Sendable () -> Void)?>(nil)

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
