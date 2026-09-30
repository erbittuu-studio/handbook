#if os(iOS)
import SwiftUI

public enum SYSFont {
    public static let largeTitle = Font.system(.largeTitle)
    public static let title = Font.system(.title)
    public static let title2 = Font.system(.title2)
    public static let title3 = Font.system(.title3)
    public static let headline = Font.system(.headline)
    public static let subheadline = Font.system(.subheadline)
    public static let body = Font.system(.body)
    public static let callout = Font.system(.callout)
    public static let footnote = Font.system(.footnote)
    public static let caption = Font.system(.caption)
    public static let caption2 = Font.system(.caption2)

    public static let rounded = SYSRoundedFont()
}

public struct SYSRoundedFont {
    public let largeTitle = Font.system(.largeTitle, design: .rounded)
    public let title = Font.system(.title, design: .rounded)
    public let title2 = Font.system(.title2, design: .rounded)
    public let title3 = Font.system(.title3, design: .rounded)
    public let headline = Font.system(.headline, design: .rounded)
    public let subheadline = Font.system(.subheadline, design: .rounded)
    public let body = Font.system(.body, design: .rounded)
    public let callout = Font.system(.callout, design: .rounded)
    public let footnote = Font.system(.footnote, design: .rounded)
    public let caption = Font.system(.caption, design: .rounded)
    public let caption2 = Font.system(.caption2, design: .rounded)
}
#endif
