// swift-tools-version: 6.2

import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "GitDiffViewer",
    platforms: [
        .macOS("26.1"),
    ],
    products: [
        .executable(name: "GitDiffViewer", targets: ["GitDiffViewer"]),
        .library(name: "DiffCore", targets: ["DiffCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "603.0.0"),
    ],
    targets: [
        .target(
            name: "DiffCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ],
            swiftSettings: strict
        ),
        .target(name: "DiffConcurrency", swiftSettings: strict),
        .target(name: "DiffIO", swiftSettings: strict + [.strictMemorySafety()]),
        .target(name: "DiffTestSupport", dependencies: ["DiffConcurrency"], swiftSettings: strict),
        .target(name: "DiffGit", dependencies: ["DiffCore", "DiffConcurrency", "DiffIO"], swiftSettings: strict),
        .target(name: "DiffRendering", dependencies: ["DiffCore", "DiffGit"], swiftSettings: strict),
        .target(name: "DiffTextKit", dependencies: ["DiffCore", "DiffRendering"], swiftSettings: strict),
        .target(name: "DiffComparison", dependencies: ["DiffCore", "DiffConcurrency", "DiffGit", "DiffRendering"], swiftSettings: strict),
        .executableTarget(
            name: "GitDiffViewer",
            dependencies: ["DiffCore", "DiffComparison", "DiffGit", "DiffRendering", "DiffTextKit"],
            // Views, coordinators and panels all live on the main actor; nothing in the app target runs elsewhere.
            swiftSettings: strict + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "DiffCoreTests", dependencies: ["DiffCore"], swiftSettings: strict),
        .testTarget(
            name: "GitDiffViewerTests",
            dependencies: ["DiffComparison", "DiffGit", "DiffRendering", "DiffTextKit", "DiffTestSupport"],
            swiftSettings: strict
        ),
    ],
    swiftLanguageModes: [.v6]
)
