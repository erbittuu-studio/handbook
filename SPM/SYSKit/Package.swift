// swift-tools-version: 5.9
//
// SYSKit — the shared layer every app of ours uses.
//
// Vendored, never fetched: apps copy this folder into App/Packages/SYSKit
// (scripts/update.sh does it) so a build never depends on someone else's server.
//
// Deliberately has NO dependencies. That keeps it buildable and testable on its
// own — `swift test` runs on a Linux CI runner with no Xcode, no simulator and
// no Firebase. The Firebase wiring lives in the separate SYSFirebase package,
// which is only resolvable once vendored next to FirebaseKit inside an app.
//
// It also contains no screens. It drives startup and returns state; the app
// owns every pixel.
import PackageDescription

let package = Package(
    name: "SYSKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "SYSKit", targets: ["SYSKit"])
    ],
    targets: [
        .target(name: "SYSKit"),
        .testTarget(name: "SYSKitTests", dependencies: ["SYSKit"])
    ]
)
