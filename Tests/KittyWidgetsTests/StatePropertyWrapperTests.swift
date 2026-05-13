import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct StatePropertyWrapperTests {
    @Test func `wrappedValue stores the initial value`() {
        let state = State(wrappedValue: 42)
        #expect(state.wrappedValue == 42)
    }

    @Test func `wrappedValue stores initial string value`() {
        let state = State(wrappedValue: "hello")
        #expect(state.wrappedValue == "hello")
    }

    @Test func `wrappedValue stores initial bool value`() {
        let state = State(wrappedValue: true)
        #expect(state.wrappedValue == true)
    }

    @Test func `Binding reads through to the source value`() {
        nonisolated(unsafe) var source = 99
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        #expect(binding.wrappedValue == 99)
    }

    @Test func `Binding writes through to the source`() {
        nonisolated(unsafe) var source = 0
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        binding.wrappedValue = 42

        #expect(source == 42)
    }

    @Test func `Binding reflects subsequent source changes`() {
        nonisolated(unsafe) var source = 1
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        source = 7
        #expect(binding.wrappedValue == 7)
    }

    @Test func `wrappedValue persists writes through nonmutating set`() {
        let state = State(wrappedValue: 0)
        state.wrappedValue = 42
        #expect(state.wrappedValue == 42)
    }

    @Test func `projectedValue Binding writes are visible to State`() {
        let state = State(wrappedValue: "old")
        let binding = state.projectedValue
        binding.wrappedValue = "new"
        #expect(state.wrappedValue == "new")
    }

    @Test func `State storage is shared across copies`() {
        let original = State(wrappedValue: 1)
        let copy = original
        copy.wrappedValue = 99
        #expect(original.wrappedValue == 99)
    }
}
