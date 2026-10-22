import XCTest
@testable import LearnCore

final class ExtractionParserTests: XCTestCase {
    func testParsesWrappedObject() throws {
        let json = """
        {"words": [
          {"german": "Tisch", "article": "der", "plural": "Tische", "english": ["table", "desk"], "partOfSpeech": "noun", "emoji": "🪑"},
          {"german": "gehen", "article": null, "plural": null, "english": ["go"], "partOfSpeech": "verb", "emoji": "🚶"}
        ]}
        """
        let entries = try ExtractionParser.parse(json)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].german, "Tisch")
        XCTAssertEqual(entries[0].article, .der)
        XCTAssertEqual(entries[0].plural, "Tische")
        XCTAssertEqual(entries[0].english, ["table", "desk"])
        XCTAssertEqual(entries[1].partOfSpeech, .verb)
        XCTAssertNil(entries[1].plural)
    }

    func testToleratesCodeFencesAndQuirks() throws {
        let reply = """
        Here you go:
        ```json
        [
          {"german": "die Lampe", "plural": "die Lampen", "english": "lamp, light", "partOfSpeech": "Noun", "emoji": "💡✨"},
          {"german": "buch", "article": "das", "plural": "-", "english": ["book"], "emoji": ""},
          {"german": "Lampe", "article": "die", "english": ["lamp"]},
          {"german": "", "english": ["nothing"]},
          {"german": "schnell", "english": []}
        ]
        ```
        """
        let entries = try ExtractionParser.parse(reply)
        XCTAssertEqual(entries.count, 2)

        let lampe = entries[0]
        XCTAssertEqual(lampe.german, "Lampe")
        XCTAssertEqual(lampe.article, .die)
        XCTAssertEqual(lampe.plural, "Lampen")
        XCTAssertEqual(lampe.english, ["lamp", "light"])
        XCTAssertEqual(lampe.emoji, "💡")

        let buch = entries[1]
        XCTAssertEqual(buch.german, "Buch")
        XCTAssertEqual(buch.partOfSpeech, .noun)
        XCTAssertNil(buch.plural)
        XCTAssertEqual(buch.emoji, "📝")
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try ExtractionParser.parse("Sorry, I cannot read this image.")) { error in
            XCTAssertEqual(error as? ExtractionParser.ParseError, .noJSON)
        }
    }

    func testSchemaIsSerializable() throws {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(ExtractionPrompt.responseSchema))
    }
}
