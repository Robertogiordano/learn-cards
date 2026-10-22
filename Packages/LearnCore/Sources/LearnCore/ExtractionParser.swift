import Foundation

/// Turns the model's reply into clean entries, tolerating the usual LLM quirks
/// (code fences, a bare array, "der Tisch" in the word field, a string instead of a list).
public enum ExtractionParser {
    public enum ParseError: LocalizedError, Equatable {
        case noJSON
        case invalidJSON

        public var errorDescription: String? {
            switch self {
            case .noJSON: return "La risposta del modello non contiene un elenco di parole."
            case .invalidJSON: return "La risposta del modello non è leggibile."
            }
        }
    }

    /// `existingCategories` lets "cibo" from the model map onto the learner's "Cibo".
    public static func parse(_ content: String, existingCategories: [String] = []) throws -> [VocabEntry] {
        let data = Data(try jsonSlice(of: content).utf8)
        let decoder = JSONDecoder()
        let raws: [RawWord]
        if let wrapped = try? decoder.decode(RawExtraction.self, from: data) {
            raws = wrapped.words
        } else if let bare = try? decoder.decode([RawWord].self, from: data) {
            raws = bare
        } else {
            throw ParseError.invalidJSON
        }

        let knownCategories = Dictionary(
            existingCategories.map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen = Set<String>()
        return raws
            .compactMap { entry(from: $0, knownCategories: knownCategories) }
            .filter { seen.insert($0.dedupeKey).inserted }
    }

    private static func jsonSlice(of content: String) throws -> String {
        guard let start = content.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = content.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end else {
            throw ParseError.noJSON
        }
        return String(content[start...end])
    }

    private static func entry(from raw: RawWord, knownCategories: [String: String]) -> VocabEntry? {
        var german = clean(raw.german)
        var article = Article(rawValue: clean(raw.article).lowercased())

        let parts = german.split(separator: " ", maxSplits: 1)
        if parts.count == 2, let leading = Article(rawValue: parts[0].lowercased()) {
            german = String(parts[1])
            article = article ?? leading
        }
        guard !german.isEmpty else { return nil }

        var partOfSpeech = PartOfSpeech(rawValue: clean(raw.partOfSpeech).lowercased()) ?? .other
        if article != nil { partOfSpeech = .noun }
        if partOfSpeech == .noun, let first = german.first {
            german = first.uppercased() + german.dropFirst()
        }

        var plural: String? = clean(raw.plural)
        if let value = plural, value.lowercased().hasPrefix("die ") {
            plural = String(value.dropFirst(4))
        }
        if let value = plural, ["", "-", "–", "—", "null", "none", "n/a"].contains(value.lowercased()) {
            plural = nil
        }
        if partOfSpeech != .noun { plural = nil }

        var english: [String] = []
        for translation in raw.english.map({ clean($0) }) where !translation.isEmpty && !english.contains(translation) {
            english.append(translation)
        }
        guard !english.isEmpty else { return nil }

        let emoji = clean(raw.emoji).first.map(String.init) ?? "📝"

        var category = clean(raw.category)
        if let first = category.first {
            category = knownCategories[category.lowercased()] ?? first.uppercased() + category.dropFirst()
        } else {
            category = VocabEntry.defaultCategory
        }

        return VocabEntry(
            german: german,
            article: article,
            plural: plural,
            english: english,
            partOfSpeech: partOfSpeech,
            emoji: emoji,
            category: category
        )
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RawExtraction: Decodable {
    let words: [RawWord]
}

private struct RawWord: Decodable {
    let german: String?
    let article: String?
    let plural: String?
    let english: [String]
    let partOfSpeech: String?
    let emoji: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case german, article, plural, english, partOfSpeech, emoji, category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        german = (try? container.decodeIfPresent(String.self, forKey: .german)) ?? nil
        article = (try? container.decodeIfPresent(String.self, forKey: .article)) ?? nil
        plural = (try? container.decodeIfPresent(String.self, forKey: .plural)) ?? nil
        partOfSpeech = (try? container.decodeIfPresent(String.self, forKey: .partOfSpeech)) ?? nil
        emoji = (try? container.decodeIfPresent(String.self, forKey: .emoji)) ?? nil
        category = (try? container.decodeIfPresent(String.self, forKey: .category)) ?? nil
        if let list = try? container.decode([String].self, forKey: .english) {
            english = list
        } else if let single = try? container.decode(String.self, forKey: .english) {
            english = single.split(whereSeparator: { $0 == "," || $0 == "/" || $0 == ";" }).map(String.init)
        } else {
            english = []
        }
    }
}
