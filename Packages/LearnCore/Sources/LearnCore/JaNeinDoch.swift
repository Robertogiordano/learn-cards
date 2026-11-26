import Foundation

/// The word that opens the answer to a yes/no question.
public enum AnswerWord: String, CaseIterable, Codable, Hashable, Sendable {
    case ja, nein, doch

    public var title: String { rawValue.capitalized }
}

/// "Hast du (k)einen Drucker? (+/−)" → "Ja / Nein / Doch, ich habe (k)einen Drucker."
/// Questions are built from the learner's own nouns (with an article) and verbs.
public struct YesNoQuestion: Hashable, Identifiable, Sendable {
    public var id: String { question + (wantsYes ? "+" : "-") }
    /// "Hast du keinen Drucker?"
    public let question: String
    /// True when the question is itself negated (kein / nicht).
    public let isNegated: Bool
    /// The answer to give: (+) positive, (−) negative.
    public let wantsYes: Bool
    /// "Ich habe einen Drucker." without the opening word.
    let positiveClause: String
    /// "Ich habe keinen Drucker." without the opening word.
    let negativeClause: String
    /// Emoji of the word the question is built on, for the card.
    public let emoji: String
    /// The English of the question and of its clauses; nil when the word has no usable translation.
    let english: English?

    /// "Don't you have a printer?" with "I have a printer", "I do have a printer", "I don't have a printer".
    struct English: Hashable, Sendable {
        let question: String
        let positive: String
        let emphatic: String
        let negative: String
    }

    init(question: String, isNegated: Bool, wantsYes: Bool,
         positiveClause: String, negativeClause: String, emoji: String = "💬", english: English? = nil) {
        self.question = question
        self.isNegated = isNegated
        self.wantsYes = wantsYes
        self.positiveClause = positiveClause
        self.negativeClause = negativeClause
        self.emoji = emoji
        self.english = english
    }

    /// "Don't you have a printer?"
    public var englishQuestion: String? { english?.question }

    /// The English of the answer to give.
    public var englishAnswer: String? { english(for: answer) }

    /// The English of any of the sentences built from this question (the answer or a wrong option).
    public func english(for sentence: String) -> String? {
        guard let english else { return nil }
        for word in AnswerWord.allCases {
            if sentence == Self.sentence(word, positiveClause) {
                let yes = word == .nein ? "No" : "Yes"
                return "\(yes), \(word == .doch ? english.emphatic : english.positive)."
            }
            if sentence == Self.sentence(word, negativeClause) {
                return "\(word == .nein ? "No" : "Yes"), \(english.negative)."
            }
        }
        return nil
    }

    /// Ja to a positive question, doch to a negated one; nein whenever the answer is negative.
    public var answerWord: AnswerWord {
        guard wantsYes else { return .nein }
        return isNegated ? .doch : .ja
    }

    /// "Doch, ich habe einen Drucker."
    public var answer: String { Self.sentence(answerWord, wantsYes ? positiveClause : negativeClause) }

    /// The right answer and three wrong ones, shuffled, drawn from every opening word with
    /// either clause: "Ja, ich habe keinen…" is a typical mistake worth catching.
    public func options<R: RandomNumberGenerator>(using rng: inout R) -> [String] {
        let all = AnswerWord.allCases.flatMap { word in
            [Self.sentence(word, positiveClause), Self.sentence(word, negativeClause)]
        }
        var wrong = all.filter { $0 != answer }
        wrong.shuffle(using: &rng)
        var options = Array(wrong.prefix(3)) + [answer]
        options.shuffle(using: &rng)
        return options
    }

    /// The opening word must be right and the negation (kein…/nicht) must match: a typo
    /// elsewhere is "almost", but "einen" for "keinen" is wrong.
    public func check(_ given: String) -> Verdict {
        let words = PhraseChecker.tokens(given)
        guard let first = words.first, first == answerWord.rawValue else { return .wrong }
        let expected = PhraseChecker.tokens(answer)
        guard Self.negations(words) == Self.negations(expected) else { return .wrong }
        return PhraseChecker.check(given, accepted: [answer])
    }

    public func checkSpoken(_ transcripts: [String]) -> Verdict {
        transcripts.map(check).max() ?? .wrong
    }

    private static func negations(_ words: [String]) -> [String] {
        words.filter { $0 == "nicht" || $0.hasPrefix("kein") }
    }

    static func sentence(_ word: AnswerWord, _ clause: String) -> String {
        "\(word.title), \(clause.prefix(1).lowercased())\(clause.dropFirst())"
    }
}

/// A verb that takes almost any object in the accusative: "Hast du …?", "Brauchst du …?".
struct ObjectFrame: Sendable {
    let du: String
    let ich: String
    let english: EnglishVerb

    static let all: [ObjectFrame] = [
        .init(du: "Hast", ich: "habe", english: EnglishVerb(base: "have")),
        .init(du: "Brauchst", ich: "brauche", english: EnglishVerb(base: "need")),
        .init(du: "Möchtest", ich: "möchte", english: .wouldLike),
        .init(du: "Kaufst", ich: "kaufe", english: EnglishVerb(base: "buy")),
        .init(du: "Suchst", ich: "suche", english: EnglishVerb(base: "look for")),
    ]
}

public enum YesNoQuiz {
    /// Verbs that would sound wrong in "Kochst du gern?".
    static let excludedInfinitives: Set<String> = [
        "sein", "haben", "werden", "wissen", "möchten", "mögen", "heißen", "kosten", "geben",
    ]

    /// Nouns that can be asked about: they need an article for ein/kein.
    public static func canUse(noun: VocabEntry) -> Bool {
        noun.partOfSpeech == .noun && noun.article != nil && !noun.german.contains(" ")
    }

    /// Verbs that can be asked about with "gern": complete, plain verbs (no modal, separable or reflexive).
    public static func canUse(verb: VerbEntry) -> Bool {
        guard verb.isComplete, [.regular, .stemChanging, .irregular].contains(verb.group) else { return false }
        let infinitive = verb.infinitive.trimmingCharacters(in: .whitespaces).lowercased()
        return !infinitive.contains(" ") && !excludedInfinitives.contains(infinitive)
            && !verb.form(for: .du).contains(" ") && !verb.form(for: .ich).contains(" ")
    }

    /// "Hast du einen Drucker?" or "Hast du keinen Drucker?".
    static func question(noun: VocabEntry, frame: ObjectFrame, negated: Bool, wantsYes: Bool) -> YesNoQuestion? {
        guard let article = noun.article else { return nil }
        let indefinite = article.accusativeIndefinite
        let negative = "k" + indefinite
        let asked = negated ? negative : indefinite
        return YesNoQuestion(
            question: "\(frame.du) du \(asked) \(noun.german)?",
            isNegated: negated,
            wantsYes: wantsYes,
            positiveClause: "Ich \(frame.ich) \(indefinite) \(noun.german).",
            negativeClause: "Ich \(frame.ich) \(negative) \(noun.german).",
            emoji: noun.emoji,
            english: noun.english.first.flatMap(EnglishGloss.indefinite).map { object in
                english(frame.english, object: object, negated: negated)
            }
        )
    }

    /// "Kochst du gern?" or "Kochst du nicht gern?".
    static func question(verb: VerbEntry, negated: Bool, wantsYes: Bool) -> YesNoQuestion {
        let du = verb.form(for: .du)
        let ich = verb.form(for: .ich)
        let asked = du.prefix(1).uppercased() + du.dropFirst()
        return YesNoQuestion(
            question: negated ? "\(asked) du nicht gern?" : "\(asked) du gern?",
            isNegated: negated,
            wantsYes: wantsYes,
            positiveClause: "Ich \(ich) gern.",
            negativeClause: "Ich \(ich) nicht gern.",
            emoji: verb.emoji,
            english: EnglishGloss.verbBase(verb.english).map { base in
                english(EnglishVerb(base: "like to \(base)"), object: nil, negated: negated)
            }
        )
    }

    /// "Do you have a printer?" / "I have a printer" / "I do have a printer" / "I don't have a printer".
    static func english(_ verb: EnglishVerb, object: String?, negated: Bool) -> YesNoQuestion.English {
        let tail = object.map { " " + $0 } ?? ""
        return YesNoQuestion.English(
            question: verb.question(subject: "you", thirdPerson: false, negated: negated) + tail + "?",
            positive: "I " + verb.present(thirdPerson: false) + tail,
            emphatic: "I " + verb.emphatic(thirdPerson: false) + tail,
            negative: "I " + verb.negative(thirdPerson: false) + tail
        )
    }

    /// `count` questions from the learner's words, half of them negated and half wanting a
    /// positive answer, so ja, nein and doch all come up. Empty when there is nothing to ask about.
    public static func make<R: RandomNumberGenerator>(
        count: Int, nouns: [VocabEntry], verbs: [VerbEntry], using rng: inout R
    ) -> [YesNoQuestion] {
        let nouns = nouns.filter(canUse(noun:)).shuffled(using: &rng)
        let verbs = verbs.filter(canUse(verb:)).shuffled(using: &rng)
        guard !nouns.isEmpty || !verbs.isEmpty else { return [] }

        // Balanced (negated, wantsYes) pairs: the four boxes of the worksheet.
        var shapes: [(Bool, Bool)] = (0..<count).map { index in (index % 2 == 0, (index / 2) % 2 == 0) }
        shapes.shuffle(using: &rng)

        var nounIndex = 0, verbIndex = 0
        var result: [YesNoQuestion] = []
        var seen = Set<String>()
        for (negated, wantsYes) in shapes {
            // About one question in three is about a verb, when there are some.
            let useVerb = !verbs.isEmpty && (nouns.isEmpty || Int.random(in: 0..<3, using: &rng) == 0)
            let question: YesNoQuestion?
            if useVerb {
                question = Self.question(verb: verbs[verbIndex % verbs.count], negated: negated, wantsYes: wantsYes)
                verbIndex += 1
            } else {
                let frame = ObjectFrame.all.randomElement(using: &rng)!
                question = Self.question(noun: nouns[nounIndex % nouns.count], frame: frame,
                                         negated: negated, wantsYes: wantsYes)
                nounIndex += 1
            }
            guard let question, seen.insert(question.id).inserted else { continue }
            result.append(question)
        }
        return result
    }
}
