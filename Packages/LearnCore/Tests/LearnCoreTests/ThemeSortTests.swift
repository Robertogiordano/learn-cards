import XCTest
@testable import LearnCore

final class ThemeSortTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var stats: [ThemeStats] {
        [
            ThemeStats(theme: "Food", wordCount: 12, newCount: 0, lastUpdated: now.addingTimeInterval(-86_400 * 5)),
            ThemeStats(theme: VocabEntry.defaultCategory, wordCount: 30, newCount: 0, lastUpdated: now),
            ThemeStats(theme: "Travel", wordCount: 4, newCount: 2, lastUpdated: now.addingTimeInterval(-86_400 * 10)),
            ThemeStats(theme: "Home", wordCount: 12, newCount: 0, lastUpdated: now.addingTimeInterval(-3_600)),
        ]
    }

    func testStandardPutsNewWordsFirstAndMiscLast() {
        XCTAssertEqual(ThemeOrdering.themes(stats, by: .standard), ["Travel", "Food", "Home", VocabEntry.defaultCategory])
    }

    func testAlphabetical() {
        XCTAssertEqual(ThemeOrdering.themes(stats, by: .alphabetical), ["Food", "Home", "Travel", VocabEntry.defaultCategory])
    }

    func testLastUpdatedNewestFirst() {
        XCTAssertEqual(ThemeOrdering.themes(stats, by: .lastUpdated), [VocabEntry.defaultCategory, "Home", "Food", "Travel"])
    }

    func testWordCountLargestFirstTiesAlphabetical() {
        XCTAssertEqual(ThemeOrdering.themes(stats, by: .wordCount), [VocabEntry.defaultCategory, "Food", "Home", "Travel"])
    }
}
