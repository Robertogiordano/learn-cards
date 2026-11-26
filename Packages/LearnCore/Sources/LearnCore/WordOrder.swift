import Foundation

/// The shape of a sentence to build, each with its own verb position.
public enum WordOrderPattern: String, CaseIterable, Codable, Hashable, Sendable {
    /// "Ich stehe um 8 Uhr auf." or "Um 8 Uhr stehe ich auf.": the verb is always second.
    case statement
    /// "Wann stehst du auf?": question word, then the verb.
    case wQuestion
    /// "Stehst du morgen auf?": the verb first.
    case yesNoQuestion

    public var title: String {
        switch self {
        case .statement: return "Statements"
        case .wQuestion: return "W-questions"
        case .yesNoQuestion: return "Yes/no questions"
        }
    }

    /// One line on where the verb goes.
    public var rule: String {
        switch self {
        case .statement: return "The verb is in second position: whatever comes first, the subject follows the verb."
        case .wQuestion: return "Question word, then the verb, then the subject."
        case .yesNoQuestion: return "The verb comes first, then the subject."
        }
    }
}

/// "Sätze bilden": put the pieces of a sentence in order.
public struct WordOrderExercise: Hashable, Identifiable, Sendable {
    public var id: String { answer }
    public let pattern: WordOrderPattern
    /// The pieces, shuffled, written as they appear inside a sentence ("ich", "am Sonntag").
    public let tiles: [String]
    /// The sentence shown as the solution.
    public let answer: String
    /// Every order that counts as right (a statement can start with the subject or the time).
    public let accepted: [String]
    public let emoji: String
    /// The separable prefix ("auf"), if the verb has one.
    public let prefix: String?

    /// The pattern's rule, plus the separable prefix when there is one.
    public var rule: String {
        guard let prefix else { return pattern.rule }
        return pattern.rule + " The prefix \(prefix) goes to the end."
    }

    public init(pattern: WordOrderPattern, tiles: [String], answer: String, accepted: [String],
                emoji: String, prefix: String? = nil) {
        self.pattern = pattern
        self.tiles = tiles
        self.answer = answer
        self.accepted = accepted
        self.emoji = emoji
        self.prefix = prefix
    }

    /// "." or "?".
    public var punctuation: String { pattern == .statement ? "." : "?" }

    /// The chosen tiles as a sentence: capital first letter and the final punctuation.
    public static func sentence(from chunks: [String], punctuation: String) -> String {
        let joined = chunks.joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst() + punctuation
    }

    public func sentence(from chunks: [String]) -> String {
        Self.sentence(from: chunks, punctuation: punctuation)
    }

    /// Right only if the tiles form one of the accepted sentences exactly.
    public func check(_ chunks: [String]) -> Verdict {
        let given = PhraseChecker.key(sentence(from: chunks))
        return accepted.contains { PhraseChecker.key($0) == given } ? .correct : .wrong
    }
}

/// Who does it: a pronoun or a name, with the verb form it takes.
struct WordOrderSubject: Sendable {
    let text: String
    let person: Person

    static let all: [WordOrderSubject] = [
        .init(text: "ich", person: .ich),
        .init(text: "du", person: .du),
        .init(text: "wir", person: .wir),
        .init(text: "ihr", person: .ihr),
        .init(text: "Laura", person: .erSieEs),
        .init(text: "Pedro", person: .erSieEs),
        .init(text: "Samira", person: .erSieEs),
        .init(text: "Tom und Anna", person: .sieSie),
    ]

    /// Questions are asked to someone, or about someone else.
    static let askable = all.filter { $0.person != .ich && $0.person != .wir }
}

/// A conjugated verb split for word order: "stehe auf" → "stehe" … "auf".
struct WordOrderVerb: Sendable {
    let finite: String
    let particle: String?

    init?(form: String) {
        let parts = form.split(separator: " ").map(String.init)
        switch parts.count {
        case 1: finite = parts[0]; particle = nil
        case 2: finite = parts[0]; particle = parts[1]
        default: return nil
        }
    }
}

public enum WordOrderQuiz {
    /// When it happens; any of them can open a statement.
    static let times = ["heute", "morgen", "am Sonntag", "am Montag", "am Wochenende", "um 8 Uhr",
                        "um halb neun", "jeden Tag", "am Abend"]
    /// Times that still fit after "wann" or "um wie viel Uhr".
    static let days = ["heute", "morgen", "am Sonntag", "am Wochenende"]
    static let questionWords = ["wann", "um wie viel Uhr"]

    /// Verbs that take almost any thing as object, used with the learner's nouns.
    static let objectVerbs: [VerbEntry] = [
        VerbEntry(infinitive: "kaufen", english: "to buy", forms: ["kaufe", "kaufst", "kauft", "kaufen", "kauft", "kaufen"]),
        VerbEntry(infinitive: "brauchen", english: "to need", forms: ["brauche", "brauchst", "braucht", "brauchen", "braucht", "brauchen"]),
        VerbEntry(infinitive: "suchen", english: "to look for", forms: ["suche", "suchst", "sucht", "suchen", "sucht", "suchen"]),
        VerbEntry(infinitive: "haben", english: "to have", forms: ["habe", "hast", "hat", "haben", "habt", "haben"], group: .irregular),
        VerbEntry(infinitive: "mitbringen", english: "to bring along",
                  forms: ["bringe mit", "bringst mit", "bringt mit", "bringen mit", "bringt mit", "bringen mit"],
                  group: .separable),
    ]

    /// The learner's verbs that work on their own: complete, plain or separable (not modal or reflexive).
    public static func canUse(verb: VerbEntry) -> Bool {
        guard verb.isComplete, [.regular, .stemChanging, .irregular, .separable].contains(verb.group) else { return false }
        let infinitive = verb.infinitive.trimmingCharacters(in: .whitespaces).lowercased()
        guard !infinitive.contains(" "), !YesNoQuiz.excludedInfinitives.contains(infinitive) else { return false }
        return Person.allCases.allSatisfy { WordOrderVerb(form: verb.form(for: $0)) != nil }
    }

    /// One exercise. `object` is an accusative phrase ("einen Drucker") or nil.
    static func exercise<R: RandomNumberGenerator>(
        pattern: WordOrderPattern, verb: VerbEntry, object: String?, emoji: String, using rng: inout R
    ) -> WordOrderExercise? {
        let subjects = pattern == .statement ? WordOrderSubject.all : WordOrderSubject.askable
        guard let subject = subjects.randomElement(using: &rng),
              let split = WordOrderVerb(form: verb.form(for: subject.person)) else { return nil }
        let tail = [object, split.particle].compactMap { $0 }

        let orders: [[String]]
        switch pattern {
        case .statement:
            let time = times.randomElement(using: &rng)!
            // Subject first or time first: both right, the verb stays second.
            orders = [[subject.text, split.finite, time] + tail,
                      [time, split.finite, subject.text] + tail]
        case .wQuestion:
            let word = questionWords.randomElement(using: &rng)!
            let day = Bool.random(using: &rng) ? days.randomElement(using: &rng) : nil
            orders = [[word, split.finite, subject.text] + [day].compactMap { $0 } + tail]
        case .yesNoQuestion:
            let time = times.randomElement(using: &rng)!
            orders = [[split.finite, subject.text, time] + tail]
        }

        let punctuation = pattern == .statement ? "." : "?"
        let accepted = orders.map { WordOrderExercise.sentence(from: $0, punctuation: punctuation) }
        let shown = orders.randomElement(using: &rng)!
        var tiles = shown
        for _ in 0..<10 where tiles == shown {
            tiles.shuffle(using: &rng)
        }
        return WordOrderExercise(pattern: pattern, tiles: tiles,
                                 answer: WordOrderExercise.sentence(from: shown, punctuation: punctuation),
                                 accepted: accepted, emoji: emoji, prefix: split.particle)
    }

    /// `count` sentences from the learner's verbs and nouns; `pattern` nil mixes them.
    /// Empty when there is nothing to build from.
    public static func make<R: RandomNumberGenerator>(
        count: Int, pattern: WordOrderPattern?, nouns: [VocabEntry], verbs: [VerbEntry], using rng: inout R
    ) -> [WordOrderExercise] {
        let nouns = nouns.filter(YesNoQuiz.canUse(noun:)).shuffled(using: &rng)
        let verbs = verbs.filter(canUse(verb:)).shuffled(using: &rng)
        guard !nouns.isEmpty || !verbs.isEmpty else { return [] }

        var result: [WordOrderExercise] = []
        var seen = Set<String>()
        var nounIndex = 0, verbIndex = 0
        for attempt in 0..<(count * 3) where result.count < count {
            let chosen = pattern ?? WordOrderPattern.allCases[attempt % WordOrderPattern.allCases.count]
            let useNoun = !nouns.isEmpty && (verbs.isEmpty || Bool.random(using: &rng))
            let exercise: WordOrderExercise?
            if useNoun {
                let noun = nouns[nounIndex % nouns.count]
                nounIndex += 1
                let object = "\(noun.article!.accusativeIndefinite) \(noun.german)"
                exercise = Self.exercise(pattern: chosen, verb: objectVerbs.randomElement(using: &rng)!,
                                         object: object, emoji: noun.emoji, using: &rng)
            } else {
                let verb = verbs[verbIndex % verbs.count]
                verbIndex += 1
                exercise = Self.exercise(pattern: chosen, verb: verb, object: nil, emoji: verb.emoji, using: &rng)
            }
            guard let exercise, seen.insert(exercise.id).inserted else { continue }
            result.append(exercise)
        }
        result.shuffle(using: &rng)
        return result
    }
}
