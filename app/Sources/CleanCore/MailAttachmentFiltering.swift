import Foundation

// MARK: - Sort order

/// How the Mail Attachments results list is ordered.
public enum MailAttachmentSortOrder: Sendable, Equatable {
    /// Largest first — the scanner's own order.
    case sizeLargestFirst
    /// Newest first; attachments without a date sort last.
    case dateNewestFirst
}

// MARK: - Visible-rows projection

/// The pure projection behind the Mail Attachments results list.
///
/// Safety rationale: this one function decides BOTH what the screen shows and
/// what the Clean button may act on — the view model feeds `clean()` strictly
/// from this projection, so a row hidden by search or size filters can never
/// be swept up invisibly. Centralising it here keeps that guarantee testable.
public enum MailAttachmentFilter {
    /// Attachments passing the name search and size threshold, in the chosen
    /// order.
    ///
    /// - Parameters:
    ///   - query: filename search; case- and diacritic-insensitive
    ///     (Finder-style). Surrounding whitespace is ignored; an empty or
    ///     whitespace-only query matches everything.
    ///   - minSizeBytes: inclusive lower bound — a file exactly at the
    ///     threshold stays visible.
    public static func visible(
        in attachments: [MailAttachment],
        matchingName query: String,
        minSizeBytes: Int64,
        sortedBy order: MailAttachmentSortOrder
    ) -> [MailAttachment] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = attachments.filter { attachment in
            guard attachment.sizeBytes >= minSizeBytes else { return false }
            if !trimmed.isEmpty, !attachment.name.localizedStandardContains(trimmed) {
                return false
            }
            return true
        }

        switch order {
        case .sizeLargestFirst:
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .dateNewestFirst:
            return filtered.sorted { a, b in
                switch (a.modificationDate, b.modificationDate) {
                case let (da?, db?) where da != db:
                    return da > db
                case (.some, .none):
                    return true   // dated rows come before undated ones
                case (.none, .some):
                    return false
                default:
                    return a.sizeBytes > b.sizeBytes   // deterministic tie-break
                }
            }
        }
    }
}
