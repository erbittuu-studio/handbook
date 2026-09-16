import Foundation

/// Dotted numeric version comparison.
///
/// Exists because the obvious approach is wrong: compared as strings, "1.10.0"
/// sorts *below* "1.9.0". That behaves correctly for years and then breaks the
/// first time a minor version reaches double digits — usually during a release,
/// which is the worst moment to discover it.
public enum SYSVersion {
    /// Missing components count as zero, so "1.2" and "1.2.0" are equal.
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parse(lhs)
        let right = parse(rhs)

        for index in 0 ..< max(left.count, right.count) {
            let leftPart = index < left.count ? left[index] : 0
            let rightPart = index < right.count ? right[index] : 0
            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    /// The running app's marketing version, e.g. "2.5.1".
    public static func current(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// The running app's build number, e.g. "42". A string, not an Int: Xcode
    /// Cloud owns this counter and overwrites CFBundleVersion with it at
    /// archive/export time (App/ci_scripts/ci_pre_xcodebuild.sh deliberately
    /// leaves it alone), so nothing here should imply it is a value the app
    /// itself computed or could validate as numeric.
    public static func build(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// "Version 2.5.1" — deliberately never the build number. A Settings
    /// screen is read by a user, not a support engineer, and Xcode Cloud's
    /// build counter identifies nothing to them; a support request that
    /// needs it can get it from TestFlight instead. Three apps had grown
    /// three near-identical "Version X (Y)" strings before this existed.
    public static func display(bundle: Bundle = .main) -> String {
        "Version \(current(bundle: bundle))"
    }

    private static func parse(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}
