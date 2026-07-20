import XCTest
@testable import CleanCore

/// Pins down the pure visible-rows projection behind the Mail Attachments
/// results list. This one function decides both what the screen shows AND
/// what the Clean button may act on — anything it hides can never be cleaned
/// — so its behavior is exercised exhaustively here. Purely in-memory values;
/// no disk access at all.
final class MailAttachmentFilteringTests: XCTestCase {
    /// Fixed reference instant so date maths never depends on wall-clock time.
    private static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func item(_ name: String, _ size: Int64, ageDays: Int? = nil) -> MailAttachment {
        MailAttachment(
            url: URL(fileURLWithPath: "/tmp/cym-mail-filter/\(name)"),
            sizeBytes: size,
            modificationDate: ageDays.map { Self.epoch.addingTimeInterval(-Double($0) * 86_400) })
    }

    private func visible(_ items: [MailAttachment],
                         query: String = "",
                         minBytes: Int64 = 0,
                         order: MailAttachmentSortOrder = .sizeLargestFirst) -> [String] {
        MailAttachmentFilter.visible(in: items, matchingName: query,
                                     minSizeBytes: minBytes, sortedBy: order)
            .map(\.name)
    }

    // MARK: - Search

    func test_emptyQuery_matchesEverything_largestFirst() {
        let items = [item("small.pdf", 10), item("big.zip", 300), item("mid.key", 40)]

        XCTAssertEqual(visible(items), ["big.zip", "mid.key", "small.pdf"])
    }

    func test_searchMatchesCaseInsensitively() {
        let items = [item("Quarterly-Report.PDF", 100), item("photo.jpg", 200)]

        XCTAssertEqual(visible(items, query: "report"), ["Quarterly-Report.PDF"])
        XCTAssertEqual(visible(items, query: "REPORT"), ["Quarterly-Report.PDF"])
    }

    func test_searchMatchesDiacriticInsensitively_bothDirections() {
        let items = [item("Résumé.pdf", 100), item("resume-final.pdf", 50), item("notes.txt", 10)]

        XCTAssertEqual(visible(items, query: "resume"), ["Résumé.pdf", "resume-final.pdf"],
                       "a plain query must match accented names")
        XCTAssertEqual(visible(items, query: "résumé"), ["Résumé.pdf", "resume-final.pdf"],
                       "an accented query must match plain names")
    }

    func test_searchIgnoresSurroundingWhitespace() {
        let items = [item("deck.key", 100), item("photo.jpg", 200)]

        XCTAssertEqual(visible(items, query: "  deck  "), ["deck.key"])
        XCTAssertEqual(visible(items, query: "   "), ["photo.jpg", "deck.key"],
                       "a whitespace-only query is no query at all")
    }

    func test_searchWithNoMatches_returnsEmpty() {
        let items = [item("deck.key", 100)]

        XCTAssertTrue(visible(items, query: "nothing-here").isEmpty)
    }

    // MARK: - Size filter

    func test_sizeFilter_dropsSmallerFiles_keepsThresholdItself() {
        let items = [item("exactly-10mb.pdf", 10_000_000),
                     item("just-under.pdf", 9_999_999),
                     item("huge.zip", 500_000_000)]

        XCTAssertEqual(visible(items, minBytes: 10_000_000),
                       ["huge.zip", "exactly-10mb.pdf"],
                       "the bound is inclusive — a file exactly at it stays visible")
    }

    func test_searchAndSizeFilterCombine() {
        let items = [item("big-report.pdf", 200_000_000),
                     item("small-report.pdf", 1_000_000),
                     item("big-video.mov", 900_000_000)]

        XCTAssertEqual(visible(items, query: "report", minBytes: 10_000_000),
                       ["big-report.pdf"])
    }

    // MARK: - Sorting

    func test_dateSort_newestFirst_undatedLast() {
        let items = [item("oldest.pdf", 999, ageDays: 300),
                     item("undated.pdf", 500),
                     item("newest.pdf", 1, ageDays: 2),
                     item("middle.pdf", 5, ageDays: 30)]

        XCTAssertEqual(visible(items, order: .dateNewestFirst),
                       ["newest.pdf", "middle.pdf", "oldest.pdf", "undated.pdf"],
                       "dated rows newest first; rows without a date sort last")
    }

    func test_dateSort_tieBreaksBySize() {
        let items = [item("small-same-day.pdf", 10, ageDays: 7),
                     item("big-same-day.pdf", 900, ageDays: 7),
                     item("undated-small.pdf", 20),
                     item("undated-big.pdf", 800)]

        XCTAssertEqual(visible(items, order: .dateNewestFirst),
                       ["big-same-day.pdf", "small-same-day.pdf",
                        "undated-big.pdf", "undated-small.pdf"],
                       "equal (or both-missing) dates fall back to largest first")
    }

    func test_sizeSort_isTheDefaultScannerOrder() {
        let items = [item("b.pdf", 200, ageDays: 1), item("a.pdf", 300, ageDays: 900)]

        XCTAssertEqual(visible(items, order: .sizeLargestFirst), ["a.pdf", "b.pdf"],
                       "size order ignores dates entirely")
    }

    // MARK: - Never widens

    /// The projection may only ever narrow or reorder its input — it must
    /// never invent rows, because the view model cleans strictly from it.
    func test_projectionNeverAddsItems() {
        let items = [item("one.pdf", 100, ageDays: 3), item("two.pdf", 50)]
        let input = Set(items.map(\.id))

        for order in [MailAttachmentSortOrder.sizeLargestFirst, .dateNewestFirst] {
            let out = MailAttachmentFilter.visible(in: items, matchingName: "pdf",
                                                   minSizeBytes: 0, sortedBy: order)
            XCTAssertTrue(Set(out.map(\.id)).isSubset(of: input))
        }
    }
}
