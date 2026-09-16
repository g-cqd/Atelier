import CoreText
import Foundation

public struct SymbolDiscovery {
    private let fileManager: FileManager
    private let metadataLoader: SymbolMetadataLoader

    public init() {
        self.fileManager = .default
        self.metadataLoader = SymbolMetadataLoader()
    }

    public func discover() throws -> SymbolCollection {
        let frameworkURL = try locateFramework()

        let publicBundle = frameworkURL.appending(
            path: "CoreGlyphs.bundle", directoryHint: .isDirectory)
        let privateBundle = frameworkURL.appending(
            path: "CoreGlyphsPrivate.bundle", directoryHint: .isDirectory)

        let publicNames = try loadSymbolOrder(from: publicBundle)
        let publicMetadata = try metadataLoader.loadFrameworkMetadata(from: publicBundle)

        let privateNames = try loadSymbolOrder(from: privateBundle)
        let privateMetadata = try metadataLoader.loadFrameworkMetadata(from: privateBundle)

        let fontCodepoints = extractFontPUACodepoints()

        let publicRecords = makeRecords(
            orderedNames: publicNames,
            visibility: .publicSymbol,
            metadata: publicMetadata,
            fontCodepoints: fontCodepoints
        )
        let privateRecords = makeRecords(
            orderedNames: privateNames,
            visibility: .privateSymbol,
            metadata: privateMetadata,
            fontCodepoints: nil
        )

        return SymbolCollection(records: publicRecords + privateRecords)
    }

    private func loadSymbolOrder(from bundleURL: URL) throws -> [String] {
        let url = bundleURL.appending(path: "symbol_order.plist")
        let data = try Data(contentsOf: url)
        guard
            let names = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String]
        else {
            throw SymbolDiscoveryError.invalidPropertyList(url.path)
        }
        return names
    }

    private func makeRecords(
        orderedNames: [String],
        visibility: SymbolRecord.Visibility,
        metadata: SymbolMetadataLoader.Metadata,
        fontCodepoints: [UInt32]?
    ) -> [SymbolRecord] {
        orderedNames.enumerated()
            .map { index, name in
                let codepoint: UInt32?
                if let fontCodepoints, index < fontCodepoints.count {
                    codepoint = fontCodepoints[index]
                } else {
                    codepoint = nil
                }
                let glyph = codepoint.flatMap { UnicodeScalar($0) }.map { String(Character($0)) }
                return SymbolRecord(
                    name: name,
                    visibility: visibility,
                    assetGlyphIndex: index,
                    codepoint: codepoint,
                    glyph: glyph,
                    availability: metadata.availabilityByName[name],
                    categories: metadata.categoriesByName[name] ?? [],
                    searchTerms: metadata.searchTermsByName[name] ?? []
                )
            }
    }

    private func extractFontPUACodepoints() -> [UInt32]? {
        let fontNames = ["SF Pro Display", "SF Pro", ".AppleSystemUIFont"]
        var resolvedFont: CTFont?

        for name in fontNames {
            let candidate = CTFontCreateWithName(name as CFString, 12, nil)
            let family = CTFontCopyFamilyName(candidate) as String
            if family.contains("SF Pro") {
                resolvedFont = candidate
                break
            }
        }

        guard let font = resolvedFont else { return nil }
        let charset = CTFontCopyCharacterSet(font)

        var codepoints: [UInt32] = []
        for cp: UInt32 in 0x100000 ... 0x103FFF where CFCharacterSetIsLongCharacterMember(charset, cp) {
            codepoints.append(cp)
        }

        return codepoints.isEmpty ? nil : codepoints
    }

    private func locateFramework() throws -> URL {
        let volumesDirectory = URL(
            fileURLWithPath: "/Library/Developer/CoreSimulator/Volumes",
            isDirectory: true
        )

        let volumes =
            try fileManager.contentsOfDirectory(
                at: volumesDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            .filter { $0.lastPathComponent.hasPrefix("iOS_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        for volume in volumes {
            // Walk into the volume to find .simruntime directories
            let runtimesPath =
                volume
                .appending(
                    path: "Library/Developer/CoreSimulator/Profiles/Runtimes",
                    directoryHint: .isDirectory)

            guard
                let runtimeDirs = try? fileManager.contentsOfDirectory(
                    at: runtimesPath,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
            else {
                continue
            }

            for runtimeDir in runtimeDirs {
                let framework =
                    runtimeDir
                    .appending(
                        path:
                            "Contents/Resources/RuntimeRoot/System/Library/PrivateFrameworks/SFSymbols.framework",
                        directoryHint: .isDirectory)
                let orderPlist = framework.appending(path: "CoreGlyphs.bundle/symbol_order.plist")

                if fileManager.fileExists(atPath: orderPlist.path) {
                    return framework
                }
            }
        }

        throw SymbolDiscoveryError.missingSimulatorRuntime
    }
}
