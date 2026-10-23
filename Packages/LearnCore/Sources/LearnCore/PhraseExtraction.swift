import Foundation

/// What we ask the vision model for phrases (sentences, idioms, question/answer pairs).
public enum PhraseExtractionPrompt {
    public static func system(existingCategories: [String]) -> String {
        let categories = existingCategories.isEmpty
            ? "The learner has no phrase categories yet."
            : "The learner's existing phrase categories are: \(existingCategories.joined(separator: ", "))."
        return """
        You help an English-speaking learner memorize German sentences and idioms. You receive a \
        photo of a page from a German course: phrase lists, idioms, dialogues or exercises.

        Find the German sentences worth memorizing. Correct obvious OCR or handwriting mistakes and \
        write every sentence completely and correctly, with its final punctuation.

        Exercises with gaps must be solved: if the page asks to find the question for given answers \
        (for example "Wie heißt die Frage?" followed by "Nein, ich spreche nur Englisch und Deutsch."), \
        write the missing question ("Sprichst du Französisch?") as the phrase and the given answer as \
        its response. Do the same, in reverse, when answers are missing. Prefer the informal "du" \
        form unless the page uses "Sie".

        For each phrase return:
        - german: the complete German sentence.
        - variants: 0 to 3 other German sentences that are also correct answers with the same \
        meaning (e.g. the "Sie" form, another natural word order). No near-duplicates.
        - english: a natural English translation.
        - response: for question/answer pairs, the German answer; null otherwise.
        - note: for idioms, the literal meaning or a short explanation in English; null otherwise.
        - kind: "question", "idiom" or "sentence".
        - category: a short category written in English, 1 to 3 words, first letter capitalized \
        (for example Personal questions, Idioms, At the restaurant, Free time). \(categories) \
        Reuse an existing category, spelled exactly the same, whenever the phrase fits it.
        - emoji: exactly ONE emoji that evokes the sentence.

        Each sentence once. Answer with JSON only, shaped as {"phrases": [ ... ]}.
        """
    }

    public static let userInstruction = "Extract the German phrases to learn from this page, solving any gap exercise."

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let variants: [String: Any] = ["type": "array", "items": string]
        let kind: [String: Any] = ["type": "string", "enum": PhraseKind.allCases.map(\.rawValue)]
        let properties: [String: Any] = [
            "german": string,
            "variants": variants,
            "english": string,
            "response": nullableString,
            "note": nullableString,
            "kind": kind,
            "category": string,
            "emoji": string,
        ]
        let phrase: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["german", "variants", "english", "response", "note", "kind", "category", "emoji"],
            "additionalProperties": false,
        ]
        let phrases: [String: Any] = ["type": "array", "items": phrase]
        let rootProperties: [String: Any] = ["phrases": phrases]
        return [
            "type": "object",
            "properties": rootProperties,
            "required": ["phrases"],
            "additionalProperties": false,
        ]
    }
}

/// Turns the model's reply into clean phrases, tolerating the usual LLM quirks.
public enum PhraseExtractionParser {
    public static func parse(_ content: String, existingCategories: [String] = []) throws -> [PhraseEntry] {
        guard let start = content.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = content.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        let data = Data(String(content[start...end]).utf8)
        let decoder = JSONDecoder()
        let raws: [RawPhrase]
        if let wrapped = try? decoder.decode(RawPhrases.self, from: data) {
            raws = wrapped.phrases
        } else if let bare = try? decoder.decode([RawPhrase].self, from: data) {
            raws = bare
        } else {
            throw ExtractionParser.ParseError.invalidJSON
        }

        let known = Dictionary(existingCategories.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return raws
            .compactMap { entry(from: $0, knownCategories: known) }
            .filter { seen.insert($0.dedupeKey).inserted }
    }

    private static func entry(from raw: RawPhrase, knownCategories: [String: String]) -> PhraseEntry? {
        let german = clean(raw.german)
        let english = clean(raw.english)
        guard !german.isEmpty, !english.isEmpty else { return nil }

        var variants: [String] = []
        var keys: Set<String> = [PhraseChecker.key(german)]
        for variant in raw.variants.map({ clean($0) }) where !variant.isEmpty && keys.insert(PhraseChecker.key(variant)).inserted {
            variants.append(variant)
        }

        let response = clean(raw.response)
        let note = clean(raw.note)
        var category = clean(raw.category)
        if let first = category.first {
            category = knownCategories[category.lowercased()] ?? first.uppercased() + category.dropFirst()
        } else {
            category = PhraseEntry.defaultCategory
        }

        return PhraseEntry(
            german: german,
            variants: Array(variants.prefix(3)),
            english: english,
            response: response.isEmpty ? nil : response,
            note: note.isEmpty ? nil : note,
            kind: PhraseKind(rawValue: clean(raw.kind).lowercased()) ?? .sentence,
            category: category,
            emoji: clean(raw.emoji).first.map(String.init) ?? "💬"
        )
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RawPhrases: Decodable {
    let phrases: [RawPhrase]
}

private struct RawPhrase: Decodable {
    let german: String?
    let variants: [String]
    let english: String?
    let response: String?
    let note: String?
    let kind: String?
    let category: String?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case german, variants, english, response, note, kind, category, emoji
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        german = string(.german)
        english = string(.english)
        response = string(.response)
        note = string(.note)
        kind = string(.kind)
        category = string(.category)
        emoji = string(.emoji)
        if let list = try? container.decode([String].self, forKey: .variants) {
            variants = list
        } else if let single = string(.variants) {
            variants = [single]
        } else {
            variants = []
        }
    }
}
