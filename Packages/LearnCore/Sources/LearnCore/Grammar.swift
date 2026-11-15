import Foundation

// MARK: - Topics

/// A grammar topic the learner can turn into a pill; the catalogue is only a starting point,
/// any free text works too.
public struct GrammarTopic: Codable, Hashable, Identifiable, Sendable {
    public var id: String { title }
    public var title: String
    /// What the pill should cover, passed to the model with the title.
    public var detail: String
    /// "A1", "A2", "B1".
    public var level: String
    public var emoji: String
    /// The chapter of the A1 course the topic belongs to; nil for the other topics.
    public var chapter: Int?

    public init(title: String, detail: String = "", level: String = "", emoji: String = "💊", chapter: Int? = nil) {
        self.title = title
        self.detail = detail
        self.level = level
        self.emoji = emoji
        self.chapter = chapter
    }

    /// The A1 course in order, then the A2 and B1 topics.
    public static var catalogue: [GrammarTopic] { GrammarCourse.a1.topics + extra }

    public static let extra: [GrammarTopic] = [
        GrammarTopic(title: "Reflexive verbs", detail: "mich/dich/sich, accusative vs dative reflexive pronouns", level: "A2", emoji: "🪞"),
        GrammarTopic(title: "Comparative and superlative", detail: "-er, am -sten, umlauts, irregular forms like gut/besser/am besten", level: "A2", emoji: "🏆"),
        GrammarTopic(title: "Subordinate clauses: weil, dass, wenn", detail: "Verb at the end, comma, main clause after the subordinate clause", level: "A2", emoji: "🔗"),
        GrammarTopic(title: "Adjective endings", detail: "After der/ein/no article, in nominative, accusative and dative", level: "B1", emoji: "🎨"),
        GrammarTopic(title: "Relative clauses", detail: "der/die/das as relative pronouns, case of the relative pronoun", level: "B1", emoji: "🪢"),
        GrammarTopic(title: "Genitive case", detail: "des/der + -s, wegen, trotz, während", level: "B1", emoji: "🔑"),
        GrammarTopic(title: "Konjunktiv II for wishes and politeness", detail: "würde + infinitive, hätte, wäre, könnte", level: "B1", emoji: "🌠"),
        GrammarTopic(title: "Passive voice", detail: "werden + past participle in present and past", level: "B1", emoji: "🏭"),
    ]
}

/// A course book's grammar programme: chapters in order, each with its topics and the
/// situations it practises, so lessons use the same contexts as the book.
public struct GrammarCourse: Sendable {
    public struct Chapter: Identifiable, Sendable {
        public var id: Int { number }
        public var number: Int
        public var title: String
        /// What the learner does in the chapter (Sprachhandlungen), used for the examples.
        public var situations: String
        public var topics: [GrammarTopic]
    }

    public var level: String
    public var chapters: [Chapter]

    public var topics: [GrammarTopic] { chapters.flatMap(\.topics) }

    public func chapter(_ number: Int?) -> Chapter? {
        chapters.first { $0.number == number }
    }

    private static func chapter(_ number: Int, _ title: String, situations: String,
                                _ topics: [(String, String, String)]) -> Chapter {
        Chapter(number: number, title: title, situations: situations, topics: topics.map { title, detail, emoji in
            GrammarTopic(title: title, detail: detail, level: "A1", emoji: emoji, chapter: number)
        })
    }

    /// The A1 programme from the learner's course book (table of contents, "Grammatik" column).
    public static let a1 = GrammarCourse(level: "A1", chapters: [
        chapter(1, "Hello!", situations: "greeting and saying goodbye, introducing yourself and others, spelling, asking questions", [
            ("Personal pronouns (Personalpronomen)", "ich, du, er/sie/es, wir, ihr, sie/Sie; du or Sie", "🙋"),
            ("Present tense (Verbkonjugation Präsens)", "Regular endings, sein and haben, stem-changing verbs (e → i, a → ä)", "🏃"),
            ("Verb position (Verbpositionen)", "Verb in second place in statements and W-questions, verb first in yes/no questions", "🧩"),
        ]),
        chapter(2, "Things around me", situations: "naming objects, asking what something is called and what it costs, agreeing and contradicting", [
            ("Articles (Artikel)", "der/die/das and ein/eine, gender hints from noun endings", "🎯"),
            ("Plural (Plural)", "The main plural patterns (-e, -en, -er, -s, umlaut) and how to guess them", "📚"),
            ("Compound nouns (Komposita)", "How compounds are built, the last word gives the article, linking -s- and -n-", "🧱"),
            ("Negation (Negation)", "kein vs nicht, where nicht goes, doch as an answer", "🚫"),
        ]),
        chapter(3, "Food and drink", situations: "talking about likes and dislikes, asking when you don't understand, ordering in a café or restaurant", [
            ("Verbs with an accusative object (Verben mit Akkusativobjekt)", "den/einen/keinen, accusative after haben, möchten, essen, trinken, brauchen, kaufen", "🍽️"),
            ("Zero article (Nullartikel)", "No article for uncountable food and drinks, professions, nationalities, plural in general", "🥖"),
            ("Punctuation (Satzzeichen)", "Full stop, question mark, exclamation mark, commas in lists and before aber/denn", "✏️"),
        ]),
        chapter(4, "Time and appointments", situations: "telling the time and the date, making, moving and cancelling appointments", [
            ("Separable and inseparable verbs (trennbare und untrennbare Verben)", "Prefix at the end (aufstehen, anrufen), inseparable be-/ver-/er-, stress", "✂️"),
            ("Adverbs and conjunctions (Adverbien und Konjunktionen)", "und, aber, oder, denn (no inversion) vs dann, danach, zuerst (inversion)", "🔗"),
            ("Ordinal numbers (Ordinalzahlen)", "der erste, zweite, dritte…, dates: am ersten Mai", "🥇"),
            ("Time prepositions (temporale Präpositionen)", "um, am, im, von … bis, ab, vor, nach", "⏰"),
        ]),
        chapter(5, "Work and jobs", situations: "introducing your work, describing professions and workplaces, talking about colleagues", [
            ("Possessive articles (Possessivartikel)", "mein, dein, sein, ihr, unser, euer, Ihr with their endings", "👜"),
            ("Modal prepositions (modale Präpositionen)", "mit, ohne, als, wie: how and with what (mit dem Bus, ohne Zucker, als Lehrer)", "🧰"),
        ]),
        chapter(6, "Health and the body", situations: "talking about the body and how you feel, giving and understanding instructions and advice, talking to a doctor", [
            ("Modal verbs (Modalverben)", "können, müssen, dürfen, sollen, wollen, möchten: forms and the infinitive at the end", "💪"),
            ("The pronoun man (man)", "man + verb in er-form for rules and general statements: Hier darf man nicht rauchen", "👥"),
            ("Imperative (Imperativ)", "du, ihr and Sie commands, with separable verbs, bitte, sein in the imperative", "📢"),
        ]),
        chapter(7, "Travel and the past", situations: "booking a hotel room, telling what happened, writing e-mails and postcards", [
            ("Perfect tense (Perfekt)", "haben or sein, past participle with ge-, separable and -ieren verbs", "⏪"),
            ("Simple past of some verbs (einige Verben im Präteritum)", "war, hatte, es gab, and the modals konnte, musste, wollte", "🕰️"),
            ("Place prepositions (lokale Präpositionen)", "in, nach, zu, aus, von, bei: where to, where, where from (nach Berlin, zum Arzt, aus Italien)", "🧭"),
        ]),
        chapter(8, "Gifts and celebrations", situations: "describing and choosing presents, giving and receiving, congratulating and inviting", [
            ("Verbs with dative and accusative object (Verben mit Dativ- und Akkusativobjekt)", "geben, schenken, zeigen, bringen: person in the dative, thing in the accusative", "🎁"),
            ("Verbs with a dative object (Verben mit Dativobjekt)", "helfen, danken, gefallen, gehören, schmecken, passen; dem/der/den + n", "🤝"),
            ("Order of dative and accusative pronouns (Stellung von Personalpronomen)", "Two nouns: dative first; accusative pronoun before dative (ich gebe es dir)", "🔀"),
        ]),
        chapter(9, "Home and the city", situations: "describing a flat and a town, saying where things are and where they go, asking for and giving directions", [
            ("Prepositions with accusative (Präpositionen mit Akkusativ)", "durch, für, gegen, ohne, um", "➡️"),
            ("Prepositions with dative (Präpositionen mit Dativ)", "aus, bei, mit, nach, seit, von, zu, gegenüber; zum, zur, beim, vom", "📍"),
            ("Two-way prepositions (Wechselpräpositionen)", "in, an, auf, über, unter, vor, hinter, neben, zwischen: wohin (accusative) vs wo (dative)", "🔄"),
            ("Verbs for positions and directions (Verben für Positionen und Richtungen)", "stellen/stehen, legen/liegen, hängen, setzen/sitzen", "🛋️"),
        ]),
    ])
}

// MARK: - Lesson content

public struct GrammarExample: Codable, Hashable, Sendable {
    public var german: String
    public var english: String

    public init(german: String, english: String) {
        self.german = german
        self.english = english
    }
}

/// A small declension or conjugation table; empty when the card has none.
public struct GrammarTable: Codable, Hashable, Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String] = [], rows: [[String]] = []) {
        self.headers = headers
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// One screen of theory: a short explanation, examples and maybe a table.
public struct GrammarCard: Codable, Hashable, Sendable {
    public var title: String
    /// Short text; **bold** marks the key forms.
    public var body: String
    public var examples: [GrammarExample]
    public var table: GrammarTable
    /// A memory trick or a common pitfall; may be empty.
    public var tip: String

    public init(title: String, body: String, examples: [GrammarExample] = [], table: GrammarTable = GrammarTable(), tip: String = "") {
        self.title = title
        self.body = body
        self.examples = examples
        self.table = table
        self.tip = tip
    }
}

public struct GrammarPair: Codable, Hashable, Sendable {
    public var left: String
    public var right: String

    public init(left: String, right: String) {
        self.left = left
        self.right = right
    }
}

/// The kinds of interactive items, shared by the games in the lesson and the exercises.
public enum GrammarTaskKind: String, Codable, CaseIterable, Sendable {
    /// Pick the right form among options.
    case choice
    /// Type the missing word in a sentence with "___".
    case gap
    /// Put the word tiles in the right order.
    case order
    /// Rewrite the sentence as asked (e.g. in the perfect tense).
    case transform
    /// Join each item on the left with its partner on the right.
    case match
    /// Drop each item into its bucket (e.g. accusative vs dative).
    case sort

    public var title: String {
        switch self {
        case .choice: return "Choose"
        case .gap: return "Fill the gap"
        case .order: return "Build the sentence"
        case .transform: return "Transform"
        case .match: return "Match"
        case .sort: return "Sort"
        }
    }

    public var systemImage: String {
        switch self {
        case .choice: return "list.bullet"
        case .gap: return "character.cursor.ibeam"
        case .order: return "square.grid.3x1.below.line.grid.1x2"
        case .transform: return "arrow.triangle.2.circlepath"
        case .match: return "link"
        case .sort: return "tray.2"
        }
    }

    public static let gameKinds: [GrammarTaskKind] = [.choice, .match, .sort]
    public static let exerciseKinds: [GrammarTaskKind] = [.choice, .gap, .order, .transform, .match]
}

/// One interactive item. Fields not used by a kind are empty.
public struct GrammarTask: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: GrammarTaskKind
    /// The instruction or the sentence, with "___" for a gap.
    public var prompt: String
    /// Translation or hint shown under the prompt; may be empty.
    public var english: String
    /// For choice.
    public var options: [String]
    /// Accepted answers: the right option for choice, the missing word(s) for gap, full sentences
    /// for order and transform (the first one gives the tiles of an order task).
    public var answers: [String]
    /// For match (left ↔ right) and sort (item → bucket).
    public var pairs: [GrammarPair]
    /// Why the answer is right, shown after answering.
    public var explanation: String
    /// The learner's own words the item is built on.
    public var uses: [String]

    public init(id: UUID = UUID(), kind: GrammarTaskKind, prompt: String, english: String = "",
                options: [String] = [], answers: [String] = [], pairs: [GrammarPair] = [],
                explanation: String = "", uses: [String] = []) {
        self.id = id
        self.kind = kind
        self.prompt = prompt
        self.english = english
        self.options = options
        self.answers = answers
        self.pairs = pairs
        self.explanation = explanation
        self.uses = uses
    }

    /// For sort: the buckets in order of first appearance.
    public var buckets: [String] {
        var seen = Set<String>()
        return pairs.map(\.right).filter { seen.insert($0).inserted }
    }

    /// For order: the tiles of the first accepted sentence, in the sentence's order.
    public var tiles: [String] {
        (answers.first ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// For choice: the index of the right option.
    public var correctIndex: Int? {
        guard let answer = answers.first else { return nil }
        let key = GrammarChecker.key(answer)
        return options.firstIndex { GrammarChecker.key($0) == key }
    }

    /// The answer shown after a mistake.
    public var displayAnswer: String {
        switch kind {
        case .match, .sort: return pairs.map { "\($0.left) → \($0.right)" }.joined(separator: ", ")
        default: return answers.first ?? ""
        }
    }

    /// Items the app cannot run are dropped instead of showing a broken screen.
    public var isPlayable: Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch kind {
        case .choice: return options.count >= 2 && correctIndex != nil
        case .gap: return !answers.isEmpty && prompt.contains("___")
        case .transform: return !answers.isEmpty
        case .order: return tiles.count >= 2
        case .match:
            return pairs.count >= 2 && Set(pairs.map { GrammarChecker.key($0.left) }).count == pairs.count
                && Set(pairs.map { GrammarChecker.key($0.right) }).count == pairs.count
        case .sort: return pairs.count >= 3 && buckets.count >= 2 && buckets.count <= 4
        }
    }
}

/// The theory part of a pill, written once by the model.
public struct GrammarLesson: Codable, Hashable, Sendable {
    public var title: String
    public var emoji: String
    public var level: String
    /// One sentence: what it is and when you need it.
    public var summary: String
    public var cards: [GrammarCard]
    /// Little games played between the cards.
    public var games: [GrammarTask]

    public init(title: String, emoji: String, level: String, summary: String, cards: [GrammarCard], games: [GrammarTask]) {
        self.title = title
        self.emoji = emoji
        self.level = level
        self.summary = summary
        self.cards = cards
        self.games = games
    }

    public enum Step: Hashable, Sendable {
        case card(GrammarCard)
        case game(GrammarTask)
    }

    /// Two cards, then a game after each further card; games left over close the lesson.
    public var steps: [Step] {
        var steps: [Step] = []
        var games = self.games[...]
        for (index, card) in cards.enumerated() {
            steps.append(.card(card))
            if index >= 1, let game = games.popFirst() {
                steps.append(.game(game))
            }
        }
        steps += games.map(Step.game)
        return steps
    }
}

// MARK: - Pills and progress

public struct GrammarMistake: Codable, Hashable, Sendable {
    public var prompt: String
    public var given: String
    public var expected: String

    public init(prompt: String, given: String, expected: String) {
        self.prompt = prompt
        self.given = given
        self.expected = expected
    }
}

/// A topic, its lesson, the latest exercises and how the learner is doing.
public struct GrammarPill: Codable, Hashable, Identifiable, Sendable {
    public static let maximumMistakes = 12
    public static let keptScores = 5
    public static let starThreshold = 0.8

    public var id: UUID
    public var topic: GrammarTopic
    public var lesson: GrammarLesson
    public var createdAt: Date
    public var lessonCompleted: Bool
    /// The current exercise set; replaced each time the learner asks for new ones.
    public var exercises: [GrammarTask]
    /// Share of right answers in the latest practice rounds, oldest first.
    public var scores: [Double]
    public var lastPracticed: Date?
    /// Recent wrong answers, so new exercises can target them.
    public var mistakes: [GrammarMistake]
    /// Stored optional so pills saved before the chat existed still load.
    private var chatMessages: [GrammarChatMessage]?

    /// Questions and answers about this pill, oldest first.
    public var chat: [GrammarChatMessage] {
        get { chatMessages ?? [] }
        set { chatMessages = Array(newValue.suffix(Self.keptChatMessages)) }
    }

    /// The chat kept on the phone; only the last few go to the model.
    public static let keptChatMessages = 100

    public init(id: UUID = UUID(), topic: GrammarTopic, lesson: GrammarLesson, createdAt: Date = Date(),
                lessonCompleted: Bool = false, exercises: [GrammarTask] = [], scores: [Double] = [],
                lastPracticed: Date? = nil, mistakes: [GrammarMistake] = []) {
        self.id = id
        self.topic = topic
        self.lesson = lesson
        self.createdAt = createdAt
        self.lessonCompleted = lessonCompleted
        self.exercises = exercises
        self.scores = scores
        self.lastPracticed = lastPracticed
        self.mistakes = mistakes
    }

    /// Average of the last three rounds, nil before the first one.
    public var mastery: Double? {
        let recent = scores.suffix(3)
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    public var hasStar: Bool { (mastery ?? 0) >= Self.starThreshold }

    public mutating func record(score: Double, mistakes new: [GrammarMistake], at date: Date = Date()) {
        scores.append(min(max(score, 0), 1))
        if scores.count > Self.keptScores { scores.removeFirst(scores.count - Self.keptScores) }
        lastPracticed = date
        mistakes += new
        if mistakes.count > Self.maximumMistakes { mistakes.removeFirst(mistakes.count - Self.maximumMistakes) }
    }
}

// MARK: - Chat

public struct GrammarChatMessage: Codable, Hashable, Identifiable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public var id: UUID
    public var role: Role
    public var text: String
    public var date: Date
    /// File name of a photo sent with the question (e.g. a page of the course book).
    public var imageName: String?

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date(), imageName: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.imageName = imageName
    }
}

/// A tutor that answers doubts about one pill. To stay cheap it sends a compact lesson
/// summary, the recent mistakes and only the latest turns of the conversation.
public enum GrammarChatPrompt {
    /// Messages of the conversation sent with each question (the rest stays on the phone).
    public static let window = 12
    /// Rough cap on the characters of those messages, for very long answers.
    public static let windowCharacters = 6000
    /// Answers are short by design.
    public static let maxTokens = 600
    /// A photo travels again only while its question is among the last few messages;
    /// after that the model gets a short note instead, so old photos stop costing tokens.
    public static let imageWindow = 4
    /// The question sent with a photo and no text.
    public static let photoOnlyQuestion = "Here is a page from my book. Help me understand it."
    public static let earlierPhotoNote = "[photo sent earlier]"

    public static func system(for pill: GrammarPill) -> String {
        let lesson = pill.lesson
        let outline = lesson.cards.map { card in
            let examples = card.examples.prefix(2).map(\.german).joined(separator: " / ")
            return "- \(card.title): \(card.body)" + (examples.isEmpty ? "" : " (e.g. \(examples))")
        }.joined(separator: "\n")
        var text = """
        You are a patient German tutor in a learning app. The learner (level \(lesson.level.isEmpty ? "A1" : lesson.level), \
        native language probably Italian, app in English) is studying "\(pill.topic.title)" and asks you about doubts.

        Lesson they studied:
        \(outline)
        """
        if let chapter = GrammarCourse.a1.chapter(pill.topic.chapter) {
            text += "\n\nIt is chapter \(chapter.number) of their A1 course book (\(chapter.title)); avoid grammar they have not met yet."
        }
        if !pill.mistakes.isEmpty {
            let mistakes = pill.mistakes.suffix(5).map { "- \($0.prompt): answered \"\($0.given)\", right \"\($0.expected)\"" }
            text += "\n\nTheir recent mistakes on this topic:\n" + mistakes.joined(separator: "\n")
        }
        text += """


        How to answer:
        - Reply in the language of the question (Italian or English); German examples stay in German.
        - Be short and concrete: usually 2-6 sentences or a few bullet points, with 1-3 simple example sentences. \
        Use **bold** for the key forms. No headings, no tables.
        - Explain simply, like a friend who knows grammar; compare with Italian or English when it helps.
        - If the question is about something else in German, answer briefly anyway. If it is not about German, \
        say kindly that you help with German.
        - Every German sentence must be correct. If you are not sure about something, say so.
        - The learner may send a photo of their book or exercises: read it and answer about what they see \
        (explain the rule, solve and explain the exercise, translate). If the photo is unreadable, say so.
        """
        return text
    }

    /// Whether a message's photo is sent again with this request.
    public static func sendsImage(of message: GrammarChatMessage, in recent: [GrammarChatMessage]) -> Bool {
        guard message.imageName != nil, let index = recent.firstIndex(where: { $0.id == message.id }) else { return false }
        return index >= recent.count - imageWindow
    }

    /// The latest messages, oldest first, starting with a question and within the size cap.
    public static func recent(_ messages: [GrammarChatMessage]) -> [GrammarChatMessage] {
        var picked: [GrammarChatMessage] = []
        var characters = 0
        for message in messages.suffix(window).reversed() {
            characters += message.text.count
            if characters > windowCharacters && !picked.isEmpty { break }
            picked.insert(message, at: 0)
        }
        while picked.first?.role == .assistant { picked.removeFirst() }
        return picked
    }

    /// Ready-made questions, the last mistake first.
    public static func suggestions(for pill: GrammarPill) -> [String] {
        var result: [String] = []
        if let mistake = pill.mistakes.last {
            result.append("Why is “\(mistake.expected)” right and not “\(mistake.given)”?")
        }
        result += ["Explain it again more simply", "Give me 3 more everyday examples", "How do I remember this?"]
        return result
    }
}

// MARK: - Checking answers

public enum GrammarChecker {
    /// Grammar lives in the endings, so there is no typo tolerance: only case, punctuation,
    /// spacing and ä/ae-style spellings are ignored.
    public static func key(_ text: String) -> String {
        AnswerChecker.foldGerman(AnswerChecker.normalize(text))
    }

    public static func check(_ given: String, accepted: [String]) -> Bool {
        let given = key(given)
        guard !given.isEmpty else { return false }
        return accepted.contains { key($0) == given }
    }

    /// Typed answer for gap and transform; for gap a full sentence with the gap filled also counts.
    public static func check(_ given: String, task: GrammarTask) -> Bool {
        if check(given, accepted: task.answers) { return true }
        guard task.kind == .gap else { return false }
        let sentences = task.answers.map { task.prompt.replacingOccurrences(of: "___", with: $0) }
        return check(given, accepted: sentences)
    }

    /// Order: the chosen tiles must spell one of the accepted sentences.
    public static func check(tiles: [String], task: GrammarTask) -> Bool {
        check(tiles.joined(separator: " "), accepted: task.answers)
    }
}

// MARK: - The learner's vocabulary

/// One of the learner's items, as the exercise prompt sees it.
public struct GrammarVocabItem: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case noun, verb, other, phrase
    }

    public var kind: Kind
    /// Compact line: "der Tisch (pl. Tische) = table", "fahren: fahre, fährst… = to drive".
    public var line: String
    /// Already practised at least once.
    public var known: Bool

    public init(kind: Kind, line: String, known: Bool) {
        self.kind = kind
        self.line = line
        self.known = known
    }

    public static func noun(german: String, article: Article?, plural: String?, english: [String], known: Bool) -> GrammarVocabItem {
        var text = [article?.rawValue, german].compactMap { $0 }.joined(separator: " ")
        if let plural, !plural.isEmpty { text += " (pl. \(plural))" }
        return GrammarVocabItem(kind: .noun, line: "\(text) = \(english.prefix(2).joined(separator: ", "))", known: known)
    }

    public static func word(german: String, partOfSpeech: PartOfSpeech, english: [String], known: Bool) -> GrammarVocabItem {
        GrammarVocabItem(kind: .other, line: "\(german) [\(partOfSpeech.rawValue)] = \(english.prefix(2).joined(separator: ", "))", known: known)
    }

    public static func verb(_ entry: VerbEntry, known: Bool) -> GrammarVocabItem {
        var text = entry.infinitive
        if entry.forms.count == Person.allCases.count { text += ": " + entry.forms.joined(separator: ", ") }
        return GrammarVocabItem(kind: .verb, line: "\(text) = \(entry.english) [\(entry.group.rawValue)]", known: known)
    }

    public static func phrase(german: String, english: String, known: Bool) -> GrammarVocabItem {
        GrammarVocabItem(kind: .phrase, line: "\(german) = \(english)", known: known)
    }
}

public enum GrammarVocabulary {
    public static let limits: [GrammarVocabItem.Kind: Int] = [.noun: 50, .verb: 30, .other: 25, .phrase: 12]

    /// A sample per kind, known items first, shuffled so each exercise set uses other words.
    public static func sample<R: RandomNumberGenerator>(_ items: [GrammarVocabItem], using rng: inout R) -> [GrammarVocabItem] {
        var result: [GrammarVocabItem] = []
        for kind in [GrammarVocabItem.Kind.noun, .verb, .other, .phrase] {
            let ofKind = items.filter { $0.kind == kind }
            let ordered = ofKind.filter(\.known).shuffled(using: &rng) + ofKind.filter { !$0.known }.shuffled(using: &rng)
            result += ordered.prefix(limits[kind] ?? 0)
        }
        return result
    }

    public static func text(_ items: [GrammarVocabItem]) -> String {
        let sections: [(GrammarVocabItem.Kind, String)] = [(.noun, "Nouns"), (.verb, "Verbs (present: ich, du, er/sie/es, wir, ihr, sie/Sie)"),
                                                           (.other, "Other words"), (.phrase, "Phrases")]
        return sections.compactMap { kind, title in
            let lines = items.filter { $0.kind == kind }.map { "- " + $0.line }
            return lines.isEmpty ? nil : "\(title):\n" + lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}

// MARK: - Prompts

public enum GrammarPrompt {
    public static let exerciseCount = 10

    private static let taskRules = """
    Item kinds and their fields (every field is always present; use "" or [] when unused):
    - "choice": prompt = a German sentence with "___" (or a short question); options = 3-4 short \
    forms, all plausible (typical learner mistakes); answers = [the right option, written exactly as in options].
    - "gap": prompt = a German sentence with exactly one "___" for one or two words; answers = every \
    correct way to fill it (e.g. ["den"], ["bin gegangen"]).
    - "order": prompt = an English instruction like "Build the sentence: I'm going to the cinema \
    tomorrow."; answers = every correct German word order, as full sentences with final punctuation \
    attached to the last word (the first one gives the tiles, 4-9 words).
    - "transform": prompt = what to do and the sentence, e.g. "Put in the perfect tense: Ich esse \
    einen Apfel."; answers = every correct full result.
    - "match": prompt = a short instruction; pairs = 3-5 {left, right} to join, every left and every \
    right unique (e.g. "ich" → "mich").
    - "sort": prompt = a short instruction; pairs = 4-8 {left: item, right: bucket}, using 2-3 \
    distinct bucket names (e.g. "auf den Tisch" → "Wohin? (Akk)").
    english = an English translation of the sentence or a short hint ("" for match and sort). \
    explanation = one or two simple English sentences on why. uses = the learner's words the item \
    is built on, written as they appear in the list ([] if none).
    Every German sentence must be natural and 100% grammatically correct; double-check articles, \
    case endings, verb position and every accepted answer.
    """

    // MARK: Lesson

    public static func lessonSystem() -> String {
        """
        You are a friendly German teacher writing a "grammar pill": a short, intuitive mini-lesson \
        for an English-speaking learner (A1-B1) who studies on a phone. Explain in simple English, \
        no jargon without an example, like a good friend who knows grammar.

        Answer with JSON only:
        {"title", "emoji", "level", "summary", "cards": [...], "games": [...]}
        - title: short English name of the topic; emoji: one emoji; level: "A1", "A2" or "B1".
        - summary: one sentence: what it is and when you need it.
        - cards: 4-6 cards, each one idea that fits on a phone screen:
          {"title", "body", "examples": [{"german", "english"}], "table": {"headers", "rows"}, "tip"}
          1. The big idea and WHEN you use it, with 2-3 real-life situations (shop, work, friends…).
          2-4. How it works, step by step, simplest pattern first. Put the key forms in **bold**. \
          Add a small table (max 4 columns, max 6 rows) where forms are learned best that way; \
          otherwise headers and rows are [].
          Last card: common mistakes and how to avoid them.
          body: max 70 words. examples: 2-3 short everyday sentences, the key form in **bold**. \
          tip: a memory trick or pitfall, max 20 words, or "".
        - games: exactly 3 quick games to check understanding between the cards, using only very \
        common words: one "sort", one "match" and one "choice".

        \(taskRules)
        """
    }

    public static func lessonInstruction(for topic: GrammarTopic) -> String {
        var text = "Topic: \(topic.title)"
        if !topic.detail.isEmpty { text += "\nCover: \(topic.detail)" }
        if !topic.level.isEmpty { text += "\nLevel: \(topic.level)" }
        if let chapter = GrammarCourse.a1.chapter(topic.chapter) {
            text += "\nIt is chapter \(chapter.number) of the learner's A1 course book (\(chapter.title)): take the situations " +
                "and examples from \(chapter.situations). Use only grammar from this chapter or earlier ones."
        }
        return text
    }

    // MARK: Exercises

    public static func exercisesSystem() -> String {
        """
        You are a German teacher preparing practice exercises on one grammar topic for an \
        English-speaking learner. You receive the topic, the lesson the learner just studied, the \
        learner's own vocabulary and their recent mistakes on this topic.

        Write exercises that train exactly this topic, built around the learner's own vocabulary: \
        nearly every sentence uses at least one of their nouns, verbs or phrases (with the article, \
        plural or verb forms given in the list), so grammar and vocabulary grow together. Use other \
        words only when needed for natural sentences, and keep them simple. Vary the words: do not \
        reuse one word in more than two items. Go from easier to harder. When there are recent \
        mistakes, include 2-3 items that train the same point with other words.

        Answer with JSON only: {"exercises": [...]}, a mix of kinds: about 3 "choice", 3 "gap", \
        2 "order", 1-2 "transform" (only when the topic has something to transform; otherwise \
        more "gap") and 1 "match".

        \(taskRules)
        """
    }

    public static func exercisesInstruction(pill: GrammarPill, vocabulary: [GrammarVocabItem],
                                            count: Int = exerciseCount) -> String {
        let lesson = pill.lesson
        let outline = lesson.cards.map { "- \($0.title): \($0.body)" }.joined(separator: "\n")
        var text = """
        Topic: \(pill.topic.title)\(pill.topic.detail.isEmpty ? "" : " (\(pill.topic.detail))")
        Level: \(lesson.level)
        Exercises: \(count)

        Lesson the learner studied:
        \(outline)

        Learner's vocabulary:
        \(vocabulary.isEmpty ? "(empty: use very common A1 words)" : GrammarVocabulary.text(vocabulary))
        """
        if let chapter = GrammarCourse.a1.chapter(pill.topic.chapter) {
            text += "\n\nCourse: chapter \(chapter.number) of an A1 book (\(chapter.title)). Prefer situations like " +
                "\(chapter.situations), and use no grammar from later chapters (keep sentences A1-simple)."
        }
        if !pill.mistakes.isEmpty {
            let mistakes = pill.mistakes.suffix(8).map { "- \($0.prompt) — answered \"\($0.given)\", right: \"\($0.expected)\"" }
            text += "\n\nRecent mistakes:\n" + mistakes.joined(separator: "\n")
        }
        return text
    }

    // MARK: Schemas

    private static var taskSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let pair: [String: Any] = [
            "type": "object",
            "properties": ["left": string, "right": string],
            "required": ["left", "right"],
            "additionalProperties": false,
        ]
        let kind: [String: Any] = ["type": "string", "enum": GrammarTaskKind.allCases.map(\.rawValue)]
        let properties: [String: Any] = [
            "kind": kind, "prompt": string, "english": string, "options": strings, "answers": strings,
            "pairs": ["type": "array", "items": pair] as [String: Any], "explanation": string, "uses": strings,
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["kind", "prompt", "english", "options", "answers", "pairs", "explanation", "uses"],
            "additionalProperties": false,
        ]
    }

    public static var lessonSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let example: [String: Any] = [
            "type": "object",
            "properties": ["german": string, "english": string],
            "required": ["german", "english"],
            "additionalProperties": false,
        ]
        let table: [String: Any] = [
            "type": "object",
            "properties": ["headers": strings, "rows": ["type": "array", "items": strings] as [String: Any]],
            "required": ["headers", "rows"],
            "additionalProperties": false,
        ]
        let cardProperties: [String: Any] = [
            "title": string, "body": string, "examples": ["type": "array", "items": example] as [String: Any],
            "table": table, "tip": string,
        ]
        let card: [String: Any] = [
            "type": "object",
            "properties": cardProperties,
            "required": ["title", "body", "examples", "table", "tip"],
            "additionalProperties": false,
        ]
        let properties: [String: Any] = [
            "title": string, "emoji": string, "level": string, "summary": string,
            "cards": ["type": "array", "items": card] as [String: Any],
            "games": ["type": "array", "items": taskSchema] as [String: Any],
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["title", "emoji", "level", "summary", "cards", "games"],
            "additionalProperties": false,
        ]
    }

    public static var exercisesSchema: [String: Any] {
        [
            "type": "object",
            "properties": ["exercises": ["type": "array", "items": taskSchema] as [String: Any]],
            "required": ["exercises"],
            "additionalProperties": false,
        ]
    }
}

// MARK: - Built-in lessons

/// The A1 lessons written in advance and shipped with the app, so the course needs no model call.
public enum GrammarLibrary {
    /// Lessons by topic title.
    public static let a1: [String: GrammarLesson] = load()

    public static func lesson(for topic: GrammarTopic) -> GrammarLesson? {
        a1[topic.title]
    }

    /// Every bundled file must parse; a broken one shows up in the tests, not as a missing lesson.
    public static func load(bundle: Bundle? = nil) -> [String: GrammarLesson] {
        let bundle = bundle ?? .module
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("grammar-a1-") }
        var result: [String: GrammarLesson] = [:]
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let lessons = try? GrammarParser.parseBundledLessons(data, course: .a1) else { continue }
            result.merge(lessons) { first, _ in first }
        }
        return result
    }
}

// MARK: - Parsing

public enum GrammarParser {
    public enum GrammarError: LocalizedError, Equatable {
        case emptyLesson
        case noExercises

        public var errorDescription: String? {
            switch self {
            case .emptyLesson: return "The model wrote no lesson. Try again or try another topic."
            case .noExercises: return "The model wrote no usable exercises. Try again."
            }
        }
    }

    private struct RawTask: Decodable {
        var kind: String?
        var prompt: String?
        var english: String?
        var options: [String]?
        var answers: [String]?
        var pairs: [GrammarPair]?
        var explanation: String?
        var uses: [String]?
    }

    private struct RawCard: Decodable {
        var title: String?
        var body: String?
        var examples: [GrammarExample]?
        var table: GrammarTable?
        var tip: String?
    }

    private struct RawLesson: Decodable {
        /// Only in bundled lessons: the course topic the lesson belongs to.
        var topic: String?
        var title: String?
        var emoji: String?
        var level: String?
        var summary: String?
        var cards: [RawCard]?
        var games: [RawTask]?
    }

    private struct RawExercises: Decodable {
        var exercises: [RawTask]?
    }

    public static func parseLesson(_ content: String, topic: GrammarTopic) throws -> GrammarLesson {
        try lesson(from: decode(content), topic: topic)
    }

    /// Lessons shipped with the app: `{"lessons": [{"topic": "<course topic title>", ...lesson}]}`.
    /// Returns the lessons by topic title; a lesson for an unknown topic is an error.
    public static func parseBundledLessons(_ data: Data, course: GrammarCourse) throws -> [String: GrammarLesson] {
        struct File: Decodable { var lessons: [RawLesson] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { throw ExtractionParser.ParseError.invalidJSON }
        var result: [String: GrammarLesson] = [:]
        for raw in file.lessons {
            guard let topic = course.topics.first(where: { $0.title == raw.topic }) else {
                throw ExtractionParser.ParseError.invalidJSON
            }
            result[topic.title] = try lesson(from: raw, topic: topic)
        }
        return result
    }

    private static func lesson(from raw: RawLesson, topic: GrammarTopic) throws -> GrammarLesson {
        let cards = (raw.cards ?? []).compactMap { card -> GrammarCard? in
            let body = clean(card.body)
            guard !body.isEmpty else { return nil }
            let examples = (card.examples ?? []).filter { !clean($0.german).isEmpty }
            return GrammarCard(title: clean(card.title), body: body, examples: examples,
                               table: tidy(card.table), tip: clean(card.tip))
        }
        guard !cards.isEmpty else { throw GrammarError.emptyLesson }
        let title = clean(raw.title)
        let emoji = clean(raw.emoji)
        return GrammarLesson(title: title.isEmpty ? topic.title : title,
                             emoji: emoji.isEmpty ? topic.emoji : emoji,
                             level: clean(raw.level).isEmpty ? topic.level : clean(raw.level),
                             summary: clean(raw.summary),
                             cards: cards,
                             games: tasks(raw.games))
    }

    public static func parseExercises(_ content: String) throws -> [GrammarTask] {
        let raw: RawExercises = try decode(content)
        let exercises = tasks(raw.exercises)
        guard !exercises.isEmpty else { throw GrammarError.noExercises }
        return exercises
    }

    private static func decode<T: Decodable>(_ content: String) throws -> T {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        guard let value = try? JSONDecoder().decode(T.self, from: Data(String(content[start...end]).utf8)) else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        return value
    }

    private static func tasks(_ raw: [RawTask]?) -> [GrammarTask] {
        (raw ?? []).compactMap { raw in
            guard let kind = raw.kind.flatMap(GrammarTaskKind.init(rawValue:)) else { return nil }
            let task = GrammarTask(
                kind: kind,
                prompt: clean(raw.prompt),
                english: clean(raw.english),
                options: (raw.options ?? []).map(clean).filter { !$0.isEmpty },
                answers: (raw.answers ?? []).map(clean).filter { !$0.isEmpty },
                pairs: (raw.pairs ?? []).map { GrammarPair(left: clean($0.left), right: clean($0.right)) }
                    .filter { !$0.left.isEmpty && !$0.right.isEmpty },
                explanation: clean(raw.explanation),
                uses: (raw.uses ?? []).map(clean).filter { !$0.isEmpty }
            )
            return task.isPlayable ? task : nil
        }
    }

    /// Rows padded or cut to the header width, so the grid never breaks.
    private static func tidy(_ table: GrammarTable?) -> GrammarTable {
        guard let table, !table.rows.isEmpty else { return GrammarTable() }
        let width = max(table.headers.count, table.rows.map(\.count).max() ?? 0)
        guard width > 0 else { return GrammarTable() }
        func fit(_ row: [String]) -> [String] {
            Array((row.map(clean) + Array(repeating: "", count: width)).prefix(width))
        }
        return GrammarTable(headers: table.headers.isEmpty ? [] : fit(table.headers), rows: table.rows.map(fit))
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
