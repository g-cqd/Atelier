import Testing

@testable import AtelierSyntaxModel

/// How a caller turns a file's path and first line into a language: its exact file name, then its extension, then,
/// for a name with no extension, the interpreter its `#!` line names.
struct LanguageDetectionByFileNameTests {
    @Test(arguments: [".zshrc", "home/me/.zshrc", ".bash_profile", ".profile", "bin/.bashrc"])
    func `a shell dotfile is shell by its exact file name`(path: String) {
        #expect(Language(path: path) == .shell)
    }

    @Test(arguments: ["Gemfile", "Podfile", "Rakefile", "Fastfile", "Brewfile", "Vagrantfile"])
    func `a Ruby tool's file name is Ruby by its exact file name`(path: String) {
        #expect(Language(path: path) == .ruby)
    }

    @Test
    func `an unmapped extension is plain, even for a name that starts like a Ruby file`() {
        #expect(Language(path: "Podfile.lock") == .plain)
    }

    @Test(arguments: [
        ("Sources/App/main.swift", Language.swift), ("include/x.h", .objectiveC), ("README.md", .plain),
        ("a.podspec", .ruby), ("run.ksh", .shell)
    ])
    func `an extension resolves to the language it always has`(path: String, language: Language) {
        #expect(Language(path: path) == language)
    }

    @Test
    func `an upper-case extension resolves as its lower-case form does`() {
        #expect(Language(path: "Main.SWIFT") == Language(fileExtension: "SWIFT"))
        #expect(Language(path: "Main.SWIFT") == .swift)
    }

    @Test(arguments: [
        ("#!/bin/sh", Language.shell), ("#!/bin/bash", .shell), ("#!/usr/bin/env bash", .shell),
        ("#!/usr/bin/env -S python3 -u", .python), ("#!/usr/bin/python3.12", .python),
        ("#!/usr/bin/env node", .javascript), ("#!/usr/local/bin/fish", .fish), ("#!/usr/bin/env ruby", .ruby),
        ("#!/usr/bin/env lua", .lua), ("#!/usr/bin/env swift", .swift)
    ])
    func `an extensionless script takes the language of the interpreter its first line names`(
        firstLine: String, language: Language
    ) {
        #expect(Language(path: "deploy", firstLine: Substring(firstLine)) == language)
    }

    @Test
    func `a script under a directory is detected by its interpreter the same way`() {
        #expect(Language(path: "bin/deploy", firstLine: "#!/usr/bin/env zsh") == .shell)
    }

    @Test
    func `a shebang does not change a file whose name has an extension`() {
        #expect(Language(path: "notes.txt", firstLine: "#!/bin/sh") == .plain)
    }

    @Test
    func `an extension wins over a shebang`() {
        #expect(Language(path: "tool.py", firstLine: "#!/bin/sh") == .python)
    }

    @Test
    func `a name ending in a dot has no extension, so its shebang decides`() {
        #expect(Language(path: "deploy.", firstLine: "#!/bin/sh") == .shell)
    }

    @Test(arguments: [nil, "echo hi", "#!/usr/bin/perl"] as [String?])
    func `an extensionless file whose first line names no known interpreter is plain`(firstLine: String?) {
        #expect(Language(path: "deploy", firstLine: firstLine.map { Substring($0) }) == .plain)
    }

    @Test(arguments: [
        "Makefile", "GNUmakefile", "Dockerfile", "CMakeLists.txt", "toolchain.cmake", ".env", ".gitignore",
        ".gitattributes"
    ])
    func `a name with no language of its own is plain`(path: String) {
        #expect(Language(path: path) == .plain)
    }
}
