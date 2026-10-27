import Foundation

/// Search across words, phrases and verbs: case, punctuation and German spelling
/// (ä/ae/a, ß/ss) do not matter.
public enum VocabularySearch {
    /// True when some field contains the query; an empty query matches nothing.
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let normalized = AnswerChecker.normalize(query)
        guard !normalized.isEmpty else { return false }
        let folded = AnswerChecker.foldGerman(normalized)
        let plain = withoutUmlauts(normalized)
        return fields.contains { field in
            let text = AnswerChecker.normalize(field)
            return AnswerChecker.foldGerman(text).contains(folded) || withoutUmlauts(text).contains(plain)
        }
    }

    /// "fährt" → "fahrt", for queries typed without umlauts.
    private static func withoutUmlauts(_ text: String) -> String {
        text.replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }
}
