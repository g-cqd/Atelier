// swift-tools-version: 6.4

import PackageDescription

// The same strict tier aemi applies to its kernel targets: Swift 6 language mode, warnings as errors, and the
// upcoming features that tighten existentials, isolation inference and import visibility.
let strict: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility")
]

let package = Package(
    name: "GitDiffViewer",
    platforms: [
        .macOS("26.1")
    ],
    products: [
        .executable(name: "GitDiffViewer", targets: ["GitDiffViewer"]),
        .library(name: "DiffCore", targets: ["DiffCore"])
    ],
    dependencies: [
        .package(path: "../../Packages/AtelierCore"),
        .package(url: "https://github.com/Aemi-Studio/aemi.git", branch: "main")
    ],
    targets: [
        // Re-exports the core diff, lexers, language vocabulary and swift-syntax provider under the old name.
        .target(
            name: "DiffCore",
            dependencies: [
                .product(name: "AtelierDiff", package: "AtelierCore"),
                .product(name: "AtelierLexers", package: "AtelierCore"),
                .product(name: "AtelierSwiftSyntax", package: "AtelierCore"),
                .product(name: "AtelierSyntaxModel", package: "AtelierCore")
            ],
            swiftSettings: strict
        ),
        // Git runs through aemi's blocking-work pool and reads blobs through its POSIX file map.
        .target(
            name: "DiffGit",
            dependencies: [
                "DiffCore", .product(name: "AtelierGit", package: "AtelierCore"),
                .product(name: "AtelierSources", package: "AtelierCore"),
                .product(name: "AtelierProcess", package: "AtelierCore"),
                .product(name: "AemiIO", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        // The one target that links swift-syntax, for the syntax tier of the intraline emphasis.
        .target(
            name: "DiffRendering",
            dependencies: ["DiffCore", "DiffGit", .product(name: "AtelierSwiftSyntax", package: "AtelierCore")],
            swiftSettings: strict
        ),
        .target(
            name: "DiffTextKit",
            dependencies: ["DiffCore", "DiffRendering", .product(name: "AemiCore", package: "aemi")],
            swiftSettings: strict
        ),
        // App-tier models spawn through AemiCore's task provider; fan-out and the clock seam come from AemiRuntime.
        .target(
            name: "DiffComparison",
            dependencies: [
                "DiffCore", "DiffGit", "DiffRendering",
                .product(name: "AemiCore", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "GitDiffViewer",
            dependencies: ["DiffCore", "DiffComparison", "DiffGit", "DiffRendering", "DiffTextKit"],
            // Views, coordinators and panels all live on the main actor; nothing in the app target runs elsewhere.
            swiftSettings: strict + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "GitDiffViewerTests",
            dependencies: [
                "DiffComparison", "DiffGit", "DiffRendering", "DiffTextKit",
                .product(name: "AtelierSources", package: "AtelierCore"),
                .product(name: "AtelierSwiftSyntax", package: "AtelierCore"),
                .product(name: "AtelierTestSupport", package: "AtelierCore"),
                .product(name: "AemiCore", package: "aemi"), .product(name: "AemiTesting", package: "aemi")
            ],
            swiftSettings: strict
        )
    ]
)
