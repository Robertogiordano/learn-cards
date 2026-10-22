import Foundation

/// Global difficulty: how much of the German form must be produced.
public enum StudyLevel: Int, CaseIterable, Codable, Hashable, Sendable {
    /// Only the translation.
    case translation = 1
    /// Article + word.
    case article = 2
    /// Article + word + plural.
    case plural = 3

    public var shortTitle: String {
        switch self {
        case .translation: return "Traduzione"
        case .article: return "Articolo"
        case .plural: return "Plurale"
        }
    }

    public var explanation: String {
        switch self {
        case .translation: return "Livello 1: basta la parola (Tisch)."
        case .article: return "Livello 2: serve l'articolo (der Tisch)."
        case .plural: return "Livello 3: articolo e plurale (der Tisch, die Tische)."
        }
    }

    /// Words without an article (verbs, adjectives, ...) fall back to the plain word.
    public func requiresArticle(for entry: VocabEntry) -> Bool {
        rawValue >= StudyLevel.article.rawValue && entry.hasArticle
    }

    public func requiresPlural(for entry: VocabEntry) -> Bool {
        self == .plural && entry.hasPlural
    }
}
