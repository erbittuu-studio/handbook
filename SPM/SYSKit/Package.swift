// swift-tools-version: 6.0
//
// SYSKit — the shared layer every app of ours uses.
//
// Vendored, never fetched: apps copy this folder into App/Packages/SYSKit
// (scripts/update.sh does it) so a build never depends on someone else's server.
//
// Deliberately has NO dependencies. That keeps it buildable and testable on its
// own — `swift test` runs on a Linux CI runner with no Xcode and no simulator.
//
// It also contains no full screens. It drives startup and returns state; the app
// owns every pixel of how a screen looks.
import PackageDescription

let package = Package(
    name: "SYSKit",
    platforms: [.iOS(.v15), .macOS(.v12), .watchOS(.v9)],
    products: [
        .library(name: "SYSKit", targets: ["SYSKit"])
    ],
    targets: [
        .target(name: "SYSKit"),
        .testTarget(name: "SYSKitTests", dependencies: ["SYSKit"])
    ]
)
