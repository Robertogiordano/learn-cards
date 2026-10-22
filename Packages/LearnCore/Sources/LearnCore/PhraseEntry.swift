import Foundation

public enum PhraseKind: String, Codable, CaseIterable, Hashable, Sendable {
    case question, idiom, sentence

    public var label: String {
        switch self {
        case .question: return "Domanda"
        case .idiom: return "Modo di dire"
        case .sentence: return "Frase"
        }
    }
}

/// A sentence or idiom to learn, independent of how it is stored.
public struct PhraseEntry: Codable, Hashable, Identifiable, Sendable {
    public static let defaultCategory = "Frasi utili"

    public var id: UUID
    /// The canonical German sentence, complete and correctly written.
    public var german: String
    /// Other correct German forms ("Sprechen Sie Französisch?" next to "Sprichst du Französisch?").
    public var variants: [String]
    public var english: String
    /// For question/answer pairs: the German answer to this question.
    public var response: String?
    /// Literal meaning or short explanation, mostly for idioms.
    public var note: String?
    public var kind: PhraseKind
    public var category: String
    public var emoji: String

    public init(
        id: UUID = UUID(),
        german: String,
        variants: [String] = [],
        english: String,
        response: String? = nil,
        note: String? = nil,
        kind: PhraseKind = .sentence,
        category: String = PhraseEntry.defaultCategory,
        emoji: String = "💬"
    ) {
        self.id = id
        self.german = german
        self.variants = variants
        self.english = english
        self.response = response
        self.note = note
        self.kind = kind
        self.category = category
        self.emoji = emoji
    }

    /// Every German form counted as right.
    public var accepted: [String] { [german] + variants }

    public var hasResponse: Bool { !(response ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Identity used to spot duplicates: case, punctuation and umlaut spelling do not matter.
    public var dedupeKey: String { PhraseChecker.key(german) }
}

public enum PhraseExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// English prompt, put the shuffled German words in order.
    case reorder
    /// English prompt, write the German sentence.
    case translate
    /// The answer is shown, write the question.
    case questionFromAnswer
    /// Fill the missing word.
    case cloze
    /// Hear the sentence, write it.
    case dictation
    /// English prompt, say the German sentence.
    case speak

    public var title: String {
        switch self {
        case .reorder: return "Ricomponi la frase"
        case .translate: return "Traduci e scrivi"
        case .questionFromAnswer: return "Domanda dalla risposta"
        case .cloze: return "Completa"
        case .dictation: return "Dettato"
        case .speak: return "Pronuncia"
        }
    }

    public func isApplicable(to entry: PhraseEntry) -> Bool {
        switch self {
        case .reorder: return PhraseExercises.tiles(for: entry.german).count >= 2
        case .questionFromAnswer: return entry.hasResponse
        case .cloze: return PhraseExercises.clozeIndex(in: entry.german) != nil
        case .translate, .dictation, .speak: return true
        }
    }
}
