import XCTest
@testable import LearnCore

final class AnswerCheckerTests: XCTestCase {
    let tisch = VocabEntry(german: "Tisch", article: .der, plural: "Tische", english: ["table", "desk"], partOfSpeech: .noun)
    let lampe = VocabEntry(german: "Lampe", article: .die, plural: "Lampen", english: ["lamp"], partOfSpeech: .noun)
    let buch = VocabEntry(german: "Buch", article: .das, plural: "Bücher", english: ["book"], partOfSpeech: .noun)
    let apfel = VocabEntry(german: "Apfel", article: .der, plural: "Äpfel", english: ["apple"], partOfSpeech: .noun)
    let gehen = VocabEntry(german: "gehen", english: ["to go", "walk"], partOfSpeech: .verb)

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

    func testTranslation() {
        XCTAssertEqual(AnswerChecker.checkTranslation("Tisch", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkTranslation("die Tisch", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkTranslation("gehen", entry: gehen), .correct)
        XCTAssertEqual(AnswerChecker.checkTranslation("Stuhl", entry: tisch), .wrong)
    }

    func testArticle() {
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "der", indefinite: "ein", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "Der Tisch", indefinite: "ein Tisch", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "die", indefinite: "eine", entry: lampe), .correct)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "das", indefinite: "ein", entry: buch), .correct)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "der", indefinite: "eine", entry: tisch), .wrong)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "das", indefinite: "ein", entry: tisch), .wrong)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "die", indefinite: "ein", entry: lampe), .wrong)
        XCTAssertEqual(AnswerChecker.checkArticle(definite: "der", indefinite: "ein", entry: gehen), .wrong)
    }

    func testPlural() {
        XCTAssertEqual(AnswerChecker.checkPlural("Tische", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkPlural("die Tische", entry: tisch), .correct)
        XCTAssertEqual(AnswerChecker.checkPlural("Aepfel", entry: apfel), .correct)
        XCTAssertEqual(AnswerChecker.checkPlural("Apfel", entry: apfel), .almost)
        XCTAssertEqual(AnswerChecker.checkPlural("Apfeln", entry: apfel), .wrong)
        XCTAssertEqual(AnswerChecker.checkPlural("Tisch", entry: gehen), .wrong)
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

    func testSpokenTranslation() {
        XCTAssertEqual(AnswerChecker.checkSpoken(["Tisch"], entry: tisch, area: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["der Tisch."], entry: tisch, area: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["Stuhl", "Tisch"], entry: tisch, area: .translation), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken([], entry: tisch, area: .translation), .wrong)
        let tuer = VocabEntry(german: "Haustür", article: .die, plural: "Haustüren", english: ["front door"], partOfSpeech: .noun)
        XCTAssertEqual(AnswerChecker.checkSpoken(["Haus Tür"], entry: tuer, area: .translation), .correct)
    }

    func testSpokenArticle() {
        XCTAssertEqual(AnswerChecker.checkSpoken(["Der Tisch, ein Tisch."], entry: tisch, area: .article), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Lampe eine Lampe"], entry: lampe, area: .article), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["der Tisch eine Tisch"], entry: tisch, area: .article), .wrong)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Tisch ein Tisch"], entry: tisch, area: .article), .wrong)
        XCTAssertEqual(AnswerChecker.checkSpoken(["der Tisch"], entry: tisch, area: .article), .wrong)
    }

    func testSpokenPlural() {
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Tische"], entry: tisch, area: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["Tische"], entry: tisch, area: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Bücher"], entry: buch, area: .plural), .correct)
        XCTAssertEqual(AnswerChecker.checkSpoken(["die Buchen"], entry: buch, area: .plural), .wrong)
    }
}
