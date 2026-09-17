import Foundation
import Testing

@testable import AtelierFileTree

@Suite(.tags(.fileNode))
struct FileNodeTests {
    // MARK: Initialisation

    @Test func `init stores all provided values`() {
        let child = FileNode(name: "child.txt", path: "/root/child.txt", isDirectory: false)
        let node = FileNode(
            name: "src",
            path: "/root/src",
            isDirectory: true,
            children: [child],
            isExpanded: true
        )

        #expect(node.name == "src")
        #expect(node.path == "/root/src")
        #expect(node.isDirectory == true)
        #expect(node.children.count == 1)
        #expect(node.children[0].name == "child.txt")
        #expect(node.isExpanded == true)
    }

    @Test func `init defaults children to empty and isExpanded to false`() {
        let node = FileNode(name: "file.swift", path: "/root/file.swift", isDirectory: false)

        #expect(node.children.isEmpty)
        #expect(node.isExpanded == false)
    }

    // MARK: Icon — file

    @Test func `icon for regular file returns three spaces`() {
        let node = FileNode(name: "main.swift", path: "/root/main.swift", isDirectory: false)
        #expect(node.icon == "   ")
    }

    @Test func `icon for collapsed directory returns [+]`() {
        let node = FileNode(
            name: "Sources", path: "/root/Sources", isDirectory: true, isExpanded: false)
        #expect(node.icon == "[+]")
    }

    @Test func `icon for expanded directory returns [-]`() {
        let node = FileNode(
            name: "Sources", path: "/root/Sources", isDirectory: true, isExpanded: true)
        #expect(node.icon == "[-]")
    }

    @Test func `icon toggling reflects isExpanded mutation`() {
        var node = FileNode(name: "lib", path: "/root/lib", isDirectory: true, isExpanded: false)
        #expect(node.icon == "[+]")

        node.isExpanded = true
        #expect(node.icon == "[-]")

        node.isExpanded = false
        #expect(node.icon == "[+]")
    }
}
