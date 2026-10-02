import Foundation

/// Dotted numeric version comparison.
public enum SYSVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
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

    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        compare(lhs, rhs) == .orderedAscending
    }

    public static func isAtLeast(_ minimum: String, current: String = SYSVersion.current()) -> Bool {
        !isOlder(current, than: minimum)
    }

    public static func current(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func build(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func display(bundle: Bundle = .main) -> String {
        "Version \(current(bundle: bundle))"
    }

    private static func parse(_ value: String) -> [Int] {
        value.split(separator: ".").map { Int($0) ?? 0 }
    }
}
