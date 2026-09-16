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
        .package(url: "https://github.com/Aemi-Studio/aemi.git", branch: "main"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "604.0.0")
    ],
    targets: [
        .target(
            name: "DiffCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ],
            swiftSettings: strict
        ),
        // Git runs through aemi's blocking-work pool and reads blobs through its POSIX file map.
        .target(
            name: "DiffGit",
            dependencies: [
                "DiffCore", .product(name: "AemiIO", package: "aemi"), .product(name: "AemiRuntime", package: "aemi")
            ],
            swiftSettings: strict
        ),
        .target(name: "DiffRendering", dependencies: ["DiffCore", "DiffGit"], swiftSettings: strict),
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
        .testTarget(name: "DiffCoreTests", dependencies: ["DiffCore"], swiftSettings: strict),
        .testTarget(
            name: "GitDiffViewerTests",
            dependencies: [
                "DiffComparison", "DiffGit", "DiffRendering", "DiffTextKit",
                .product(name: "AemiCore", package: "aemi"), .product(name: "AemiTesting", package: "aemi")
            ],
            swiftSettings: strict
        )
    ]
)
