import SwiftUI
import CleanCore

/// Scaffold for the Maintenance module — replaced by the full implementation
/// (run a fixed set of safe, no-sudo maintenance tasks).
struct MaintenanceView: View {
    let model: MaintenanceViewModel

    init(model: MaintenanceViewModel) { self.model = model }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Maintenance") { StatusPill(text: "Ready", tone: .blue) }
            Spacer()
            Orb(size: 230)
            Text("Run safe maintenance tasks")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 6)
            Spacer()
        }
        .navigationTitle("Maintenance")
    }
}
