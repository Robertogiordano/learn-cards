import XCTest
@testable import LearnCore

final class WordOrderTests: XCTestCase {
    let aufstehen = VerbEntry(infinitive: "aufstehen", english: "to get up",
                              forms: ["stehe auf", "stehst auf", "steht auf", "stehen auf", "steht auf", "stehen auf"],
                              group: .separable)
    let kochen = VerbEntry(infinitive: "kochen", english: "to cook",
                           forms: ["koche", "kochst", "kocht", "kochen", "kocht", "kochen"])
    let waschen = VerbEntry(infinitive: "sich waschen", english: "to wash",
                            forms: ["wasche mich", "wäschst dich", "wäscht sich", "waschen uns", "wascht euch", "waschen sich"],
                            group: .reflexive)
    let drucker = VocabEntry(german: "Drucker", article: .der, english: ["printer"], partOfSpeech: .noun)

    func testStatementAcceptsSubjectOrTimeFirstWithPrefixAtTheEnd() {
        var rng = SeededGenerator(state: 2)
        for _ in 0..<20 {
            let exercise = WordOrderQuiz.exercise(pattern: .statement, verb: aufstehen, object: nil, emoji: "⏰", using: &rng)!
            XCTAssertEqual(exercise.accepted.count, 2)
            XCTAssertTrue(exercise.accepted.allSatisfy { $0.hasSuffix(" auf.") })
            XCTAssertEqual(exercise.tiles.count, 4)
            XCTAssertTrue(exercise.rule.hasSuffix("The prefix auf goes to the end."))
            for sentence in exercise.accepted {
                let words = PhraseChecker.tokens(sentence)
                XCTAssertTrue(words.contains("stehe") || words.contains("stehst") || words.contains("steht") || words.contains("stehen"))
            }
        }
    }

    func testCheck() {
        let exercise = WordOrderExercise(pattern: .statement, tiles: ["auf", "ich", "um 8 Uhr", "stehe"],
                                         answer: "Ich stehe um 8 Uhr auf.",
                                         accepted: ["Ich stehe um 8 Uhr auf.", "Um 8 Uhr stehe ich auf."], emoji: "⏰")
        XCTAssertEqual(exercise.check(["ich", "stehe", "um 8 Uhr", "auf"]), .correct)
        XCTAssertEqual(exercise.check(["um 8 Uhr", "stehe", "ich", "auf"]), .correct)
        XCTAssertEqual(exercise.check(["um 8 Uhr", "ich", "stehe", "auf"]), .wrong)
        XCTAssertEqual(exercise.check(["ich", "stehe", "auf", "um 8 Uhr"]), .wrong)
    }

    func testQuestionsPutTheVerbFirstOrAfterTheQuestionWord() {
        var rng = SeededGenerator(state: 5)
        let yesNo = WordOrderQuiz.exercise(pattern: .yesNoQuestion, verb: WordOrderQuiz.objectVerbs[0],
                                           object: "einen Drucker", emoji: "🖨️", using: &rng)!
        XCTAssertTrue(yesNo.answer.hasPrefix("Kauf"))
        XCTAssertTrue(yesNo.answer.hasSuffix(" einen Drucker?"))

        let w = WordOrderQuiz.exercise(pattern: .wQuestion, verb: aufstehen, object: nil, emoji: "⏰", using: &rng)!
        XCTAssertTrue(w.answer.hasPrefix("Wann ") || w.answer.hasPrefix("Um wie viel Uhr "))
        XCTAssertTrue(w.answer.hasSuffix(" auf?"))
        XCTAssertFalse(w.answer.contains(" ich "))
    }

    func testMakeSkipsReflexiveVerbsAndMixesPatterns() {
        var rng = SeededGenerator(state: 9)
        let exercises = WordOrderQuiz.make(count: 9, pattern: nil, nouns: [drucker],
                                           verbs: [aufstehen, kochen, waschen], using: &rng)
        XCTAssertEqual(exercises.count, 9)
        XCTAssertFalse(exercises.contains { $0.answer.contains("wasch") })
        XCTAssertEqual(Set(exercises.map(\.pattern)).count, 3)
        XCTAssertTrue(exercises.allSatisfy { $0.accepted.contains($0.answer) })
    }

    func testMakeWithNothingSuitable() {
        var rng = SeededGenerator(state: 1)
        XCTAssertTrue(WordOrderQuiz.make(count: 5, pattern: nil, nouns: [], verbs: [waschen], using: &rng).isEmpty)
    }
}
