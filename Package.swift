// swift-tools-version: 5.9
import PackageDescription

// Sprint's QA widget for iOS apps.
//
// Two targets, deliberately split:
//   SprintQACore  Foundation only: the wire contract, the client, PKCE, the
//                 Keychain store, tokens, theme and strings. It also builds on
//                 macOS, which is only there so `swift test` runs on a Mac CI
//                 runner without a simulator.
//   SprintQA      The UIKit and SwiftUI widget. iOS and iPadOS only.
//
// No third-party dependencies.
let package = Package(
    name: "SprintQA",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SprintQA", targets: ["SprintQA"]),
    ],
    targets: [
        .target(name: "SprintQACore", path: "Sources/SprintQACore"),
        .target(name: "SprintQA", dependencies: ["SprintQACore"], path: "Sources/SprintQA"),
        .testTarget(name: "SprintQACoreTests", dependencies: ["SprintQACore"], path: "Tests/SprintQACoreTests"),
        // iOS only; run with xcodebuild on a simulator. Empty under `swift test` on a Mac.
        .testTarget(name: "SprintQATests", dependencies: ["SprintQA"], path: "Tests/SprintQATests"),
    ]
)
