import SwiftUI
import CleanCore

// MARK: - Potential-issues section (report-only audit findings)

/// The "POTENTIAL ISSUES" block on the Privacy results screen: a slab header
/// and one glass card listing every audit finding, most severe first. Findings
/// are report-only — no checkboxes, no selection, nothing here can route into
/// the cleaner. The only action is opening the relevant System Settings pane.
struct PrivacyFindingsSection: View {
    let findings: [PrivacyFinding]
    /// Invoked when the user taps "Open Settings" on a finding that carries a
    /// System Settings deep link.
    let openSettings: (PrivacyFinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POTENTIAL ISSUES")
                .font(.system(size: 9.5, weight: .bold))
                .tracking(1.3)
                .foregroundStyle(Palette.slab)

            VStack(spacing: 0) {
                if findings.isEmpty {
                    allClearRow
                } else {
                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                        FindingRow(finding: finding) { openSettings(finding) }
                        if index < findings.count - 1 {
                            Rectangle().fill(Palette.hair).frame(height: 1).padding(.leading, 14)
                        }
                    }
                }
            }
            .glassCard(radius: 14)
        }
    }

    /// The quiet single row shown when the audit found nothing to report.
    private var allClearRow: some View {
        HStack(spacing: 10) {
            TagBadge(text: "All clear", color: PillTone.good.text)
            Text("No privacy issues detected")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.sub)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

// MARK: - One finding row

/// A single audit finding: title with a severity chip, one-line detail, and a
/// trailing "Open Settings" capsule when the finding has a settings deep link.
private struct FindingRow: View {
    let finding: PrivacyFinding
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(finding.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    SeverityChip(severity: finding.severity)
                }
                Text(finding.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tiny)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    // Long granted-app lists truncate at two lines — the full
                    // text is reachable on hover.
                    .help(finding.detail)
            }

            Spacer()

            if finding.settingsURLString != nil {
                CompactCapsuleButton(title: "Open Settings", action: onOpenSettings)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
    }
}

// MARK: - Severity chip

/// Tiny capsule naming a finding's severity: warn tone for warnings, blue for
/// advisories, and a neutral white-0.10 chip for informational notes.
private struct SeverityChip: View {
    let severity: PrivacyFinding.Severity

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(fill))
    }

    private var label: String {
        switch severity {
        case .warning:  return "Warning"
        case .advisory: return "Advisory"
        case .info:     return "Info"
        }
    }

    private var textColor: Color {
        switch severity {
        case .warning:  return PillTone.warn.text
        case .advisory: return PillTone.blue.text
        case .info:     return .white.opacity(0.70)
        }
    }

    private var fill: Color {
        switch severity {
        case .warning:  return PillTone.warn.fill
        case .advisory: return PillTone.blue.fill
        case .info:     return .white.opacity(0.10)
        }
    }
}
