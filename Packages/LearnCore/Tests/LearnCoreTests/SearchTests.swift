import XCTest
@testable import LearnCore

final class SearchTests: XCTestCase {
    func testGermanSpellingDoesNotMatter() {
        XCTAssertTrue(VocabularySearch.matches("strasse", in: ["die Straße"]))
        XCTAssertTrue(VocabularySearch.matches("Straße", in: ["Strasse"]))
        XCTAssertTrue(VocabularySearch.matches("fahrt", in: ["fährt"]))
        XCTAssertTrue(VocabularySearch.matches("faehrt", in: ["fährt"]))
        XCTAssertTrue(VocabularySearch.matches("FÄHR", in: ["du fährst"]))
    }

    func testAnyFieldAndNoMatch() {
        XCTAssertTrue(VocabularySearch.matches("table", in: ["Tisch", "table, desk"]))
        XCTAssertTrue(VocabularySearch.matches("wie heisst", in: ["Wie heißt du?"]))
        XCTAssertFalse(VocabularySearch.matches("stuhl", in: ["Tisch", "table"]))
        XCTAssertFalse(VocabularySearch.matches("  ", in: ["Tisch"]))
    }
}
