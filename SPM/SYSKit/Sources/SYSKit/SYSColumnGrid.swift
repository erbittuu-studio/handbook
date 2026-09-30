#if os(iOS)
import SwiftUI

public struct SYSColumnGrid<Content: View>: View {
    private let minimumWidth: CGFloat
    private let spacing: CGFloat
    private let minimumColumns: Int
    private let even: Bool?
    private let content: Content

    @Environment(\.sysMetrics) private var metrics
    @State private var width: CGFloat = 0

    public init(
        minimumWidth: CGFloat = 150,
        spacing: CGFloat = 12,
        minimumColumns: Int = 1,
        even: Bool? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.minimumWidth = minimumWidth
        self.spacing = spacing
        self.minimumColumns = minimumColumns
        self.even = even
        self.content = content()
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
            spacing: spacing
        ) {
            content
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SYSColumnGridWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SYSColumnGridWidthKey.self) { width = $0 }
    }

    private var columns: Int {
        guard width > 0 else { return max(minimumColumns, 1) }
        return metrics.columns(
            minimumWidth: minimumWidth,
            spacing: spacing,
            minimumColumns: minimumColumns,
            even: even,
            in: width
        )
    }
}

private struct SYSColumnGridWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
#endif
