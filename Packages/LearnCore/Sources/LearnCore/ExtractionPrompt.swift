import Foundation

/// What we ask the vision model on OpenRouter.
public enum ExtractionPrompt {
    /// The learner's existing themes are listed so the model reuses them instead of inventing synonyms.
    public static func system(existingCategories: [String]) -> String {
        let themes = existingCategories.isEmpty
            ? "The learner has no themes yet."
            : "The learner's existing themes are: \(existingCategories.joined(separator: ", "))."
        return """
        You help an English-speaking learner memorize German vocabulary. You receive a photo of a \
        page from a German exercise book or worksheet.

        Find the German words worth memorizing on the page: vocabulary lists, glossary entries and \
        the content words used in the exercises. Skip proper names, numbers, grammar instructions \
        and text that is not German. Correct obvious OCR or handwriting mistakes. Return each word once.

        For each word return:
        - german: the base form WITHOUT article. Nouns in the nominative singular, capitalized \
        (Tisch); verbs in the infinitive (gehen); adjectives in the base form (schnell). Keep fixed \
        expressions as a phrase (es tut mir leid).
        - article: "der", "die" or "das" for nouns, null for anything else. Plural-only nouns use "die".
        - plural: the nominative plural WITHOUT article (Tische), null if the word is not a noun or \
        has no plural.
        - english: 1 to 3 common English translations, most common first, verbs without "to".
        - partOfSpeech: one of noun, verb, adjective, adverb, phrase, other.
        - emoji: exactly ONE emoji giving a concrete visual association to remember the word. For \
        abstract words choose the most evocative image.
        - category: the theme of the word, written in English, 1 to 3 words, first letter \
        capitalized (for example Food, Home, Work, Travel, Family, Body, Free time). \
        \(themes) Reuse one of the existing themes, spelled exactly the same, whenever the word \
        fits it. Create a new theme only when none fits, and keep themes broad enough to group \
        several words.

        Answer with JSON only, shaped as {"words": [ ... ]}.
        """
    }

    public static let userInstruction = "Extract the German vocabulary to learn from this page."

    /// JSON schema for OpenRouter structured outputs (`response_format: json_schema`).
    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let english: [String: Any] = ["type": "array", "items": string]
        let partOfSpeech: [String: Any] = ["type": "string", "enum": PartOfSpeech.allCases.map(\.rawValue)]
        let properties: [String: Any] = [
            "german": string,
            "article": nullableString,
            "plural": nullableString,
            "english": english,
            "partOfSpeech": partOfSpeech,
            "emoji": string,
            "category": string,
        ]
        let word: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["german", "article", "plural", "english", "partOfSpeech", "emoji", "category"],
            "additionalProperties": false,
        ]
        let words: [String: Any] = ["type": "array", "items": word]
        let rootProperties: [String: Any] = ["words": words]
        return [
            "type": "object",
            "properties": rootProperties,
            "required": ["words"],
            "additionalProperties": false,
        ]
    }
}
