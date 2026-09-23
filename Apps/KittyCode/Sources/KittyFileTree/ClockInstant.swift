/// A point in time from an injected `any Clock<Duration>`, erased so a property can store it without naming the
/// clock's `Instant` type. Durations and comparisons hold only between instants of one clock: across clocks the
/// duration is zero, so such instants compare equal.
public struct ClockInstant: Sendable, Comparable {
    private let instant: any Sendable
    private let distanceTo: @Sendable (any Sendable) -> Duration
    private let advance: @Sendable (Duration) -> ClockInstant

    fileprivate init<ClockType: Clock>(_ instant: ClockType.Instant, of clockType: ClockType.Type)
    where ClockType.Duration == Duration {
        self.instant = instant
        self.distanceTo = { other in
            guard let other = other as? ClockType.Instant else { return .zero }
            return instant.duration(to: other)
        }
        self.advance = { duration in
            ClockInstant(instant.advanced(by: duration), of: ClockType.self)
        }
    }

    /// Elapsed time from `self` to `other`; positive when `other` is later, negative when it is earlier.
    public func duration(to other: ClockInstant) -> Duration {
        distanceTo(other.instant)
    }

    public func advanced(by duration: Duration) -> ClockInstant {
        advance(duration)
    }

    public static func == (lhs: ClockInstant, rhs: ClockInstant) -> Bool {
        lhs.duration(to: rhs) == .zero
    }

    public static func < (lhs: ClockInstant, rhs: ClockInstant) -> Bool {
        lhs.duration(to: rhs) > .zero
    }
}

extension Clock where Duration == Swift.Duration {
    /// The clock's `now`, erased into a ``ClockInstant``; callable on an `any Clock<Duration>`.
    public func erasedNow() -> ClockInstant {
        ClockInstant(now, of: Self.self)
    }
}
