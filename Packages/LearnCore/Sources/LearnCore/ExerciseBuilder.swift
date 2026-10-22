import Foundation

public enum ExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Pick the answer among a few options.
    case multipleChoice
    /// Type the German answer.
    case typeGerman
    /// German prompt, type the English word (translation only).
    case typeEnglish
    /// Say the German answer.
    case speakGerman
}

public struct Exercise: Identifiable, Sendable {
    public let id: UUID
    public let area: StudyArea
    public let kind: ExerciseKind
    public let entry: VocabEntry
    /// Multiple-choice options; empty for the other kinds.
    public let options: [String]
    /// Optional second line per option (the gender for article questions).
    public let optionDetails: [String]
    public let correctIndex: Int?

    public init(
        id: UUID = UUID(),
        area: StudyArea,
        kind: ExerciseKind,
        entry: VocabEntry,
        options: [String] = [],
        optionDetails: [String] = [],
        correctIndex: Int? = nil
    ) {
        self.id = id
        self.area = area
        self.kind = kind
        self.entry = entry
        self.options = options
        self.optionDetails = optionDetails
        self.correctIndex = correctIndex
    }

    /// The same exercise after the word was corrected (e.g. a wrong gender from the extraction).
    /// Keeps the id so the screen is not reset; article options are in fixed gender order,
    /// so only the right index moves.
    public func withEntry(_ corrected: VocabEntry) -> Exercise {
        var index = correctIndex
        if area == .article, kind == .multipleChoice, let article = corrected.article {
            index = Article.allCases.firstIndex(of: article)
        }
        return Exercise(id: id, area: area, kind: kind, entry: corrected, options: options,
                        optionDetails: optionDetails, correctIndex: index)
    }

    public var prompt: String {
        switch area {
        case .translation: return kind == .typeEnglish ? entry.german : entry.englishDisplay
        case .article: return entry.german
        case .plural: return entry.withArticle
        }
    }

    public var expectedAnswer: String {
        switch area {
        case .translation:
            return kind == .typeEnglish ? entry.englishDisplay : entry.german
        case .article:
            return [entry.withArticle, entry.withIndefiniteArticle].compactMap { $0 }.joined(separator: " / ")
        case .plural:
            return entry.pluralWithArticle ?? entry.german
        }
    }
}

public enum ExerciseBuilder {
    public static func make<R: RandomNumberGenerator>(
        area: StudyArea,
        kind: ExerciseKind,
        entry: VocabEntry,
        pool: [VocabEntry],
        using rng: inout R
    ) -> Exercise {
        guard kind == .multipleChoice else {
            return Exercise(area: area, kind: kind, entry: entry)
        }
        switch area {
        case .translation:
            return translationChoice(entry: entry, pool: pool, using: &rng)
        case .article:
            return articleChoice(entry: entry)
        case .plural:
            return pluralChoice(entry: entry, using: &rng)
        }
    }

    public static func make(area: StudyArea, kind: ExerciseKind, entry: VocabEntry, pool: [VocabEntry]) -> Exercise {
        var rng = SystemRandomNumberGenerator()
        return make(area: area, kind: kind, entry: entry, pool: pool, using: &rng)
    }

    // MARK: - Multiple choice per area

    private static func translationChoice<R: RandomNumberGenerator>(entry: VocabEntry, pool: [VocabEntry], using rng: inout R) -> Exercise {
        let correct = entry.german
        var distractors: [String] = []
        let others = pool
            .filter { $0.id != entry.id && $0.dedupeKey != entry.dedupeKey }
            .shuffled(using: &rng)
        let samePartOfSpeech = others.filter { $0.partOfSpeech == entry.partOfSpeech }
        let rest = others.filter { $0.partOfSpeech != entry.partOfSpeech }
        for other in samePartOfSpeech + rest where distractors.count < 3 {
            let key = AnswerChecker.normalize(other.german)
            if key != AnswerChecker.normalize(correct),
               !distractors.contains(where: { AnswerChecker.normalize($0) == key }) {
                distractors.append(other.german)
            }
        }
        guard !distractors.isEmpty else {
            // Not enough words for a real choice.
            return Exercise(area: .translation, kind: .typeGerman, entry: entry)
        }
        var options = distractors + [correct]
        options.shuffle(using: &rng)
        return Exercise(area: .translation, kind: .multipleChoice, entry: entry,
                        options: options, correctIndex: options.firstIndex(of: correct))
    }

    /// Always the three genders in a fixed order, like a grammar table.
    private static func articleChoice(entry: VocabEntry) -> Exercise {
        guard let article = entry.article else {
            return Exercise(area: .article, kind: .typeGerman, entry: entry)
        }
        let options = Article.allCases.map { "\($0.rawValue) \(entry.german) / \($0.indefinite) \(entry.german)" }
        return Exercise(
            area: .article,
            kind: .multipleChoice,
            entry: entry,
            options: options,
            optionDetails: Article.allCases.map(\.genderLabel),
            correctIndex: Article.allCases.firstIndex(of: article)
        )
    }

    private static func pluralChoice<R: RandomNumberGenerator>(entry: VocabEntry, using rng: inout R) -> Exercise {
        guard let plural = entry.plural, entry.hasPlural else {
            return Exercise(area: .plural, kind: .typeGerman, entry: entry)
        }
        let fakes = plausiblePlurals(for: entry.german, excluding: plural).shuffled(using: &rng).prefix(3)
        let correct = "die \(plural)"
        var options = fakes.map { "die \($0)" } + [correct]
        options.shuffle(using: &rng)
        return Exercise(area: .plural, kind: .multipleChoice, entry: entry,
                        options: options, correctIndex: options.firstIndex(of: correct))
    }

    // MARK: - Fake plurals

    /// Wrong but believable plurals built from the common German endings.
    public static func plausiblePlurals(for word: String, excluding actual: String) -> [String] {
        let umlauted = addUmlaut(to: word)
        let stem = word.hasSuffix("e") ? String(word.dropLast()) : word
        var candidates = [word + "e", word + "en", word + "n", word + "er", word + "s", word, stem + "en"]
        if umlauted != word {
            candidates += [umlauted, umlauted + "e", umlauted + "er"]
        }
        var seen = Set<String>()
        let actualKey = AnswerChecker.normalize(actual)
        return candidates.filter { candidate in
            let key = AnswerChecker.normalize(candidate)
            return key != actualKey && seen.insert(key).inserted
        }
    }

    /// Umlauts the last a/o/u (or "au"), as in Apfel → Äpfel, Haus → Häus.
    static func addUmlaut(to word: String) -> String {
        var characters = Array(word)
        for index in characters.indices.reversed() {
            let replacement: Character?
            switch characters[index] {
            case "a": replacement = "ä"
            case "o": replacement = "ö"
            case "u":
                if index > 0, characters[index - 1] == "a" {
                    characters[index - 1] = "ä"
                    return String(characters)
                }
                replacement = "ü"
            case "A": replacement = "Ä"
            case "O": replacement = "Ö"
            case "U": replacement = "Ü"
            default: replacement = nil
            }
            if let replacement {
                characters[index] = replacement
                return String(characters)
            }
        }
        return word
    }
}
