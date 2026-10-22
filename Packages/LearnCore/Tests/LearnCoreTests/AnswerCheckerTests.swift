import XCTest
@testable import LearnCore

final class AnswerCheckerTests: XCTestCase {
    let tisch = VocabEntry(german: "Tisch", article: .der, plural: "Tische", english: ["table", "desk"], partOfSpeech: .noun)
    let apfel = VocabEntry(german: "Apfel", article: .der, plural: "Äpfel", english: ["apple"], partOfSpeech: .noun)
    let gehen = VocabEntry(german: "gehen", english: ["to go", "walk"], partOfSpeech: .verb)
    let strasse = VocabEntry(german: "Straße", article: .die, plural: "Straßen", english: ["street"], partOfSpeech: .noun)

    func testNormalize() {
        XCTAssertEqual(AnswerChecker.normalize("  Der   Tisch! "), "der tisch")
        XCTAssertEqual(AnswerChecker.normalize("„Hallo“, Welt."), "hallo welt")
    }

    func testCompareGermanVariants() {
        XCTAssertEqual(AnswerChecker.compareGerman("tisch", "Tisch"), .correct)
        XCTAssertEqual(AnswerChecker.compareGerman("Strasse", "Straße"), .correct)
        XCTAssertEqual(AnswerChecker.compareGerman("Aepfel", "Äpfel"), .correct)
        XCTAssertEqual(AnswerChecker.compareGerman("Apfel", "Äpfel"), .almost)
        XCTAssertEqual(AnswerChecker.compareGerman("Tish", "Tisch"), .almost)
        XCTAssertEqual(AnswerChecker.compareGerman("Stuhl", "Tisch"), .wrong)
        XCTAssertEqual(AnswerChecker.compareGerman("", "Tisch"), .wrong)
        // Short words: one letter off is another word, not a typo.
        XCTAssertEqual(AnswerChecker.compareGerman("Eid", "Ei"), .wrong)
    }

    func testLevelOneIgnoresArticle() {
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(word: "Tisch"), entry: tisch, level: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .die, word: "Tisch"), entry: tisch, level: .translation), .correct)
    }

    func testLevelTwoRequiresArticle() {
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Tisch"), entry: tisch, level: .article), .correct)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .das, word: "Tisch"), entry: tisch, level: .article), .wrong)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(word: "Tisch"), entry: tisch, level: .article), .wrong)
        // Article typed into the word field.
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(word: "der Tisch"), entry: tisch, level: .article), .correct)
        // Verbs have no article: level 2 falls back to the word.
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(word: "gehen"), entry: gehen, level: .article), .correct)
    }

    func testLevelThreeRequiresPlural() {
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Apfel", plural: "Äpfel"), entry: apfel, level: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Apfel", plural: "die Aepfel"), entry: apfel, level: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Apfel", plural: "Apfel"), entry: apfel, level: .plural), .almost)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Apfel", plural: "Apfeln"), entry: apfel, level: .plural), .wrong)
        XCTAssertEqual(AnswerChecker.checkGerman(GermanAnswer(article: .der, word: "Apfel"), entry: apfel, level: .plural), .wrong)
    }

    func testCompareEnglish() {
        XCTAssertEqual(AnswerChecker.compareEnglish("desk", accepted: tisch.english), .correct)
        XCTAssertEqual(AnswerChecker.compareEnglish("the table", accepted: tisch.english), .correct)
        XCTAssertEqual(AnswerChecker.compareEnglish("go", accepted: gehen.english), .correct)
        XCTAssertEqual(AnswerChecker.compareEnglish("to walk", accepted: gehen.english), .correct)
        XCTAssertEqual(AnswerChecker.compareEnglish("tabl", accepted: tisch.english), .almost)
        XCTAssertEqual(AnswerChecker.compareEnglish("chair", accepted: tisch.english), .wrong)
        XCTAssertEqual(AnswerChecker.compareEnglish("lane", accepted: ["street / road"]), .wrong)
        XCTAssertEqual(AnswerChecker.compareEnglish("road", accepted: ["street / road"]), .correct)
    }

    func testSpoken() {
        XCTAssertEqual(AnswerChecker.checkSpoken(["Tisch"], entry: tisch, level: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["der Tisch"], entry: tisch, level: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["Der Tisch."], entry: tisch, level: .article), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Tisch"], entry: tisch, level: .article), .wrong)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Tisch", "der Tisch"], entry: tisch, level: .article), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["der Tisch, die Tische"], entry: tisch, level: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Straße die Straßen"], entry: strasse, level: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken([], entry: tisch, level: .translation), .wrong)
    }

    func testSpokenCompoundSplitByRecognizer() {
        let tuer = VocabEntry(german: "Haustür", article: .die, plural: "Haustüren", english: ["front door"], partOfSpeech: .noun)
        XCTAssertEqual(AnswerChecker.checkSpoken(["Haus Tür"], entry: tuer, level: .translation), .correct)
    }
}
