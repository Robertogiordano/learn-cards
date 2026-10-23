import Foundation

/// What is being trained. Each area has its own spaced-repetition schedule per word.
public enum StudyArea: String, CaseIterable, Codable, Hashable, Sendable {
    /// English ↔ German.
    case translation
    /// Definite and indefinite article of a noun (der Tisch / ein Tisch).
    case article
    /// Plural of a noun (der Tisch → die Tische).
    case plural

    public var title: String {
        switch self {
        case .translation: return "Translation"
        case .article: return "Article"
        case .plural: return "Plural"
        }
    }

    public var explanation: String {
        switch self {
        case .translation: return "From English to German (and back): table → Tisch."
        case .article: return "Definite and indefinite article: Tisch → der Tisch / ein Tisch."
        case .plural: return "The plural: der Tisch → die Tische."
        }
    }

    /// Articles and plurals only make sense for nouns that have them.
    public func isApplicable(to entry: VocabEntry) -> Bool {
        switch self {
        case .translation: return true
        case .article: return entry.hasArticle
        case .plural: return entry.hasArticle && entry.hasPlural
        }
    }

    /// Exercise kinds available in this area.
    public var kinds: [ExerciseKind] {
        switch self {
        case .translation: return [.multipleChoice, .typeGerman, .typeEnglish, .speakGerman]
        case .article, .plural: return [.multipleChoice, .typeGerman, .speakGerman]
        }
    }
}
