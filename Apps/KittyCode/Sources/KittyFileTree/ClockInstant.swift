/// A point in time read from an injected `any Clock<Duration>`, stored without naming the clock's associated
/// `Instant` type — an existential `any Clock<Duration>` cannot expose that associated type directly, so a
/// stored timestamp has nowhere to live unless it is erased like this.
///
/// `duration(to:)` and the comparison operators are only meaningful between instants taken from the same
/// clock; a comparison against an instant from a different clock returns a zero duration instead of trapping,
/// since every use in this codebase injects one clock per owner and reads every stored instant from it.
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
    /// `now`, boxed into a ``ClockInstant`` so it can be stored as a property whose declared type does not
    /// name this clock's concrete `Instant` type. Called on an `any Clock<Duration>` value, Swift opens the
    /// existential to call this extension method against the clock's real, underlying type.
    public func erasedNow() -> ClockInstant {
        ClockInstant(now, of: Self.self)
    }
}
