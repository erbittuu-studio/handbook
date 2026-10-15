#if canImport(MessageUI) && canImport(SwiftUI) && !os(watchOS)
import MessageUI
import SwiftUI

enum SYSSupportMail {
    @MainActor static var canSend: Bool { MFMailComposeViewController.canSendMail() }
}

public extension View {
    internal func sysSupportMail(
        isPresented: Binding<Bool>,
        subject: String,
        recipient: String = SYSAbout.supportEmail,
        body: String = "\n\n" + SYSVersion.display()
    ) -> some View {
        modifier(SYSSupportMailModifier(isPresented: isPresented, recipient: recipient, subject: subject, message: body))
    }
}

private struct SYSSupportMailModifier: ViewModifier {
    @Binding var isPresented: Bool
    let recipient: String
    let subject: String
    let message: String

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { isPresented && SYSSupportMail.canSend },
                set: { isPresented = $0 }
            )) {
                SYSMailComposer(recipient: recipient, subject: subject, body: message)
                    .ignoresSafeArea()
            }
            .onChange(of: isPresented) { presented in
                guard presented, !SYSSupportMail.canSend else { return }
                isPresented = false
                let query = "subject=\(subject)&body=\(message)"
                    .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "mailto:\(recipient)?\(query)") {
                    UIApplication.shared.open(url)
                }
            }
    }
}

private struct SYSMailComposer: UIViewControllerRepresentable {
    let recipient: String
    let subject: String
    let body: String
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        if let log = SYSLogFile.shared.combinedData() {
            composer.addAttachmentData(log, mimeType: "text/plain", fileName: "log.txt")
        }
        return composer
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            if let error { SYSLogger.error("Failed to send support email", error) }
            dismiss()
        }
    }
}
#endif
