import SwiftUI
import CleanCore

/// Scaffold for the Mail Attachments module — replaced by the full
/// implementation (scan Mail's local attachment copies, clean to Trash).
struct MailAttachmentsView: View {
    let model: MailAttachmentsViewModel

    init(model: MailAttachmentsViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Mail Attachments") { StatusPill(text: "Ready", tone: .blue) }
            Spacer()
            Orb(size: 230)
            Text("Reclaim space from Mail downloads")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer()
        }
        .navigationTitle("Mail Attachments")
    }
}
