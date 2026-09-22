import Testing

@testable import AtelierSyntaxModel

struct HoverContentQualityTests {
    @Test
    func `declaration-only fence has no prose`() {
        #expect(HoverContentQuality.hasProse("```swift\nclass NSPopover\n```") == false)
    }

    @Test
    func `fence followed by whitespace only has no prose`() {
        #expect(HoverContentQuality.hasProse("```swift\nclass NSPopover\n```\n\n   \n") == false)
    }

    @Test
    func `fence followed by a prose paragraph has prose`() {
        #expect(
            HoverContentQuality.hasProse("```swift\nclass NSPopover\n```\n\nA means to display additional content.")
                == true)
    }

    @Test
    func `multiple fenced blocks with no prose between or after them have no prose`() {
        let markdown = "```swift\nclass A\n```\n\n```swift\nclass B\n```"
        #expect(HoverContentQuality.hasProse(markdown) == false)
    }

    @Test
    func `prose between two fenced blocks counts as prose`() {
        let markdown = "```swift\nclass A\n```\n\nSome text.\n\n```swift\nclass B\n```"
        #expect(HoverContentQuality.hasProse(markdown) == true)
    }

    @Test
    func `plain prose with no fence at all has prose`() {
        #expect(HoverContentQuality.hasProse("Just some words.") == true)
    }

    @Test
    func `empty markdown has no prose`() {
        #expect(HoverContentQuality.hasProse("") == false)
    }

    @Test
    func `leadingFencedBlock returns the fence when markdown opens with one`() {
        let markdown = "```swift\nclass NSPopover\n```\n\nSome prose."
        #expect(HoverContentQuality.leadingFencedBlock(markdown) == "```swift\nclass NSPopover\n```")
    }

    @Test
    func `leadingFencedBlock is nil when markdown does not open with a fence`() {
        #expect(HoverContentQuality.leadingFencedBlock("Some prose.\n\n```swift\nclass A\n```") == nil)
    }

    @Test
    func `leadingFencedBlock is nil for an unterminated fence`() {
        #expect(HoverContentQuality.leadingFencedBlock("```swift\nclass NSPopover") == nil)
    }
}
