import XCTest
@testable import LearnCore

final class PhraseTests: XCTestCase {
    let question = PhraseEntry(
        german: "Sprichst du Französisch?",
        variants: ["Sprechen Sie Französisch?"],
        english: "Do you speak French?",
        response: "Nein, ich spreche nur Englisch und Deutsch.",
        kind: .question,
        category: "Domande personali"
    )
    let idiom = PhraseEntry(german: "Ich verstehe nur Bahnhof.", english: "It's all Greek to me.",
                            note: "Literally: I only understand train station.", kind: .idiom)

    func testCheckAcceptsVariantsAndIgnoresCaseAndPunctuation() {
        XCTAssertEqual(PhraseChecker.check("sprichst du französisch", accepted: question.accepted), .correct)
        XCTAssertEqual(PhraseChecker.check("Sprechen Sie Franzoesisch?", accepted: question.accepted), .correct)
        XCTAssertEqual(PhraseChecker.check("Sprichst du Franzözisch?", accepted: question.accepted), .almost)
        XCTAssertEqual(PhraseChecker.check("Sprichst du Englisch?", accepted: question.accepted), .wrong)
        XCTAssertEqual(PhraseChecker.check("Du sprichst Französisch?", accepted: question.accepted), .wrong)
        XCTAssertEqual(PhraseChecker.check("", accepted: question.accepted), .wrong)
    }

    func testTwoTyposAreWrong() {
        XCTAssertEqual(PhraseChecker.check("Ich verstehe nur Banhof", accepted: idiom.accepted), .almost)
        XCTAssertEqual(PhraseChecker.check("Ich verstee nur Banhof", accepted: idiom.accepted), .wrong)
    }

    func testSpokenTakesTheBestCandidate() {
        XCTAssertEqual(PhraseChecker.checkSpoken(["Ich verstehe nur Banhof", "ich verstehe nur Bahnhof"], accepted: idiom.accepted), .correct)
    }

    func testMissingWords() {
        XCTAssertEqual(PhraseChecker.missingWords(in: "Sprichst du Englisch", expected: question.german), [2])
    }

    func testTiles() {
        XCTAssertEqual(PhraseExercises.tiles(for: question.german), ["Sprichst", "du", "Französisch"])
        var rng = SeededGenerator(state: 4)
        let shuffled = PhraseExercises.shuffledTiles(for: idiom.german, using: &rng)
        XCTAssertEqual(shuffled.sorted(), PhraseExercises.tiles(for: idiom.german).sorted())
        XCTAssertNotEqual(shuffled, PhraseExercises.tiles(for: idiom.german))

        XCTAssertEqual(PhraseExercises.checkReorder(["Sprichst", "du", "Französisch"], entry: question), .correct)
        XCTAssertEqual(PhraseExercises.checkReorder(["du", "Sprichst", "Französisch"], entry: question), .wrong)
    }

    func testClozeHidesALongWordAfterTheFirst() throws {
        XCTAssertEqual(PhraseExercises.clozeIndex(in: question.german), 2)
        let cloze = try XCTUnwrap(PhraseExercises.cloze(for: question.german))
        XCTAssertEqual(cloze.shown, "Sprichst du _____?")
        XCTAssertEqual(cloze.answer, "Französisch")
        XCTAssertNil(PhraseExercises.clozeIndex(in: "Ja."))
    }

    func testApplicability() {
        XCTAssertTrue(PhraseExerciseKind.questionFromAnswer.isApplicable(to: question))
        XCTAssertFalse(PhraseExerciseKind.questionFromAnswer.isApplicable(to: idiom))
    }

    func testAutomaticKindByLevel() {
        var rng = SeededGenerator(state: 2)
        XCTAssertEqual(PhraseExercises.kind(level: 0, entry: idiom, allowSpeaking: true, using: &rng), .reorder)
        for _ in 0..<20 {
            let second = PhraseExercises.kind(level: 1, entry: idiom, allowSpeaking: true, using: &rng)
            XCTAssertTrue([.cloze, .dictation].contains(second))
            let later = PhraseExercises.kind(level: 3, entry: idiom, allowSpeaking: false, using: &rng)
            XCTAssertTrue([.translate, .dictation].contains(later))
        }
    }

    func testMastery() {
        let phrases: [(entry: PhraseEntry, streaks: [PhraseExerciseKind: Int])] = [
            (question, [.reorder: 2, .translate: 1]),
            (idiom, [.reorder: 2]),
        ]
        let kinds = PhraseExercises.kindMastery(phrases)
        XCTAssertEqual(kinds[.reorder], 1)
        XCTAssertEqual(kinds[.translate], 0.25)
        XCTAssertEqual(kinds[.questionFromAnswer], 0)
        XCTAssertEqual(kinds.count, PhraseExerciseKind.allCases.count)
    }

    func testParserSolvesPairsAndCleansUp() throws {
        let json = """
        ```json
        {"phrases": [
          {"german": "Sprichst du Französisch?", "variants": ["Sprechen Sie Französisch?", "sprichst du französisch"],
           "english": "Do you speak French?", "response": "Nein, ich spreche nur Englisch und Deutsch.",
           "note": null, "kind": "question", "category": "domande personali", "emoji": "🇫🇷"},
          {"german": "Ich verstehe nur Bahnhof.", "variants": [], "english": "It's all Greek to me.",
           "response": "", "note": "Literally: I only understand train station.", "kind": "IDIOM", "category": "", "emoji": ""},
          {"german": "sprichst du Französisch", "english": "duplicate"},
          {"german": "", "english": "empty"}
        ]}
        ```
        """
        let phrases = try PhraseExtractionParser.parse(json, existingCategories: ["Domande personali"])
        XCTAssertEqual(phrases.count, 2)
        XCTAssertEqual(phrases[0].variants, ["Sprechen Sie Französisch?"])
        XCTAssertEqual(phrases[0].category, "Domande personali")
        XCTAssertEqual(phrases[0].response, "Nein, ich spreche nur Englisch und Deutsch.")
        XCTAssertEqual(phrases[1].kind, .idiom)
        XCTAssertNil(phrases[1].response)
        XCTAssertEqual(phrases[1].category, PhraseEntry.defaultCategory)
        XCTAssertEqual(phrases[1].emoji, "💬")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(PhraseExtractionPrompt.responseSchema))
    }

    func testBackupRoundTripAndMerge() throws {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let stored = BackupPhrase(entry: question, createdAt: base, updatedAt: base, srs: .new(now: base),
                                  streak: 1, kindStreaks: [.reorder: 2])
        let decoded = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: base, words: [], phrases: [stored])))
        XCTAssertEqual(decoded.phrases, [stored])
        XCTAssertEqual(decoded.phrases?.first?.streaksByKind[.reorder], 2)

        var newer = BackupPhrase(entry: PhraseEntry(german: "sprichst du franzoesisch", english: "x"),
                                 createdAt: base, updatedAt: base.addingTimeInterval(60), srs: .new(now: base))
        newer.kindStreaks = [:]
        let merge = BackupPhraseMerger.merge(existing: [stored], incoming: [newer, BackupPhrase(entry: idiom, createdAt: base, updatedAt: base, srs: .new(now: base))])
        XCTAssertEqual(merge.updates.map(\.id), [stored.id])
        XCTAssertEqual(merge.inserts.map(\.german), [idiom.german])

        let old = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: base, words: [])))
        XCTAssertNil(old.phrases)
    }
}
