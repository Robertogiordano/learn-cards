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
        // Without a preterite, its games do not count.
        let applicable = VerbExerciseKind.allCases.count - VerbExerciseKind.conjugationKinds(.preterite).count
        XCTAssertEqual(VerbExercises.mastery(streaks), 2.0 / Double(applicable), accuracy: 0.0001)
        XCTAssertEqual(VerbExerciseKind.translationKinds.count, 4)
    }

    func testMastery() {
        let kinds = VerbExercises.kindMastery([[.chooseForm: 2], [.chooseForm: 1, .typeForm: 2]])
        XCTAssertEqual(kinds[.chooseForm], 0.75)
        XCTAssertEqual(kinds[.typeForm], 0.5)
        XCTAssertEqual(kinds.count, VerbExerciseKind.allCases.count - VerbExerciseKind.conjugationKinds(.preterite).count)
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

    func testInfinitiveList() throws {
        let wrapped = #"{"infinitives": ["fahren", " Fahren ", "", "sich waschen", "aufstehen"]}"#
        XCTAssertEqual(try VerbListPrompt.parse(wrapped), ["fahren", "sich waschen", "aufstehen"])
        XCTAssertEqual(try VerbListPrompt.parse(#"Here: ["gehen", "gehen"]"#), ["gehen"])
        XCTAssertThrowsError(try VerbListPrompt.parse("nessun verbo"))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(VerbListPrompt.responseSchema))
    }

    func testMissingInfinitives() {
        let existing: Set<String> = [fahren.dedupeKey, PhraseChecker.key("sich waschen")]
        let missing = VerbExtractionPlan.missing(["Fahren", "Sich waschen", "aufstehen", "gehen"], existingKeys: existing)
        XCTAssertEqual(missing, ["aufstehen", "gehen"])
        XCTAssertTrue(VerbExtractionPlan.missing(["fahren"], existingKeys: existing).isEmpty)
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

    func testSeparablePrefix() throws {
        let json = """
        {"verbs": [
          {"infinitive": "anfangen", "english": "begin", "forms": ["fange an","fängst an","fängt an","fangen an","fangt an","fangen an"],
           "group": "stemChanging", "separablePrefix": " An ", "note": null, "emoji": "🏁"},
          {"infinitive": "aufstehen", "english": "get up", "forms": ["stehe auf","stehst auf","steht auf","stehen auf","steht auf","stehen auf"],
           "group": "separable", "note": null, "emoji": "⏰"},
          {"infinitive": "verstehen", "english": "understand", "forms": ["verstehe","verstehst","versteht","verstehen","versteht","verstehen"],
           "group": "regular", "separablePrefix": null, "note": null, "emoji": "💡"}
        ]}
        """
        let verbs = try VerbExtractionParser.parse(json)
        XCTAssertEqual(verbs[0].separablePrefix, "an")
        XCTAssertEqual(verbs[0].group, .stemChanging)
        XCTAssertEqual(verbs[0].section, .separable)
        // An older answer with the separable group: flag kept, prefix read off the table.
        XCTAssertEqual(verbs[1].separablePrefix, "auf")
        XCTAssertEqual(verbs[1].group, .regular)
        XCTAssertNil(verbs[2].separablePrefix)
        XCTAssertEqual(verbs[2].section, .regular)
        XCTAssertFalse(VerbGroup.baseGroups.contains(.separable))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(VerbExtractionPrompt.responseSchema))
    }

    func testInferPrefix() {
        XCTAssertEqual(SeparableVerbs.inferPrefix(infinitive: "aufstehen", forms: aufstehen.forms), "auf")
        XCTAssertEqual(SeparableVerbs.inferPrefix(infinitive: "sich anziehen", forms: ["ziehe mich an"]), "an")
        XCTAssertNil(SeparableVerbs.inferPrefix(infinitive: "sich waschen", forms: ["wasche mich"]))
        XCTAssertNil(SeparableVerbs.inferPrefix(infinitive: "fahren", forms: fahren.forms))
    }

    func testBackupKeepsPrefix() throws {
        let verb = VerbEntry(infinitive: "anrufen", english: "call", forms: aufstehen.forms, separablePrefix: "an")
        let backup = BackupVerb(entry: verb, createdAt: .now, updatedAt: .now, srs: .new(now: .now))
        let decoded = try JSONDecoder().decode(BackupVerb.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(decoded.entry.separablePrefix, "an")
    }

    // MARK: - Preterite

    var fahrenWithPast: VerbEntry {
        var verb = fahren
        verb.preterite = ["fuhr", "fuhrst", "fuhr", "fuhren", "fuhrt", "fuhren"]
        return verb
    }

    func testPreteriteKinds() {
        XCTAssertEqual(VerbExerciseKind.conjugationKinds(.preterite).count, 5)
        XCTAssertEqual(VerbExerciseKind.conjugationKinds(.present).count, 5)
        XCTAssertEqual(VerbExerciseKind.typeFormPreterite.base, .typeForm)
        XCTAssertEqual(VerbExerciseKind.typeFormPreterite.tense, .preterite)
        XCTAssertEqual(VerbExerciseKind.typeForm.inTense(.preterite), .typeFormPreterite)
        XCTAssertEqual(VerbExerciseKind.speakPreterite.inTense(.present), .speak)
        XCTAssertEqual(VerbExerciseKind.translateGerman.inTense(.preterite), .translateGerman)
        XCTAssertTrue(VerbExerciseKind.speakPreterite.isSpeaking)
        XCTAssertTrue(VerbExerciseKind.chooseFormPreterite.isRecognition)
        XCTAssertNil(VerbExerciseKind.translateChoice.tense)
    }

    func testPreteriteSupport() {
        XCTAssertFalse(fahren.hasPreterite)
        XCTAssertFalse(fahren.supports(.typeFormPreterite))
        XCTAssertTrue(fahren.supports(.typeForm))
        XCTAssertTrue(fahrenWithPast.supports(.fullTablePreterite))
    }

    func testCheckPreterite() {
        let verb = fahrenWithPast
        XCTAssertEqual(VerbExercises.check("fuhrst", verb: verb, person: .du, tense: .preterite), .correct)
        XCTAssertEqual(VerbExercises.check("du fuhrst", verb: verb, person: .du, tense: .preterite), .correct)
        XCTAssertEqual(VerbExercises.check("fährst", verb: verb, person: .du, tense: .preterite), .wrong)
        XCTAssertEqual(VerbExercises.checkTable(verb.preterite, verb: verb, tense: .preterite), .correct)
        // "fuhr" is both ich and er/sie/es.
        XCTAssertEqual(verb.persons(with: "fuhr", tense: .preterite), [.ich, .erSieEs])
        XCTAssertEqual(VerbExercises.checkPerson(.ich, form: "fuhr", verb: verb, tense: .preterite), .correct)
    }

    func testPreteriteOptions() {
        var rng = SystemRandomNumberGenerator()
        let verb = fahrenWithPast
        for person in Person.allCases {
            let options = VerbExercises.options(for: verb, person: person, tense: .preterite, using: &rng)
            XCTAssertEqual(options.count, 4)
            XCTAssertEqual(Set(options.map { PhraseChecker.key($0) }).count, 4)
            XCTAssertTrue(options.contains(verb.form(for: person, tense: .preterite)))
        }
    }

    func testPreteriteMasteryOnlyCountsVerbsWithIt() {
        let progress = [
            VerbProgress(streaks: [.typeFormPreterite: 2], hasPreterite: true),
            VerbProgress(streaks: [:], hasPreterite: false),
        ]
        let kinds = VerbExercises.kindMastery(progress)
        XCTAssertEqual(kinds[.typeFormPreterite], 1)
        XCTAssertEqual(kinds[.typeForm], 0)
        XCTAssertNil(VerbExercises.kindMastery([VerbProgress(streaks: [:], hasPreterite: false)])[.typeFormPreterite])
    }

    func testAdaptiveKindUsesPreteriteOnlyWhenKnown() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let kind = VerbExercises.kind(level: 3, allowSpeaking: true, hasPreterite: false, using: &rng)
            XCTAssertNotEqual(kind.tense, .preterite)
        }
        let kinds = (0..<300).map { _ in
            VerbExercises.kind(level: 3, allowSpeaking: true, hasPreterite: true, using: &rng)
        }
        XCTAssertTrue(kinds.contains { $0.tense == .preterite })
    }

    func testParserReadsPreterite() throws {
        let json = """
        {"verbs": [{"infinitive": "fahren", "english": "to drive",
          "forms": ["fahre", "fährst", "fährt", "fahren", "fahrt", "fahren"],
          "preterite": ["fuhr", "fuhrst", "fuhr", "fuhren", "fuhrt", "fuhren"],
          "group": "stemChanging", "separablePrefix": null, "note": null, "emoji": "🚗"},
         {"infinitive": "gehen", "english": "go",
          "forms": ["gehe", "gehst", "geht", "gehen", "geht", "gehen"],
          "preterite": ["ging", "gingst"], "group": "irregular", "separablePrefix": null, "note": null, "emoji": "🚶"}]}
        """
        let verbs = try VerbExtractionParser.parse(json)
        XCTAssertEqual(verbs.count, 2)
        XCTAssertEqual(verbs[0].preterite.first, "fuhr")
        // A partial table is dropped rather than half used.
        XCTAssertEqual(verbs[1].preterite, [])
    }

    func testPreteritePromptParser() throws {
        let json = """
        {"verbs": [{"infinitive": "Sein", "preterite": ["war", "warst", "war", "waren", "wart", "waren"]},
                   {"infinitive": "haben", "preterite": ["hatte"]}]}
        """
        let tables = try VerbPreteritePrompt.parse(json)
        XCTAssertEqual(tables[PhraseChecker.key("sein")]?.first, "war")
        XCTAssertNil(tables[PhraseChecker.key("haben")])
    }

    func testBackupKeepsPreteriteAndReadsOldBackups() throws {
        let backup = BackupVerb(entry: fahrenWithPast, createdAt: .now, updatedAt: .now, srs: .new(now: .now))
        let decoded = try JSONDecoder().decode(BackupVerb.self, from: JSONEncoder().encode(backup))
        XCTAssertEqual(decoded.entry.preterite, fahrenWithPast.preterite)

        let old = BackupVerb(entry: fahren, createdAt: .now, updatedAt: .now, srs: .new(now: .now))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object.removeValue(forKey: "preterite")
        let oldDecoded = try JSONDecoder().decode(BackupVerb.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(oldDecoded.entry.preterite, [])
    }
}
