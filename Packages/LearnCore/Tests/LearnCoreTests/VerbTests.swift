import XCTest
@testable import LearnCore

final class VerbTests: XCTestCase {
    let fahren = VerbEntry(infinitive: "fahren", english: "drive",
                           forms: ["fahre", "fährst", "fährt", "fahren", "fahrt", "fahren"], group: .stemChanging)
    let aufstehen = VerbEntry(infinitive: "aufstehen", english: "get up",
                              forms: ["stehe auf", "stehst auf", "steht auf", "stehen auf", "steht auf", "stehen auf"],
                              group: .separable)

    func testCheckForm() {
        XCTAssertEqual(VerbExercises.check("fährst", verb: fahren, person: .du), .correct)
        XCTAssertEqual(VerbExercises.check("du fährst", verb: fahren, person: .du), .correct)
        XCTAssertEqual(VerbExercises.check("faehrst", verb: fahren, person: .du), .correct)
        XCTAssertEqual(VerbExercises.check("fahrst", verb: fahren, person: .du), .almost)
        XCTAssertEqual(VerbExercises.check("fahre", verb: fahren, person: .du), .wrong)
        XCTAssertEqual(VerbExercises.check("er steht auf", verb: aufstehen, person: .erSieEs), .correct)
        XCTAssertEqual(VerbExercises.check("aufsteht", verb: aufstehen, person: .erSieEs), .wrong)
    }

    func testTableAndSpoken() {
        XCTAssertEqual(VerbExercises.checkTable(fahren.forms, verb: fahren), .correct)
        var answers = fahren.forms
        answers[1] = "fahrst"
        XCTAssertEqual(VerbExercises.checkTable(answers, verb: fahren), .almost)
        answers[2] = "fahre"
        XCTAssertEqual(VerbExercises.checkTable(answers, verb: fahren), .wrong)
        XCTAssertEqual(VerbExercises.checkSpoken(["Du fährst."], verb: fahren, person: .du), .correct)
    }

    func testSharedFormsCountForEveryPerson() {
        XCTAssertEqual(fahren.persons(with: "fahren"), [.wir, .sieSie])
        XCTAssertEqual(VerbExercises.checkPerson(.sieSie, form: "fahren", verb: fahren), .correct)
        XCTAssertEqual(VerbExercises.checkPerson(.ich, form: "fahren", verb: fahren), .wrong)
    }

    func testOptions() {
        var rng = SeededGenerator(state: 8)
        for person in Person.allCases {
            let options = VerbExercises.options(for: fahren, person: person, using: &rng)
            XCTAssertEqual(options.count, 4)
            XCTAssertEqual(Set(options.map { PhraseChecker.key($0) }).count, 4)
            XCTAssertTrue(options.contains(fahren.form(for: person)))
        }
        let separable = VerbExercises.options(for: aufstehen, person: .du, using: &rng)
        XCTAssertTrue(separable.allSatisfy { $0.hasSuffix(" auf") })
    }

    func testKindByLevel() {
        var rng = SeededGenerator(state: 1)
        var seen = Set<VerbExerciseKind>()
        for _ in 0..<40 {
            let first = VerbExercises.kind(level: 0, allowSpeaking: true, using: &rng)
            XCTAssertTrue([.translateChoice, .chooseForm].contains(first))
            let second = VerbExercises.kind(level: 1, allowSpeaking: true, using: &rng)
            XCTAssertTrue([.translateGerman, .translateEnglish, .typeForm, .whichPerson].contains(second))
            let later = VerbExercises.kind(level: 3, allowSpeaking: false, using: &rng)
            XCTAssertFalse(later.isSpeaking)
            seen.formUnion([first, second, later])
        }
        XCTAssertTrue(seen.contains(.translateChoice))
    }

    func testTranslationChecks() {
        let waschen = VerbEntry(infinitive: "sich waschen", english: "wash (oneself)", forms: aufstehen.forms, group: .reflexive)
        XCTAssertEqual(VerbExercises.checkTranslation("fahren", verb: fahren), .correct)
        XCTAssertEqual(VerbExercises.checkTranslation("Fahren", verb: fahren), .correct)
        XCTAssertEqual(VerbExercises.checkTranslation("fahen", verb: fahren), .almost)
        XCTAssertEqual(VerbExercises.checkTranslation("gehen", verb: fahren), .wrong)
        XCTAssertEqual(VerbExercises.checkTranslation("waschen", verb: waschen), .correct)
        XCTAssertEqual(VerbExercises.checkTranslation("sich waschen", verb: waschen), .correct)
        XCTAssertEqual(VerbExercises.checkSpokenInfinitive(["Fahren."], verb: fahren), .correct)

        let drive = VerbEntry(infinitive: "fahren", english: "drive / go", forms: fahren.forms)
        XCTAssertEqual(VerbExercises.checkEnglish("to drive", verb: drive), .correct)
        XCTAssertEqual(VerbExercises.checkEnglish("go", verb: drive), .correct)
        XCTAssertEqual(VerbExercises.checkEnglish("drve", verb: drive), .almost)
        XCTAssertEqual(VerbExercises.checkEnglish("walk", verb: drive), .wrong)
    }

    func testTranslationOptions() throws {
        var rng = SeededGenerator(state: 3)
        let pool = [
            fahren, aufstehen,
            VerbEntry(infinitive: "laufen", english: "run", forms: fahren.forms, group: .stemChanging),
            VerbEntry(infinitive: "machen", english: "do", forms: fahren.forms, group: .regular),
            VerbEntry(infinitive: "lesen", english: "read", forms: fahren.forms, group: .stemChanging),
        ]
        let options = try XCTUnwrap(VerbExercises.translationOptions(for: fahren, pool: pool, using: &rng))
        XCTAssertEqual(options.count, 4)
        XCTAssertEqual(Set(options).count, 4)
        XCTAssertTrue(options.contains("fahren"))
        // Same group comes first: both other stem-changing verbs are offered.
        XCTAssertTrue(options.contains("laufen") && options.contains("lesen"))
        XCTAssertNil(VerbExercises.translationOptions(for: fahren, pool: [fahren], using: &rng))
    }

    func testMasteryBySubset() {
        let streaks: [[VerbExerciseKind: Int]] = [[.translateChoice: 2, .translateGerman: 2]]
        XCTAssertEqual(VerbExercises.mastery(streaks, kinds: [.translateChoice, .translateGerman]), 1)
        XCTAssertEqual(VerbExercises.mastery(streaks, kinds: VerbExerciseKind.conjugationKinds), 0)
        XCTAssertEqual(VerbExercises.mastery(streaks), 2.0 / Double(VerbExerciseKind.allCases.count), accuracy: 0.0001)
        XCTAssertEqual(VerbExerciseKind.translationKinds.count, 4)
    }

    func testMastery() {
        let kinds = VerbExercises.kindMastery([[.chooseForm: 2], [.chooseForm: 1, .typeForm: 2]])
        XCTAssertEqual(kinds[.chooseForm], 0.75)
        XCTAssertEqual(kinds[.typeForm], 0.5)
        XCTAssertEqual(kinds.count, VerbExerciseKind.allCases.count)
    }

    func testParser() throws {
        let json = """
        {"verbs": [
          {"infinitive": "fahren", "english": "to drive", "forms": ["fahre","fährst","fährt","fahren","fahrt","fahren"],
           "group": "stemChanging", "note": "a → ä con du ed er", "emoji": "🚗"},
          {"infinitive": "sein", "english": "be", "forms": {"ich": "bin", "du": "bist", "er/sie/es": "ist", "wir": "sind", "ihr": "seid", "sie/Sie": "sind"},
           "group": "irregular", "note": null, "emoji": ""},
          {"infinitive": "Fahren", "english": "dup", "forms": ["a","b","c","d","e","f"]},
          {"infinitive": "gehen", "english": "go", "forms": ["gehe","gehst"]}
        ]}
        """
        let verbs = try VerbExtractionParser.parse(json)
        XCTAssertEqual(verbs.map(\.infinitive), ["fahren", "sein"])
        XCTAssertEqual(verbs[0].english, "drive")
        XCTAssertEqual(verbs[1].forms, ["bin", "bist", "ist", "sind", "seid", "sind"])
        XCTAssertEqual(verbs[1].emoji, "🏃")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(VerbExtractionPrompt.responseSchema))
    }

    func testBackup() throws {
        let base = Date(timeIntervalSince1970: 1_780_000_000)
        let stored = BackupVerb(entry: fahren, createdAt: base, updatedAt: base, srs: .new(now: base),
                                streak: 2, kindStreaks: [.typeForm: 1])
        let decoded = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: base, words: [], verbs: [stored])))
        XCTAssertEqual(decoded.verbs, [stored])
        XCTAssertEqual(decoded.verbs?.first?.streaksByKind[.typeForm], 1)

        let newer = BackupVerb(entry: VerbEntry(infinitive: "Fahren", english: "x", forms: fahren.forms),
                               createdAt: base, updatedAt: base.addingTimeInterval(5), srs: .new(now: base))
        XCTAssertEqual(BackupVerbMerger.merge(existing: [stored], incoming: [newer]).updates.map(\.id), [stored.id])
    }
}
