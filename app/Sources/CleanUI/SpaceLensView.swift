import SwiftUI
import CleanCore

/// Scaffold for the Space Lens module — replaced by the full implementation
/// (read-only folder-size explorer with drill-down).
struct SpaceLensView: View {
    let model: SpaceLensViewModel

    init(model: SpaceLensViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Space Lens") { StatusPill(text: "Ready", tone: .blue) }
            Spacer()
            Orb(size: 230)
            Text("See where your space went")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer()
        }
        .navigationTitle("Space Lens")
    }
}
