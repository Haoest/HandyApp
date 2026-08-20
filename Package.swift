// swift-tools-version: 6.0
import PackageDescription

// Command-line test harness for HandyApp3's logic layer.
//
// The Xcode project remains the only way the *app* is built. This package points at
// the same source files on disk (nothing is copied or moved) so the pure-Swift half —
// Models, Controllers, SystemTypes — can be compiled and its tests run headlessly with
// `swift test`, which needs no simulator and no asset catalog.
//
// Excluded from the target: `Views/` (SwiftUI), the AppIntents half of `Intents/`, and
// `ReceiptScanner.swift` (the one Controller that imports UIKit). Nothing in
// HandyApp3Tests/ touches them. `Intents/AssetNameMatcher.swift` is Foundation-only
// pure logic with its own test file, and `Views/HomeActivityDigest.swift` is likewise
// Foundation-only, so both are pulled in explicitly.
let package = Package(
    name: "HandyApp3",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "HandyApp3",
            path: "HandyApp3",
            exclude: ["Controllers/ReceiptScanner.swift"],
            sources: ["Models", "Controllers", "SystemTypes", "Intents/AssetNameMatcher.swift", "Views/HomeActivityDigest.swift"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HandyApp3Tests",
            dependencies: ["HandyApp3"],
            path: "HandyApp3Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
