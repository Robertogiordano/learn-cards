import Foundation

public enum ExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// English prompt, pick the German word among four.
    case multipleChoice
    /// English prompt, type the German word.
    case typeGerman
    /// German prompt, type the English word.
    case typeEnglish
    /// English prompt, say the German word.
    case speakGerman
}

public struct Exercise: Identifiable, Sendable {
    public let id = UUID()
    public let kind: ExerciseKind
    public let entry: VocabEntry
    public let level: StudyLevel
    /// Multiple-choice options; empty for the other kinds.
    public let options: [String]
    public let correctIndex: Int?

    public init(kind: ExerciseKind, entry: VocabEntry, level: StudyLevel, options: [String] = [], correctIndex: Int? = nil) {
        self.kind = kind
        self.entry = entry
        self.level = level
        self.options = options
        self.correctIndex = correctIndex
    }

    public var prompt: String {
        kind == .typeEnglish ? entry.germanDisplay(level: level) : entry.englishDisplay
    }

    public var expectedAnswer: String {
        kind == .typeEnglish ? entry.englishDisplay : entry.germanDisplay(level: level)
    }

    public var requiresArticle: Bool { kind != .typeEnglish && level.requiresArticle(for: entry) }

    public var requiresPlural: Bool { kind != .typeEnglish && level.requiresPlural(for: entry) }
}

public enum ExerciseBuilder {
    public static func make<R: RandomNumberGenerator>(
        kind: ExerciseKind,
        entry: VocabEntry,
        pool: [VocabEntry],
        level: StudyLevel,
        using rng: inout R
    ) -> Exercise {
        guard kind == .multipleChoice else {
            return Exercise(kind: kind, entry: entry, level: level)
        }

        let correct = entry.germanDisplay(level: level)
        var distractors: [String] = []
        func add(_ option: String) {
            let key = AnswerChecker.normalize(option)
            guard key != AnswerChecker.normalize(correct),
                  !distractors.contains(where: { AnswerChecker.normalize($0) == key }) else { return }
            distractors.append(option)
        }

        // At levels 2-3 one option tests the grammar of the very same word.
        if level.requiresArticle(for: entry), let article = entry.article,
           let other = Article.allCases.filter({ $0 != article }).randomElement(using: &rng) {
            var variant = entry
            variant.article = other
            add(variant.germanDisplay(level: level))
        }
        if level.requiresPlural(for: entry), let plural = entry.plural,
           let fake = plausiblePlurals(for: entry.german, excluding: plural).randomElement(using: &rng) {
            var variant = entry
            variant.plural = fake
            add(variant.germanDisplay(level: level))
        }

        let others = pool
            .filter { $0.id != entry.id && $0.dedupeKey != entry.dedupeKey }
            .shuffled(using: &rng)
        let samePartOfSpeech = others.filter { $0.partOfSpeech == entry.partOfSpeech }
        let rest = others.filter { $0.partOfSpeech != entry.partOfSpeech }
        for other in samePartOfSpeech + rest where distractors.count < 3 {
            add(other.germanDisplay(level: level))
        }

        // Small vocabularies: pad with the remaining article variants.
        if distractors.count < 3, level.requiresArticle(for: entry), let article = entry.article {
            for other in Article.allCases where other != article {
                var variant = entry
                variant.article = other
                add(variant.germanDisplay(level: level))
            }
        }

        var options = Array(distractors.prefix(3)) + [correct]
        guard options.count >= 2 else {
            // Not enough material for a real choice.
            return Exercise(kind: .typeGerman, entry: entry, level: level)
        }
        options.shuffle(using: &rng)
        return Exercise(kind: kind, entry: entry, level: level, options: options, correctIndex: options.firstIndex(of: correct))
    }

    public static func make(kind: ExerciseKind, entry: VocabEntry, pool: [VocabEntry], level: StudyLevel) -> Exercise {
        var rng = SystemRandomNumberGenerator()
        return make(kind: kind, entry: entry, pool: pool, level: level, using: &rng)
    }

    /// Wrong but believable plurals built from the common German endings.
    public static func plausiblePlurals(for word: String, excluding actual: String) -> [String] {
        let umlauted = addUmlaut(to: word)
        var candidates = [word + "e", word + "en", word + "n", word + "er", word + "s", word]
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
