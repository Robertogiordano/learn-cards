import XCTest
@testable import LearnCore

/// Deterministic generator so option order is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class ExerciseBuilderTests: XCTestCase {
    let tisch = VocabEntry(german: "Tisch", article: .der, plural: "Tische", english: ["table"], partOfSpeech: .noun, emoji: "🪑")
    let pool = [
        VocabEntry(german: "Stuhl", article: .der, plural: "Stühle", english: ["chair"], partOfSpeech: .noun),
        VocabEntry(german: "Lampe", article: .die, plural: "Lampen", english: ["lamp"], partOfSpeech: .noun),
        VocabEntry(german: "Buch", article: .das, plural: "Bücher", english: ["book"], partOfSpeech: .noun),
        VocabEntry(german: "laufen", english: ["run"], partOfSpeech: .verb),
    ]

    func testGermanDisplayPerLevel() {
        XCTAssertEqual(tisch.germanDisplay(level: .translation), "Tisch")
        XCTAssertEqual(tisch.germanDisplay(level: .article), "der Tisch")
        XCTAssertEqual(tisch.germanDisplay(level: .plural), "der Tisch, die Tische")
        let verb = pool[3]
        XCTAssertEqual(verb.germanDisplay(level: .plural), "laufen")
    }

    func testMultipleChoiceHasFourUniqueOptionsIncludingAnswer() {
        for level in StudyLevel.allCases {
            var rng = SeededGenerator(state: 42)
            let exercise = ExerciseBuilder.make(kind: .multipleChoice, entry: tisch, pool: pool + [tisch], level: level, using: &rng)
            XCTAssertEqual(exercise.options.count, 4)
            XCTAssertEqual(Set(exercise.options).count, 4)
            let index = try! XCTUnwrap(exercise.correctIndex)
            XCTAssertEqual(exercise.options[index], tisch.germanDisplay(level: level))
        }
    }

    func testLevelTwoIncludesWrongArticleOfSameWord() {
        var rng = SeededGenerator(state: 7)
        let exercise = ExerciseBuilder.make(kind: .multipleChoice, entry: tisch, pool: pool, level: .article, using: &rng)
        XCTAssertTrue(exercise.options.contains { $0 == "die Tisch" || $0 == "das Tisch" })
    }

    func testTinyPoolFallsBackGracefully() {
        var rng = SeededGenerator(state: 1)
        let verb = pool[3]
        let exercise = ExerciseBuilder.make(kind: .multipleChoice, entry: verb, pool: [verb], level: .translation, using: &rng)
        XCTAssertEqual(exercise.kind, .typeGerman)
    }

    func testPromptsAndRequirements() {
        let typeEnglish = Exercise(kind: .typeEnglish, entry: tisch, level: .plural)
        XCTAssertEqual(typeEnglish.prompt, "der Tisch, die Tische")
        XCTAssertFalse(typeEnglish.requiresArticle)
        let typeGerman = Exercise(kind: .typeGerman, entry: tisch, level: .plural)
        XCTAssertEqual(typeGerman.prompt, "table")
        XCTAssertTrue(typeGerman.requiresArticle)
        XCTAssertTrue(typeGerman.requiresPlural)
    }

    func testPlausiblePlurals() {
        let fakes = ExerciseBuilder.plausiblePlurals(for: "Apfel", excluding: "Äpfel")
        XCTAssertFalse(fakes.contains("Äpfel"))
        XCTAssertTrue(fakes.contains("Apfeln"))
        XCTAssertEqual(ExerciseBuilder.addUmlaut(to: "Haus"), "Häus")
        XCTAssertEqual(ExerciseBuilder.addUmlaut(to: "Buch"), "Büch")
    }
}
