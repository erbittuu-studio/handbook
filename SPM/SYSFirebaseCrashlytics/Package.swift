// swift-tools-version: 5.9
//
// SYSFirebaseCrashlytics — SYSErrorReporter only, for an app whose vendored
// FirebaseKit carries Crashlytics but not Analytics.
//
// A separate package, not a second product inside SYSFirebase's own
// manifest: SPM resolves every target a manifest declares, not just the
// product an app actually links, so SYSFirebase's own FirebaseAnalytics
// dependency would still fail resolution here even unused. Genuinely
// separate packages is the only shape SPM lets an app opt out of one half.
//
// The App Store Kids Category forbids third-party measurement and ad SDKs —
// this is why FirebaseAnalytics cannot simply be vendored anyway for an app
// in it, not a workaround for something that could otherwise be included.
import PackageDescription

let package = Package(
    name: "SYSFirebaseCrashlytics",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SYSFirebaseCrashlytics", targets: ["SYSFirebaseCrashlytics"]),
    ],
    dependencies: [
        .package(path: "../SYSKit"),
        .package(path: "../../Vendor/FirebaseKit"),
    ],
    targets: [
        .target(
            name: "SYSFirebaseCrashlytics",
            dependencies: [
                "SYSKit",
                .product(name: "FirebaseCrashlytics", package: "FirebaseKit"),
            ]
        ),
    ]
)
