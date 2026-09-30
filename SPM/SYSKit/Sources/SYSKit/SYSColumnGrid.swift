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
        VStack(spacing: 0) {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onWidthChange(of: proxy.size.width) { width = $0 }
            }
            .frame(height: 0)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columns),
                spacing: spacing
            ) {
                content
            }
        }
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

private extension View {
    @ViewBuilder
    func onWidthChange(of width: CGFloat, perform action: @escaping (CGFloat) -> Void) -> some View {
        if #available(iOS 17.0, *) {
            onChange(of: width) { _, new in action(new) }
        } else {
            onChange(of: width, perform: action)
        }
    }
}
#endif
