import Foundation

/// Splits a compound noun into words of the vocabulary: Kinderzimmer → Kind + Zimmer.
public enum CompoundSplitter {
    /// Letters that may join two parts (Arbeit-s-zimmer, Kind-er-zimmer, Küche-n-tür).
    static let linkingLetters = ["", "s", "es", "n", "en", "er", "e"]
    static let minimumPartLength = 3
    static let maximumParts = 3

    /// Two or three vocabulary words that make the compound, spelled as in the vocabulary;
    /// nil when no split is found. Fewer parts win, then longer parts.
    public static func suggest(_ compound: String, vocabulary: [String]) -> [String]? {
        let target = key(compound)
        guard target.count >= minimumPartLength * 2 else { return nil }
        var words: [String: String] = [:]
        var stems: [String: String] = [:]
        for word in vocabulary {
            let full = key(word)
            guard full.count >= minimumPartLength, full != target else { continue }
            words[full] = words[full] ?? word
            // A first part can also drop a final -e (Schul-) or a verb ending (Schreib-, Wander-).
            for stem in [full] + stemsWithoutEnding(full) where stem.count >= minimumPartLength {
                stems[stem] = stems[stem] ?? word
            }
        }
        let candidates = splits(target, stems: stems, words: words, partsLeft: maximumParts).filter { $0.count >= 2 }
        return candidates.min { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count < rhs.count }
            return (lhs.map { key($0).count }.min() ?? 0) > (rhs.map { key($0).count }.min() ?? 0)
        }
    }

    private static func splits(_ rest: String, stems: [String: String], words: [String: String],
                               partsLeft: Int) -> [[String]] {
        var results: [[String]] = []
        if let word = words[rest] { results.append([word]) }
        guard partsLeft > 1 else { return results }
        var length = rest.count - minimumPartLength
        while length >= minimumPartLength {
            let prefix = String(rest.prefix(length))
            if let first = stems[prefix] {
                let after = String(rest.dropFirst(length))
                for link in linkingLetters where after.hasPrefix(link) {
                    let tail = String(after.dropFirst(link.count))
                    guard tail.count >= minimumPartLength else { continue }
                    for tailSplit in splits(tail, stems: stems, words: words, partsLeft: partsLeft - 1) {
                        results.append([first] + tailSplit)
                    }
                }
            }
            length -= 1
        }
        return results
    }

    private static func stemsWithoutEnding(_ word: String) -> [String] {
        var result: [String] = []
        if word.hasSuffix("en") { result.append(String(word.dropLast(2))) }
        if word.hasSuffix("e") || word.hasSuffix("n") { result.append(String(word.dropLast())) }
        return result
    }

    private static func key(_ text: String) -> String {
        AnswerChecker.foldGerman(AnswerChecker.normalize(text)).replacingOccurrences(of: " ", with: "")
    }
}

/// Asking the model to split a compound the vocabulary cannot explain.
public enum CompoundSplitPrompt {
    public static func system() -> String {
        """
        You split German compound nouns into the words they are made of, for a learner of German. \
        Return the parts in order, in their dictionary form, without linking letters or articles: \
        Küchentür → ["Küche", "Tür"], Schreibtisch → ["schreiben", "Tisch"], Arbeitszimmer → \
        ["Arbeit", "Zimmer"], Kinderzimmer → ["Kind", "Zimmer"]. Nouns capitalized, verbs and \
        adjectives lowercase. If the word is not a compound, return []. Answer with JSON only, \
        shaped as {"parts": [...]}.
        """
    }

    public static func userInstruction(for word: String) -> String {
        "Split: \(word)"
    }

    public static var responseSchema: [String: Any] {
        let parts: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let properties: [String: Any] = ["parts": parts]
        return ["type": "object", "properties": properties, "required": ["parts"], "additionalProperties": false]
    }

    /// Two or more cleaned parts, or [] when the model found none.
    public static func parse(_ content: String) throws -> [String] {
        guard let start = content.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = content.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        let data = Data(String(content[start...end]).utf8)
        let decoder = JSONDecoder()
        let raw: [String]
        if let wrapped = try? decoder.decode([String: [String]].self, from: data), let list = wrapped["parts"] {
            raw = list
        } else if let bare = try? decoder.decode([String].self, from: data) {
            raw = bare
        } else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        let parts = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.count >= 2 ? parts : []
    }
}
