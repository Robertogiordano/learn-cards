import Foundation

public enum Article: String, Codable, CaseIterable, Hashable, Sendable {
    case der, die, das
}

public enum PartOfSpeech: String, Codable, CaseIterable, Hashable, Sendable {
    case noun, verb, adjective, adverb, phrase, other

    public var label: String {
        switch self {
        case .noun: return "Sostantivo"
        case .verb: return "Verbo"
        case .adjective: return "Aggettivo"
        case .adverb: return "Avverbio"
        case .phrase: return "Espressione"
        case .other: return "Altro"
        }
    }
}

/// A single vocabulary item, independent of how it is stored.
public struct VocabEntry: Codable, Hashable, Identifiable, Sendable {
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

    public init(
        id: UUID = UUID(),
        german: String,
        article: Article? = nil,
        plural: String? = nil,
        english: [String],
        partOfSpeech: PartOfSpeech = .other,
        emoji: String = "📝"
    ) {
        self.id = id
        self.german = german
        self.article = article
        self.plural = plural
        self.english = english
        self.partOfSpeech = partOfSpeech
        self.emoji = emoji
    }

    public var hasArticle: Bool { article != nil }

    public var hasPlural: Bool {
        !(plural ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The German form a learner is asked for at the given level.
    public func germanDisplay(level: StudyLevel) -> String {
        var text = german
        if level.requiresArticle(for: self), let article {
            text = "\(article.rawValue) \(german)"
        }
        if level.requiresPlural(for: self), let plural {
            text += ", die \(plural)"
        }
        return text
    }

    /// Article, word and plural: everything we know.
    public var fullGerman: String { germanDisplay(level: .plural) }

    public var englishDisplay: String { english.joined(separator: ", ") }

    /// Identity used to spot duplicates across imports ("der See" and "die See" are different words).
    public var dedupeKey: String { Self.dedupeKey(german: german, article: article) }

    public static func dedupeKey(german: String, article: Article?) -> String {
        let word = AnswerChecker.foldGerman(AnswerChecker.normalize(german))
        return "\(article?.rawValue ?? "-")|\(word)"
    }
}
