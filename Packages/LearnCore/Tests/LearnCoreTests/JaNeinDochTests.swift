import XCTest
@testable import LearnCore

final class JaNeinDochTests: XCTestCase {
    let drucker = VocabEntry(german: "Drucker", article: .der, english: ["printer"], partOfSpeech: .noun)
    let zeitung = VocabEntry(german: "Zeitung", article: .die, english: ["newspaper"], partOfSpeech: .noun)
    let buch = VocabEntry(german: "Buch", article: .das, english: ["book"], partOfSpeech: .noun)
    let laufen = VocabEntry(german: "laufen", english: ["run"], partOfSpeech: .verb)
    let kochen = VerbEntry(infinitive: "kochen", english: "to cook",
                           forms: ["koche", "kochst", "kocht", "kochen", "kocht", "kochen"])
    let aufstehen = VerbEntry(infinitive: "aufstehen", english: "to get up",
                              forms: ["stehe auf", "stehst auf", "steht auf", "stehen auf", "steht auf", "stehen auf"],
                              group: .separable)
    let haben = ObjectFrame.all[0]

    func testAnswerWordFollowsTheWorksheet() {
        let positive = YesNoQuiz.question(noun: drucker, frame: haben, negated: false, wantsYes: true)!
        XCTAssertEqual(positive.question, "Hast du einen Drucker?")
        XCTAssertEqual(positive.answer, "Ja, ich habe einen Drucker.")

        let refused = YesNoQuiz.question(noun: drucker, frame: haben, negated: false, wantsYes: false)!
        XCTAssertEqual(refused.answer, "Nein, ich habe keinen Drucker.")

        let contradicted = YesNoQuiz.question(noun: drucker, frame: haben, negated: true, wantsYes: true)!
        XCTAssertEqual(contradicted.question, "Hast du keinen Drucker?")
        XCTAssertEqual(contradicted.answerWord, .doch)
        XCTAssertEqual(contradicted.answer, "Doch, ich habe einen Drucker.")

        let confirmed = YesNoQuiz.question(noun: drucker, frame: haben, negated: true, wantsYes: false)!
        XCTAssertEqual(confirmed.answer, "Nein, ich habe keinen Drucker.")
    }

    func testArticlesInTheAccusative() {
        XCTAssertEqual(YesNoQuiz.question(noun: zeitung, frame: haben, negated: true, wantsYes: false)!.answer,
                       "Nein, ich habe keine Zeitung.")
        XCTAssertEqual(YesNoQuiz.question(noun: buch, frame: haben, negated: false, wantsYes: true)!.answer,
                       "Ja, ich habe ein Buch.")
    }

    func testVerbQuestions() {
        let question = YesNoQuiz.question(verb: kochen, negated: true, wantsYes: false)
        XCTAssertEqual(question.question, "Kochst du nicht gern?")
        XCTAssertEqual(question.answer, "Nein, ich koche nicht gern.")
        XCTAssertEqual(YesNoQuiz.question(verb: kochen, negated: true, wantsYes: true).answer, "Doch, ich koche gern.")
    }

    func testCheckIsStrictOnOpeningWordAndNegation() {
        let question = YesNoQuiz.question(noun: drucker, frame: haben, negated: true, wantsYes: true)!
        XCTAssertEqual(question.check("doch ich habe einen drucker"), .correct)
        XCTAssertEqual(question.check("Doch, ich habe einen Druker."), .almost)
        XCTAssertEqual(question.check("Ja, ich habe einen Drucker."), .wrong)
        XCTAssertEqual(question.check("Doch, ich habe keinen Drucker."), .wrong)
        XCTAssertEqual(question.check(""), .wrong)
    }

    func testOptionsContainTheAnswerOnce() {
        let question = YesNoQuiz.question(noun: drucker, frame: haben, negated: false, wantsYes: false)!
        var rng = SeededGenerator(state: 3)
        let options = question.options(using: &rng)
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(Set(options).count, 4)
        XCTAssertEqual(options.filter { $0 == question.answer }.count, 1)
    }

    func testMakeUsesOnlySuitableWordsAndBalancesShapes() {
        var rng = SeededGenerator(state: 7)
        let questions = YesNoQuiz.make(count: 12, nouns: [drucker, zeitung, buch, laufen],
                                       verbs: [kochen, aufstehen], using: &rng)
        XCTAssertFalse(questions.isEmpty)
        XCTAssertFalse(questions.contains { $0.question.contains("laufen") || $0.question.contains("stehst") })
        XCTAssertTrue(questions.contains { $0.answerWord == .doch })
        XCTAssertTrue(questions.contains { $0.answerWord == .ja })
        XCTAssertTrue(questions.contains { $0.answerWord == .nein })
    }

    func testMakeWithNothingSuitable() {
        var rng = SeededGenerator(state: 1)
        XCTAssertTrue(YesNoQuiz.make(count: 5, nouns: [laufen], verbs: [aufstehen], using: &rng).isEmpty)
    }
}
