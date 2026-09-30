#if os(iOS)
import SwiftUI

public struct SYSTwoPane<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    @Environment(\.sysMetrics) private var metrics

    public init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    public var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView(primary: { primary }, secondary: { secondary })
        } else if metrics.isCompactWidth {
            VStack { primary; secondary }
        } else {
            HStack { primary; secondary }
        }
    }
}
#endif
