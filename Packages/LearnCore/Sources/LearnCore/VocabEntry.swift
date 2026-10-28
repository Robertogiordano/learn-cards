import Foundation

public enum Article: String, Codable, CaseIterable, Hashable, Sendable {
    case der, die, das

    /// The matching indefinite article in the nominative.
    public var indefinite: String {
        self == .die ? "eine" : "ein"
    }

    public var genderLabel: String {
        switch self {
        case .der: return "maskulin"
        case .die: return "feminin"
        case .das: return "neutral"
        }
    }
}

public enum PartOfSpeech: String, Codable, CaseIterable, Hashable, Sendable {
    case noun, verb, adjective, adverb, phrase, other

    public var label: String {
        switch self {
        case .noun: return "Noun"
        case .verb: return "Verb"
        case .adjective: return "Adjective"
        case .adverb: return "Adverb"
        case .phrase: return "Expression"
        case .other: return "Other"
        }
    }
}

/// A single vocabulary item, independent of how it is stored.
public struct VocabEntry: Codable, Hashable, Identifiable, Sendable {
    public static let defaultCategory = "Misc"
    /// The default theme before the app switched to English, renamed on first launch.
    public static let legacyDefaultCategory = "Varie"
    /// Theme of compound nouns (Küche + Tür → Küchentür).
    public static let compoundCategory = "Compound words"

    public var id: UUID
    /// Base form without article: singular noun, infinitive verb, ...
    public var german: String
    public var article: Article?
    /// Plural form without article ("Tische"); nil when the word has no plural.
    public var plural: String?
    /// Accepted English translations, most common first.
    public var english: [String]
    public var partOfSpeech: PartOfSpeech
    public var emoji: String
    /// Theme used to group words and to pick what to study (Food, Home, ...).
    public var category: String
    /// For compound nouns, the base words they are made of ("Küche", "Tür"); empty otherwise.
    public var parts: [String]

    public init(
        id: UUID = UUID(),
        german: String,
        article: Article? = nil,
        plural: String? = nil,
        english: [String],
        partOfSpeech: PartOfSpeech = .other,
        emoji: String = "📝",
        category: String = VocabEntry.defaultCategory,
        parts: [String] = []
    ) {
        self.id = id
        self.german = german
        self.article = article
        self.plural = plural
        self.english = english
        self.partOfSpeech = partOfSpeech
        self.emoji = emoji
        self.category = category
        self.parts = parts
    }

    enum CodingKeys: String, CodingKey {
        case id, german, article, plural, english, partOfSpeech, emoji, category, parts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        german = try container.decode(String.self, forKey: .german)
        article = try container.decodeIfPresent(Article.self, forKey: .article)
        plural = try container.decodeIfPresent(String.self, forKey: .plural)
        english = try container.decode([String].self, forKey: .english)
        partOfSpeech = try container.decode(PartOfSpeech.self, forKey: .partOfSpeech)
        emoji = try container.decode(String.self, forKey: .emoji)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? Self.defaultCategory
        parts = try container.decodeIfPresent([String].self, forKey: .parts) ?? []
    }

    public var hasArticle: Bool { article != nil }

    /// Made of two or more words.
    public var isCompound: Bool { parts.count >= 2 }

    /// "Küche + Tür".
    public var partsDisplay: String { parts.joined(separator: " + ") }

    public var hasPlural: Bool {
        !(plural ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "der Tisch", or the bare word when it has no article.
    public var withArticle: String {
        article.map { "\($0.rawValue) \(german)" } ?? german
    }

    /// "ein Tisch"; nil for words without article.
    public var withIndefiniteArticle: String? {
        article.map { "\($0.indefinite) \(german)" }
    }

    /// "die Tische"; nil when there is no plural.
    public var pluralWithArticle: String? {
        hasPlural ? plural.map { "die \($0)" } : nil
    }

    /// Article, word and plural: everything we know.
    public var fullGerman: String {
        pluralWithArticle.map { "\(withArticle), \($0)" } ?? withArticle
    }

    public var englishDisplay: String { english.joined(separator: ", ") }

    /// Identity used to spot duplicates across imports ("der See" and "die See" are different words).
    public var dedupeKey: String { Self.dedupeKey(german: german, article: article) }

    public static func dedupeKey(german: String, article: Article?) -> String {
        let word = AnswerChecker.foldGerman(AnswerChecker.normalize(german))
        return "\(article?.rawValue ?? "-")|\(word)"
    }
}
