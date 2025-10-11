//
//  MailView.swift
//
import SwiftUI
#if canImport(MessageUI)
import MessageUI
#endif

#if canImport(MessageUI)
struct MailView: UIViewControllerRepresentable {
    @Binding var isShowing: Bool
    let subject: String; let recipients: [String]; let body: String
    let attachmentData: Data; let mimeType: String; let fileName: String

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.setSubject(subject)
        vc.setToRecipients(recipients)
        vc.setMessageBody(body, isHTML: false)
        vc.addAttachmentData(attachmentData, mimeType: mimeType, fileName: fileName)
        vc.mailComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let parent: MailView
        init(_ p: MailView) { self.parent = p }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) { self.parent.isShowing = false }
        }
    }
}
#endif
