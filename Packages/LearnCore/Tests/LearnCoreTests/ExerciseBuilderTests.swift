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
    let laufen = VocabEntry(german: "laufen", english: ["run"], partOfSpeech: .verb)
    lazy var pool = [
        VocabEntry(german: "Stuhl", article: .der, plural: "Stühle", english: ["chair"], partOfSpeech: .noun),
        VocabEntry(german: "Lampe", article: .die, plural: "Lampen", english: ["lamp"], partOfSpeech: .noun),
        VocabEntry(german: "Buch", article: .das, plural: "Bücher", english: ["book"], partOfSpeech: .noun),
        laufen,
        tisch,
    ]

    func testDisplayHelpers() {
        XCTAssertEqual(tisch.withArticle, "der Tisch")
        XCTAssertEqual(tisch.withIndefiniteArticle, "ein Tisch")
        XCTAssertEqual(tisch.pluralWithArticle, "die Tische")
        XCTAssertEqual(tisch.fullGerman, "der Tisch, die Tische")
        XCTAssertEqual(laufen.fullGerman, "laufen")
        XCTAssertEqual(Article.die.indefinite, "eine")
        XCTAssertEqual(Article.das.indefinite, "ein")
    }

    func testAreaApplicability() {
        let milch = VocabEntry(german: "Milch", article: .die, english: ["milk"], partOfSpeech: .noun)
        XCTAssertTrue(StudyArea.article.isApplicable(to: tisch))
        XCTAssertFalse(StudyArea.article.isApplicable(to: laufen))
        XCTAssertTrue(StudyArea.plural.isApplicable(to: tisch))
        XCTAssertFalse(StudyArea.plural.isApplicable(to: milch))
        XCTAssertTrue(StudyArea.translation.isApplicable(to: laufen))
        XCTAssertFalse(StudyArea.article.kinds.contains(.typeEnglish))
    }

    func testTranslationChoice() throws {
        var rng = SeededGenerator(state: 42)
        let exercise = ExerciseBuilder.make(area: .translation, kind: .multipleChoice, entry: tisch, pool: pool, using: &rng)
        XCTAssertEqual(exercise.options.count, 4)
        XCTAssertEqual(Set(exercise.options).count, 4)
        XCTAssertEqual(exercise.options[try XCTUnwrap(exercise.correctIndex)], "Tisch")
        XCTAssertEqual(exercise.prompt, "table")
    }

    func testArticleChoiceListsThreeGenders() throws {
        var rng = SeededGenerator(state: 1)
        let exercise = ExerciseBuilder.make(area: .article, kind: .multipleChoice, entry: tisch, pool: pool, using: &rng)
        XCTAssertEqual(exercise.options, ["der Tisch / ein Tisch", "die Tisch / eine Tisch", "das Tisch / ein Tisch"])
        XCTAssertEqual(exercise.optionDetails, ["maskulin", "feminin", "neutral"])
        XCTAssertEqual(exercise.correctIndex, 0)
        XCTAssertEqual(exercise.prompt, "Tisch")
        XCTAssertEqual(exercise.expectedAnswer, "der Tisch / ein Tisch")
    }

    func testPluralChoice() throws {
        var rng = SeededGenerator(state: 7)
        let exercise = ExerciseBuilder.make(area: .plural, kind: .multipleChoice, entry: tisch, pool: pool, using: &rng)
        XCTAssertEqual(exercise.options.count, 4)
        XCTAssertEqual(Set(exercise.options).count, 4)
        XCTAssertTrue(exercise.options.allSatisfy { $0.hasPrefix("die ") })
        XCTAssertEqual(exercise.options[try XCTUnwrap(exercise.correctIndex)], "die Tische")
        XCTAssertEqual(exercise.prompt, "der Tisch")
    }

    func testTinyPoolFallsBackToTyping() {
        var rng = SeededGenerator(state: 1)
        let exercise = ExerciseBuilder.make(area: .translation, kind: .multipleChoice, entry: laufen, pool: [laufen], using: &rng)
        XCTAssertEqual(exercise.kind, .typeGerman)
    }

    func testTypeEnglishPrompt() {
        let exercise = Exercise(area: .translation, kind: .typeEnglish, entry: tisch)
        XCTAssertEqual(exercise.prompt, "Tisch")
        XCTAssertEqual(exercise.expectedAnswer, "table")
    }

    func testPlausiblePlurals() {
        let fakes = ExerciseBuilder.plausiblePlurals(for: "Apfel", excluding: "Äpfel")
        XCTAssertFalse(fakes.contains("Äpfel"))
        XCTAssertTrue(fakes.contains("Apfeln"))
        XCTAssertFalse(ExerciseBuilder.plausiblePlurals(for: "Lampe", excluding: "Lampen").contains("Lampen"))
        XCTAssertEqual(ExerciseBuilder.addUmlaut(to: "Haus"), "Häus")
        XCTAssertEqual(ExerciseBuilder.addUmlaut(to: "Buch"), "Büch")
    }
}
