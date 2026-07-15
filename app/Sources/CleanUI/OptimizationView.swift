import SwiftUI
import CleanCore

/// Scaffold for the Optimization module — replaced by the full implementation
/// (read-only review of launch agents/daemons and login items).
struct OptimizationView: View {
    let model: OptimizationViewModel

    init(model: OptimizationViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Optimization") { StatusPill(text: "Ready", tone: .blue) }
            Spacer()
            Orb(size: 230)
            Text("See what launches at startup")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer()
        }
        .navigationTitle("Optimization")
    }
}
