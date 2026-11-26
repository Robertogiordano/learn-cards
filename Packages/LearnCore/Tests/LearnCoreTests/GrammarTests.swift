import XCTest
@testable import LearnCore

final class GrammarTests: XCTestCase {
    private let lessonJSON = """
    {"title": "Accusative case", "emoji": "🎯", "level": "A1", "summary": "Use it for the thing you act on.",
     "cards": [
       {"title": "When", "body": "The **direct object**.", "examples": [{"german": "Ich sehe **den** Hund.", "english": "I see the dog."}],
        "table": {"headers": [], "rows": []}, "tip": ""},
       {"title": "Forms", "body": "Only der changes: **den**.", "examples": [],
        "table": {"headers": ["", "m", "f"], "rows": [["Nom", "der", "die"], ["Akk", "den"]]}, "tip": "Only masculine changes!"},
       {"title": "Empty", "body": "  ", "examples": [], "table": {"headers": [], "rows": []}, "tip": ""},
       {"title": "Mistakes", "body": "Don't forget den.", "examples": [], "table": {"headers": [], "rows": []}, "tip": ""}
     ],
     "games": [
       {"kind": "sort", "prompt": "Nominative or accusative?", "english": "", "options": [], "answers": [],
        "pairs": [{"left": "der Hund", "right": "Nom"}, {"left": "den Hund", "right": "Akk"}, {"left": "einen Ball", "right": "Akk"}],
        "explanation": "", "uses": []},
       {"kind": "choice", "prompt": "Ich habe ___ Bruder.", "english": "", "options": ["ein", "einen"], "answers": ["einen"],
        "pairs": [], "explanation": "Bruder is masculine.", "uses": []},
       {"kind": "choice", "prompt": "Broken", "english": "", "options": ["a", "b"], "answers": ["c"],
        "pairs": [], "explanation": "", "uses": []},
       {"kind": "dance", "prompt": "Unknown kind", "english": "", "options": [], "answers": [], "pairs": [], "explanation": "", "uses": []}
     ]}
    """

    func testParseLessonKeepsValidCardsAndGames() throws {
        let lesson = try GrammarParser.parseLesson(lessonJSON, topic: GrammarTopic(title: "Akk"))
        XCTAssertEqual(lesson.title, "Accusative case")
        XCTAssertEqual(lesson.cards.count, 3, "the card with an empty body is dropped")
        XCTAssertEqual(lesson.cards[1].table.rows[1], ["Akk", "den", ""], "short rows are padded")
        XCTAssertEqual(lesson.games.map(\.kind), [.sort, .choice], "broken and unknown games are dropped")
    }

    func testLessonStepsInterleaveGames() throws {
        let lesson = try GrammarParser.parseLesson(lessonJSON, topic: GrammarTopic(title: "Akk"))
        let kinds = lesson.steps.map { step -> String in
            if case .card = step { return "card" } else { return "game" }
        }
        XCTAssertEqual(kinds, ["card", "card", "game", "card", "game"])
    }

    func testParseExercisesDropsUnplayable() throws {
        let json = """
        {"exercises": [
          {"kind": "gap", "prompt": "Ich kaufe ___ Tisch.", "english": "I buy a table.", "options": [], "answers": ["einen"], "pairs": [], "explanation": "", "uses": ["der Tisch"]},
          {"kind": "gap", "prompt": "No gap here", "english": "", "options": [], "answers": ["x"], "pairs": [], "explanation": "", "uses": []},
          {"kind": "order", "prompt": "Build", "english": "", "options": [], "answers": ["Morgen gehe ich ins Kino.", "Ich gehe morgen ins Kino."], "pairs": [], "explanation": "", "uses": []},
          {"kind": "match", "prompt": "Match", "english": "", "options": [], "answers": [], "pairs": [{"left": "ich", "right": "mich"}, {"left": "du", "right": "mich"}], "explanation": "", "uses": []}
        ]}
        """
        let tasks = try GrammarParser.parseExercises(json)
        XCTAssertEqual(tasks.map(\.kind), [.gap, .order], "a gap without ___ and a match with a repeated right side are dropped")
        XCTAssertEqual(tasks[1].tiles, ["Morgen", "gehe", "ich", "ins", "Kino."])
    }

    func testNoExercisesThrows() {
        XCTAssertThrowsError(try GrammarParser.parseExercises(#"{"exercises": []}"#))
    }

    func testCheckerHasNoTypoToleranceButFoldsSpelling() {
        let gap = GrammarTask(kind: .gap, prompt: "Ich gebe ___ Mann das Buch.", answers: ["dem"])
        XCTAssertTrue(GrammarChecker.check("Dem", task: gap))
        XCTAssertFalse(GrammarChecker.check("den", task: gap), "one letter is the whole point")
        XCTAssertTrue(GrammarChecker.check("Ich gebe dem Mann das Buch", task: gap), "the full sentence counts too")

        let transform = GrammarTask(kind: .transform, prompt: "Perfekt: Ich gehe.", answers: ["Ich bin gegangen."])
        XCTAssertTrue(GrammarChecker.check("ich bin gegangen", task: transform))

        let umlaut = GrammarTask(kind: .gap, prompt: "Das ist ___ dich.", answers: ["für"])
        XCTAssertTrue(GrammarChecker.check("fuer", task: umlaut))
        XCTAssertFalse(GrammarChecker.check("", task: umlaut))
    }

    func testOrderAcceptsAlternativeWordOrders() {
        let task = GrammarTask(kind: .order, prompt: "Build", answers: ["Morgen gehe ich ins Kino.", "Ich gehe morgen ins Kino."])
        XCTAssertTrue(GrammarChecker.check(tiles: ["Ich", "gehe", "morgen", "ins", "Kino."], task: task))
        XCTAssertFalse(GrammarChecker.check(tiles: ["Ich", "morgen", "gehe", "ins", "Kino."], task: task))
    }

    func testChoiceCorrectIndexAndSortBuckets() {
        let choice = GrammarTask(kind: .choice, prompt: "___", options: ["den", "dem"], answers: ["dem"])
        XCTAssertEqual(choice.correctIndex, 1)
        let sort = GrammarTask(kind: .sort, prompt: "Sort", pairs: [
            GrammarPair(left: "a", right: "Akk"), GrammarPair(left: "b", right: "Dat"), GrammarPair(left: "c", right: "Akk"),
        ])
        XCTAssertEqual(sort.buckets, ["Akk", "Dat"])
        XCTAssertTrue(sort.isPlayable)
    }

    func testPillProgressKeepsRecentScoresAndMistakes() {
        var pill = GrammarPill(topic: GrammarTopic(title: "Dativ"),
                               lesson: GrammarLesson(title: "Dativ", emoji: "🎁", level: "A2", summary: "", cards: [], games: []))
        XCTAssertNil(pill.mastery)
        for score in [0.2, 0.4, 0.9, 0.8, 0.9, 1.0] {
            pill.record(score: score, mistakes: [GrammarMistake(prompt: "p", given: "g", expected: "e")])
        }
        XCTAssertEqual(pill.scores.count, GrammarPill.keptScores)
        XCTAssertEqual(pill.mastery!, 0.9, accuracy: 0.001)
        XCTAssertTrue(pill.hasStar)
        XCTAssertEqual(pill.mistakes.count, 6)
    }

    func testVocabularySamplePrefersKnownItemsAndRespectsLimits() {
        let known = (0..<60).map { GrammarVocabItem(kind: .noun, line: "known \($0)", known: true) }
        let fresh = (0..<10).map { GrammarVocabItem(kind: .noun, line: "new \($0)", known: false) }
        var rng = SystemRandomNumberGenerator()
        let sample = GrammarVocabulary.sample(fresh + known, using: &rng)
        XCTAssertEqual(sample.count, GrammarVocabulary.limits[.noun])
        XCTAssertTrue(sample.allSatisfy(\.known))
    }

    func testVocabularyLinesAndPrompt() {
        let noun = GrammarVocabItem.noun(german: "Tisch", article: .der, plural: "Tische", english: ["table"], known: true)
        XCTAssertEqual(noun.line, "der Tisch (pl. Tische) = table")
        let verb = GrammarVocabItem.verb(VerbEntry(infinitive: "fahren", english: "to drive",
                                                   forms: ["fahre", "fährst", "fährt", "fahren", "fahrt", "fahren"],
                                                   group: .stemChanging), known: false)
        XCTAssertTrue(verb.line.hasPrefix("fahren: fahre, fährst"))

        var pill = GrammarPill(topic: GrammarTopic(title: "Dativ"),
                               lesson: GrammarLesson(title: "Dativ", emoji: "🎁", level: "A2", summary: "",
                                                     cards: [GrammarCard(title: "Idea", body: "dem")], games: []))
        pill.mistakes = [GrammarMistake(prompt: "Ich helfe ___ Mann.", given: "den", expected: "dem")]
        let text = GrammarPrompt.exercisesInstruction(pill: pill, vocabulary: [noun, verb])
        XCTAssertTrue(text.contains("der Tisch (pl. Tische)"))
        XCTAssertTrue(text.contains("Recent mistakes"))
    }

    func testBackupRoundTripsPills() throws {
        let pill = GrammarPill(topic: GrammarTopic(title: "Dativ"),
                               lesson: GrammarLesson(title: "Dativ", emoji: "🎁", level: "A2", summary: "s",
                                                     cards: [GrammarCard(title: "Idea", body: "dem")], games: []))
        let data = try BackupCodec.encode(Backup(exportedAt: Date(), words: [], grammarPills: [pill]))
        XCTAssertEqual(try BackupCodec.decode(data).grammarPills?.first?.lesson.title, "Dativ")
    }

    func testA1CourseFollowsTheBook() {
        let course = GrammarCourse.a1
        XCTAssertEqual(course.chapters.map(\.number), Array(1...9))
        XCTAssertEqual(course.topics.count, 31)
        XCTAssertEqual(Set(course.topics.map(\.title)).count, 31, "titles identify the pills")
        XCTAssertTrue(course.topics.allSatisfy { $0.level == "A1" && $0.chapter != nil })
        XCTAssertEqual(course.chapter(9)?.topics.last?.title, "Verbs for positions and directions (Verben für Positionen und Richtungen)")
        let text = GrammarPrompt.lessonInstruction(for: course.topics[0])
        XCTAssertTrue(text.contains("chapter 1"))
    }

    func testOldTopicsWithoutChapterStillDecode() throws {
        let json = #"{"title": "Dativ", "detail": "", "level": "A2", "emoji": "🎁"}"#
        let topic = try JSONDecoder().decode(GrammarTopic.self, from: Data(json.utf8))
        XCTAssertNil(topic.chapter)
    }

    func testEveryA1TopicHasAPlayableBuiltInLesson() {
        let library = GrammarLibrary.load()
        for topic in GrammarCourse.a1.topics {
            guard let lesson = library[topic.title] else {
                XCTFail("No built-in lesson for \(topic.title)")
                continue
            }
            XCTAssertGreaterThanOrEqual(lesson.cards.count, 4, topic.title)
            XCTAssertEqual(lesson.games.count, 3, "every game must be playable: \(topic.title)")
            XCTAssertTrue(lesson.cards.allSatisfy { !$0.title.isEmpty && $0.body.split(separator: " ").count <= 80 }, topic.title)
            XCTAssertEqual(lesson.level, "A1")
        }
        XCTAssertEqual(library.count, GrammarCourse.a1.topics.count)
    }

    func testEveryBundledFileParses() throws {
        let urls = (Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("grammar-a1-") }
        XCTAssertEqual(urls.count, 9)
        for url in urls {
            XCTAssertNoThrow(try GrammarParser.parseBundledLessons(Data(contentsOf: url), course: .a1), url.lastPathComponent)
        }
    }

    func testChatWindowKeepsTheLatestTurnsStartingWithAQuestion() {
        var messages: [GrammarChatMessage] = []
        for index in 0..<20 {
            messages.append(GrammarChatMessage(role: .user, text: "q\(index)"))
            messages.append(GrammarChatMessage(role: .assistant, text: "a\(index)"))
        }
        let recent = GrammarChatPrompt.recent(messages)
        XCTAssertEqual(recent.count, GrammarChatPrompt.window)
        XCTAssertEqual(recent.first?.text, "q14")
        XCTAssertEqual(recent.last?.text, "a19")

        let long = [GrammarChatMessage(role: .user, text: String(repeating: "x", count: 5000)),
                    GrammarChatMessage(role: .assistant, text: String(repeating: "y", count: 5000)),
                    GrammarChatMessage(role: .user, text: "short")]
        XCTAssertEqual(GrammarChatPrompt.recent(long).map(\.text), ["short"], "the size cap drops old turns, never the question")
    }

    func testChatIsSavedWithThePillAndOldPillsLoad() throws {
        var pill = GrammarPill(topic: GrammarTopic(title: "Dativ"),
                               lesson: GrammarLesson(title: "Dativ", emoji: "🎁", level: "A1", summary: "",
                                                     cards: [GrammarCard(title: "Idea", body: "dem")], games: []))
        XCTAssertTrue(pill.chat.isEmpty)
        pill.chat.append(GrammarChatMessage(role: .user, text: "Warum dem?"))
        let decoded = try JSONDecoder().decode(GrammarPill.self, from: JSONEncoder().encode(pill))
        XCTAssertEqual(decoded.chat.first?.text, "Warum dem?")
        XCTAssertTrue(GrammarChatPrompt.system(for: pill).contains("Idea: dem"))
    }

    func testPhotosAreResentOnlyWhileRecent() {
        let photo = GrammarChatMessage(role: .user, text: "", imageName: "a.jpg")
        var messages = [photo, GrammarChatMessage(role: .assistant, text: "a")]
        XCTAssertTrue(GrammarChatPrompt.sendsImage(of: photo, in: GrammarChatPrompt.recent(messages)))
        for index in 0..<3 {
            messages.append(GrammarChatMessage(role: .user, text: "q\(index)"))
            messages.append(GrammarChatMessage(role: .assistant, text: "a\(index)"))
        }
        XCTAssertFalse(GrammarChatPrompt.sendsImage(of: photo, in: GrammarChatPrompt.recent(messages)))
    }
}
