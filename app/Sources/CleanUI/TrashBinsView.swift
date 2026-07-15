import SwiftUI
import CleanCore

/// Scaffold for the Trash Bins module — replaced by the full implementation
/// (review Trash contents, empty selected items permanently, with confirmation).
struct TrashBinsView: View {
    let model: TrashBinsViewModel

    init(model: TrashBinsViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Trash Bins") { StatusPill(text: "Ready", tone: .blue) }
            Spacer()
            Orb(size: 230)
            Text("Review and empty your Trash")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer()
        }
        .navigationTitle("Trash Bins")
    }
}
