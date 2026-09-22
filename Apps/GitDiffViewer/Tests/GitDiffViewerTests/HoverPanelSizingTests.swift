import AppKit
import Foundation
import Testing

@testable import DiffTextKit

@Suite struct HoverPanelSizingTests {
    @Test func contentShorterThanTheDegenerateFloorClampsUpToIt() {
        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: 10)
        #expect(height == HoverPanelSizing.minHeight)
        #expect(!scrolls)
    }

    /// A short, real answer -- a one-line declaration and a footer, say -- hugs its own content instead of
    /// padding out to some fixed minimum: the panel used to force every hover up to a 260pt floor, leaving a void
    /// under anything shorter than that regardless of how little it actually had to show.
    @Test func aShortDocumentHugsItsOwnContentRatherThanPaddingToAFixedFloor() {
        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: 90)
        #expect(height == 90)
        #expect(!scrolls)
    }

    @Test func contentBetweenTheFloorAndCeilingSizesExactly() {
        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: 300)
        #expect(height == 300)
        #expect(!scrolls)
    }

    @Test func contentTallerThanTheCeilingClampsAndScrolls() {
        let (height, scrolls) = HoverPanelSizing.clampedHeight(forContentHeight: 900)
        #expect(height == HoverPanelSizing.maxHeight)
        #expect(scrolls)
    }

    @Test func theOriginSitsBelowTheAnchorWhenItFitsOnScreen() {
        let anchor = NSRect(x: 100, y: 500, width: 40, height: 16)
        let size = NSSize(width: 440, height: 300)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = HoverPanelSizing.origin(anchorRect: anchor, panelSize: size, screenFrame: screen)
        #expect(origin.x == anchor.minX)
        #expect(origin.y == anchor.minY - size.height)
    }

    @Test func theOriginFlipsAboveTheAnchorWhenItWouldRunOffTheBottomOfTheScreen() {
        let anchor = NSRect(x: 100, y: 40, width: 40, height: 16)
        let size = NSSize(width: 440, height: 300)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = HoverPanelSizing.origin(anchorRect: anchor, panelSize: size, screenFrame: screen)
        #expect(origin.y == anchor.maxY)
    }

    @Test func theOriginClampsHorizontallyToStayOnScreen() {
        let anchor = NSRect(x: 1800, y: 500, width: 40, height: 16)
        let size = NSSize(width: 440, height: 300)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = HoverPanelSizing.origin(anchorRect: anchor, panelSize: size, screenFrame: screen)
        #expect(origin.x == screen.maxX - size.width)
    }

    @Test func theOriginNeverRunsPastTheLeftEdgeOfTheScreen() {
        let anchor = NSRect(x: -50, y: 500, width: 40, height: 16)
        let size = NSSize(width: 440, height: 300)
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let origin = HoverPanelSizing.origin(anchorRect: anchor, panelSize: size, screenFrame: screen)
        #expect(origin.x == screen.minX)
    }
}
