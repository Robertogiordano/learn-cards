import XCTest
@testable import LearnCore

final class EnglishGlossTests: XCTestCase {
    let drucker = VocabEntry(german: "Drucker", article: .der, english: ["printer"], partOfSpeech: .noun)
    let apfel = VocabEntry(german: "Apfel", article: .der, english: ["the apple", "apples"], partOfSpeech: .noun)
    let kochen = VerbEntry(infinitive: "kochen", english: "to cook, to make (food)",
                           forms: ["koche", "kochst", "kocht", "kochen", "kocht", "kochen"])
    let aufstehen = VerbEntry(infinitive: "aufstehen", english: "to get up",
                              forms: ["stehe auf", "stehst auf", "steht auf", "stehen auf", "steht auf", "stehen auf"],
                              group: .separable)

    func testHelpers() {
        XCTAssertEqual(EnglishGloss.verbBase("to cook, to make (food)"), "cook")
        XCTAssertEqual(EnglishGloss.verbBase("to look for"), "look for")
        XCTAssertNil(EnglishGloss.verbBase(""))
        XCTAssertEqual(EnglishGloss.indefinite("the apple"), "an apple")
        XCTAssertEqual(EnglishGloss.indefinite("printer (machine)"), "a printer")
        XCTAssertEqual(EnglishGloss.thirdPerson("get up"), "gets up")
        XCTAssertEqual(EnglishGloss.thirdPerson("watch"), "watches")
        XCTAssertEqual(EnglishGloss.thirdPerson("study"), "studies")
        XCTAssertEqual(EnglishGloss.thirdPerson("play"), "plays")
        XCTAssertEqual(EnglishGloss.thirdPerson("have"), "has")
    }

    func testYesNoQuestionsAndAnswers() {
        let haben = ObjectFrame.all[0]
        let doch = YesNoQuiz.question(noun: drucker, frame: haben, negated: true, wantsYes: true)!
        XCTAssertEqual(doch.englishQuestion, "Don't you have a printer?")
        XCTAssertEqual(doch.englishAnswer, "Yes, I do have a printer.")
        XCTAssertEqual(doch.english(for: "Nein, ich habe keinen Drucker."), "No, I don't have a printer.")
        XCTAssertEqual(doch.english(for: "Ja, ich habe einen Drucker."), "Yes, I have a printer.")

        let modal = YesNoQuiz.question(noun: apfel, frame: ObjectFrame.all[2], negated: false, wantsYes: false)!
        XCTAssertEqual(modal.englishQuestion, "Would you like an apple?")
        XCTAssertEqual(modal.englishAnswer, "No, I wouldn't like an apple.")

        let gern = YesNoQuiz.question(verb: kochen, negated: true, wantsYes: false)
        XCTAssertEqual(gern.englishQuestion, "Don't you like to cook?")
        XCTAssertEqual(gern.englishAnswer, "No, I don't like to cook.")
    }

    func testNoTranslationWithoutEnglish() {
        let bare = VocabEntry(german: "Ding", article: .das, english: [], partOfSpeech: .noun)
        let question = YesNoQuiz.question(noun: bare, frame: ObjectFrame.all[0], negated: false, wantsYes: true)!
        XCTAssertNil(question.englishQuestion)
        XCTAssertNil(question.englishAnswer)
    }

    func testWordOrderSentences() {
        var rng = SeededGenerator(state: 4)
        for _ in 0..<30 {
            let statement = WordOrderQuiz.exercise(pattern: .statement, verb: aufstehen, object: nil, emoji: "⏰", using: &rng)!
            let english = try! XCTUnwrap(statement.english)
            XCTAssertTrue(english.contains("get up ") || english.contains("gets up "), english)
            XCTAssertTrue(english.hasSuffix("."))

            let yesNo = WordOrderQuiz.exercise(pattern: .yesNoQuestion, verb: WordOrderQuiz.objectVerbs[0],
                                               object: "einen Drucker", objectEnglish: "a printer", emoji: "🖨️", using: &rng)!
            XCTAssertTrue(yesNo.english!.hasPrefix("Do ") || yesNo.english!.hasPrefix("Does "), yesNo.english!)
            XCTAssertTrue(yesNo.english!.contains(" buy a printer "), yesNo.english!)

            let w = WordOrderQuiz.exercise(pattern: .wQuestion, verb: kochen, object: nil, emoji: "🍳", using: &rng)!
            XCTAssertTrue(w.english!.hasPrefix("When do") || w.english!.hasPrefix("At what time do"), w.english!)
        }
        let unknown = WordOrderQuiz.exercise(pattern: .statement, verb: WordOrderQuiz.objectVerbs[0],
                                             object: "ein Ding", objectEnglish: nil, emoji: "📦", using: &rng)!
        XCTAssertNil(unknown.english)
    }

    func testThirdPersonStatement() {
        var rng = SeededGenerator(state: 1)
        var seen = false
        for _ in 0..<60 {
            let exercise = WordOrderQuiz.exercise(pattern: .statement, verb: kochen, object: nil, emoji: "🍳", using: &rng)!
            if exercise.answer.contains("Laura") {
                XCTAssertTrue(exercise.english!.hasPrefix("Laura cooks "), exercise.english!)
                seen = true
            }
            if exercise.answer.contains("Tom und Anna") {
                XCTAssertTrue(exercise.english!.hasPrefix("Tom and Anna cook "), exercise.english!)
            }
        }
        XCTAssertTrue(seen)
    }
}
