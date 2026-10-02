#if os(iOS)
import SwiftUI

struct SYSTwoPane<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    @Environment(\.sysMetrics) private var metrics

    init(@ViewBuilder primary: () -> Primary, @ViewBuilder secondary: () -> Secondary) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        if #available(iOS 27.1, *) {
            ArrangementView(primary: { primary }, secondary: { secondary })
        } else if metrics.prefersSideBySide {
            HStack { primary; secondary }
        } else {
            VStack { primary; secondary }
        }
    }
}
#endif
