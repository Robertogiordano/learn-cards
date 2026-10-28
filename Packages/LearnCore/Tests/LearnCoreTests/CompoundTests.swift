import XCTest
@testable import LearnCore

final class CompoundTests: XCTestCase {
    func compound(_ german: String, _ article: Article, _ parts: [String], _ english: String) -> VocabEntry {
        VocabEntry(german: german, article: article, english: [english], partOfSpeech: .noun,
                   category: VocabEntry.compoundCategory, parts: parts)
    }

    lazy var kuechentuer = compound("Küchentür", .die, ["Küche", "Tür"], "kitchen door")
    lazy var schreibtisch = compound("Schreibtisch", .der, ["schreiben", "Tisch"], "desk")
    lazy var haustuer = compound("Haustür", .die, ["Haus", "Tür"], "front door")
    lazy var kuehlschrank = compound("Kühlschrank", .der, ["kühlen", "Schrank"], "fridge")
    lazy var arbeitszimmer = compound("Arbeitszimmer", .das, ["Arbeit", "Zimmer"], "study")
    lazy var all = [kuechentuer, schreibtisch, haustuer, kuehlschrank, arbeitszimmer]

    func testMatchRoundAvoidsAmbiguousTiles() throws {
        var rng = SeededGenerator(state: 1)
        let round = try XCTUnwrap(CompoundGame.matchRound(all, using: &rng))
        // Haustür shares "Tür" with Küchentür, so it is left out.
        XCTAssertEqual(round.compounds.map(\.german), ["Küchentür", "Schreibtisch", "Kühlschrank", "Arbeitszimmer"])
        XCTAssertEqual(Set(round.left), ["Küche", "schreiben", "kühlen", "Arbeit"])
        XCTAssertEqual(round.compound(left: "küche", right: "Tür")?.german, "Küchentür")
        XCTAssertNil(round.compound(left: "Küche", right: "Tisch"))
        XCTAssertEqual(round.compound(left: "Arbeit")?.german, "Arbeitszimmer")
        XCTAssertNil(CompoundGame.matchRound([kuechentuer, haustuer, schreibtisch], using: &rng))
    }

    func testCompleteOptions() {
        var rng = SeededGenerator(state: 4)
        for _ in 0..<20 {
            let question = CompoundGame.complete(kuechentuer, compounds: all, words: ["Stuhl", "Lampe"], using: &rng)
            XCTAssertEqual(question.options.count, 4)
            XCTAssertEqual(Set(question.options.map(PhraseChecker.key)).count, 4)
            XCTAssertTrue(question.options.contains(question.answer))
            // "Haus" + "Tür" is another known compound, so it is never a wrong option for "___ + Tür".
            if question.missingIndex == 0 {
                XCTAssertFalse(question.options.contains("Haus"))
            }
        }
    }

    func testBuildTilesAndCheck() {
        var rng = SeededGenerator(state: 9)
        let question = CompoundGame.build(schreibtisch, compounds: all, words: ["Stuhl"], using: &rng)
        XCTAssertEqual(question.tiles.count, 6)
        XCTAssertTrue(Set(question.tiles).isSuperset(of: ["schreiben", "Tisch"]))
        XCTAssertEqual(CompoundGame.checkBuild(["schreiben", "Tisch"], entry: schreibtisch), .correct)
        XCTAssertEqual(CompoundGame.checkBuild(["Tisch", "schreiben"], entry: schreibtisch), .wrong)
    }

    func testTyped() {
        XCTAssertEqual(CompoundGame.checkTyped("die Küchentür", entry: kuechentuer), .correct)
        XCTAssertEqual(CompoundGame.checkTyped("die Kuechentuer", entry: kuechentuer), .correct)
        XCTAssertEqual(CompoundGame.checkTyped("Küchentür", entry: kuechentuer), .almost)
        XCTAssertEqual(CompoundGame.checkTyped("der Küchentür", entry: kuechentuer), .wrong)
        XCTAssertEqual(CompoundGame.checkTyped("die Küchentur", entry: kuechentuer), .almost)
    }

    func testMastery() {
        let kinds = CompoundGame.kindMastery([[.matchPairs: 2], [.matchPairs: 1, .typeCompound: 2]])
        XCTAssertEqual(kinds[.matchPairs], 0.75)
        XCTAssertEqual(kinds[.typeCompound], 0.5)
        XCTAssertEqual(kinds[.completeWord], 0)
    }

    func testParserKeepsParts() throws {
        let json = """
        {"words": [
          {"german": "Küchentür", "article": "die", "plural": "Küchentüren", "english": ["kitchen door"],
           "partOfSpeech": "noun", "emoji": "🚪", "category": "Home", "parts": ["Küche", " Tür "]},
          {"german": "Küche", "article": "die", "plural": "Küchen", "english": ["kitchen"],
           "partOfSpeech": "noun", "emoji": "🍳", "category": "Home", "parts": []},
          {"german": "schnell", "article": null, "plural": null, "english": ["fast"],
           "partOfSpeech": "adjective", "emoji": "⚡", "category": "Misc"}
        ]}
        """
        let entries = try ExtractionParser.parse(json)
        XCTAssertEqual(entries[0].parts, ["Küche", "Tür"])
        XCTAssertEqual(entries[0].category, VocabEntry.compoundCategory)
        XCTAssertTrue(entries[0].isCompound)
        XCTAssertEqual(entries[1].parts, [])
        XCTAssertEqual(entries[1].category, "Home")
        XCTAssertEqual(entries[2].parts, [])
    }

    func testBackupKeepsParts() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let word = BackupWord(entry: kuechentuer, createdAt: now, updatedAt: now, srs: .new(now: now),
                              compoundStreaks: ["matchPairs": 2])
        let decoded = try XCTUnwrap(BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: now, words: [word]))).words.first)
        XCTAssertEqual(decoded.parts, ["Küche", "Tür"])
        XCTAssertEqual(decoded.entry.parts, ["Küche", "Tür"])
        XCTAssertEqual(decoded.compoundStreaks, ["matchPairs": 2])
    }
}

final class CompoundSplitterTests: XCTestCase {
    let vocabulary = ["Küche", "Tür", "Arbeit", "Zimmer", "schreiben", "Tisch", "Kind", "Haus", "Haustür",
                      "Schlüssel", "Schule", "Tasche", "Küchentür"]

    func testSplitsWithLinkingLetters() {
        XCTAssertEqual(CompoundSplitter.suggest("Küchentür", vocabulary: vocabulary), ["Küche", "Tür"])
        XCTAssertEqual(CompoundSplitter.suggest("Arbeitszimmer", vocabulary: vocabulary), ["Arbeit", "Zimmer"])
        XCTAssertEqual(CompoundSplitter.suggest("Schreibtisch", vocabulary: vocabulary), ["schreiben", "Tisch"])
        XCTAssertEqual(CompoundSplitter.suggest("Kinderzimmer", vocabulary: vocabulary), ["Kind", "Zimmer"])
        XCTAssertEqual(CompoundSplitter.suggest("Schultasche", vocabulary: vocabulary), ["Schule", "Tasche"])
    }

    func testPrefersFewerAndLongerParts() {
        XCTAssertEqual(CompoundSplitter.suggest("Haustürschlüssel", vocabulary: vocabulary), ["Haustür", "Schlüssel"])
        XCTAssertEqual(CompoundSplitter.suggest("Kinderzimmertür", vocabulary: vocabulary), ["Kind", "Zimmer", "Tür"])
    }

    func testNoSplit() {
        XCTAssertNil(CompoundSplitter.suggest("Fahrrad", vocabulary: vocabulary))
        XCTAssertNil(CompoundSplitter.suggest("Tür", vocabulary: vocabulary))
    }
}

final class CompoundSplitPromptTests: XCTestCase {
    func testParse() throws {
        XCTAssertEqual(try CompoundSplitPrompt.parse(#"{"parts": ["Küche", " Tür "]}"#), ["Küche", "Tür"])
        XCTAssertEqual(try CompoundSplitPrompt.parse(#"{"parts": ["Tisch"]}"#), [])
        XCTAssertEqual(try CompoundSplitPrompt.parse(#"Sure: ["Kind", "Zimmer"]"#), ["Kind", "Zimmer"])
        XCTAssertThrowsError(try CompoundSplitPrompt.parse("no idea"))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CompoundSplitPrompt.responseSchema))
    }
}
