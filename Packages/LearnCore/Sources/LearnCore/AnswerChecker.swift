import Foundation

public enum Verdict: Int, Codable, Hashable, Sendable, Comparable {
    case wrong = 0
    /// Right word with a small typo or a missing umlaut.
    case almost = 1
    case correct = 2

    public static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum AnswerChecker {
    private static let punctuation = Set(".,;:!?\"'«»„“”‚‘’()[]")

    /// Lowercased, punctuation removed, whitespace collapsed.
    public static func normalize(_ text: String) -> String {
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased()
        let cleaned = String(lowered.map { punctuation.contains($0) ? " " : $0 })
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// ä → ae, ö → oe, ü → ue, ß → ss, so answers typed on an English keyboard count.
    public static func foldGerman(_ text: String) -> String {
        text.replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    private static func stripUmlauts(_ text: String) -> String {
        text.replacingOccurrences(of: "ä", with: "a")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ß", with: "ss")
    }

    public static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// One edit away, on words long enough for that to be a typo rather than another word.
    private static func isTypo(_ given: String, _ expected: String) -> Bool {
        max(given.count, expected.count) >= 4 && levenshtein(given, expected) <= 1
    }

    // MARK: - Single words

    public static func compareGerman(_ given: String, _ expected: String) -> Verdict {
        let g = normalize(given), e = normalize(expected)
        guard !g.isEmpty else { return .wrong }
        if g == e || foldGerman(g) == foldGerman(e) { return .correct }
        if stripUmlauts(g) == stripUmlauts(e) { return .almost }
        if isTypo(foldGerman(g), foldGerman(e)) { return .almost }
        return .wrong
    }

    /// Accepts any of the translations; "to go" matches "go", "the table" matches "table".
    public static func compareEnglish(_ given: String, accepted: [String]) -> Verdict {
        let g = stripEnglishFillers(normalize(given))
        guard !g.isEmpty else { return .wrong }
        let candidates = accepted
            .flatMap { $0.split(whereSeparator: { $0 == "/" || $0 == ";" }) }
            .map { stripEnglishFillers(normalize(String($0))) }
            .filter { !$0.isEmpty }
        var best = Verdict.wrong
        for candidate in candidates {
            if g == candidate { return .correct }
            if isTypo(g, candidate) { best = max(best, .almost) }
        }
        return best
    }

    private static func stripEnglishFillers(_ text: String) -> String {
        for prefix in ["to ", "the ", "a ", "an "] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }

    // MARK: - Full answers per area

    /// Translation into German: the bare word; a leading article is tolerated, never required.
    public static func checkTranslation(_ given: String, entry: VocabEntry) -> Verdict {
        compareGerman(droppingArticle(normalize(given), for: entry), entry.german)
    }

    /// Both articles must be exact; "der Tisch" typed in the field counts as "der".
    public static func checkArticle(definite: String, indefinite: String, entry: VocabEntry) -> Verdict {
        guard let article = entry.article else { return .wrong }
        let givenDefinite = firstWord(of: definite)
        let givenIndefinite = firstWord(of: indefinite)
        return givenDefinite == article.rawValue && givenIndefinite == article.indefinite ? .correct : .wrong
    }

    /// The plural, with or without the leading "die"; typos and missing umlauts count as almost.
    public static func checkPlural(_ given: String, entry: VocabEntry) -> Verdict {
        guard let plural = entry.plural else { return .wrong }
        return compareGerman(dropLeadingDie(given), plural)
    }

    /// Checks the speech recognizer's candidate transcriptions; the best one wins.
    public static func checkSpoken(_ transcripts: [String], entry: VocabEntry, area: StudyArea) -> Verdict {
        var best = Verdict.wrong
        for transcript in transcripts {
            let verdict: Verdict
            switch area {
            case .translation:
                verdict = compareWords(droppingArticle(normalize(transcript), for: entry), entry.german)
            case .article:
                verdict = checkSpokenArticles(normalize(transcript), entry: entry)
            case .plural:
                guard let plural = entry.plural else { return .wrong }
                verdict = compareWords(dropLeadingDie(transcript), plural)
            }
            best = max(best, verdict)
            if best == .correct { break }
        }
        return best
    }

    /// "der Tisch, ein Tisch": the first word must be the definite article and the
    /// next ein-word the indefinite one. The noun itself was in the prompt, so it is not graded.
    private static func checkSpokenArticles(_ transcript: String, entry: VocabEntry) -> Verdict {
        guard let article = entry.article else { return .wrong }
        let tokens = transcript.split(separator: " ").map(String.init)
        guard let first = tokens.first, first == article.rawValue else { return .wrong }
        let einForms: Set<String> = ["ein", "eine", "einen", "einem", "einer", "eines"]
        guard let indefinite = tokens.dropFirst().first(where: { einForms.contains($0) }) else { return .wrong }
        return indefinite == article.indefinite ? .correct : .wrong
    }

    /// Word-by-word comparison, falling back to the joined text because the
    /// recognizer may split or merge compound words ("Haus Tür" for "Haustür").
    private static func compareWords(_ given: String, _ expected: String) -> Verdict {
        let tokens = normalize(given).split(separator: " ").map(String.init)
        let parts = normalize(expected).split(separator: " ").map(String.init)
        if tokens.count == parts.count {
            return zip(tokens, parts).map { pair in compareGerman(pair.0, pair.1) }.min() ?? .wrong
        }
        return compareGerman(tokens.joined(), parts.joined())
    }

    private static func droppingArticle(_ normalized: String, for entry: VocabEntry) -> String {
        guard entry.hasArticle else { return normalized }
        let tokens = normalized.split(separator: " ")
        if tokens.count > 1, Article(rawValue: String(tokens[0])) != nil {
            return tokens.dropFirst().joined(separator: " ")
        }
        return normalized
    }

    private static func firstWord(of text: String) -> String {
        normalize(text).split(separator: " ").first.map(String.init) ?? ""
    }

    private static func dropLeadingDie(_ text: String) -> String {
        let normalized = normalize(text)
        return normalized.hasPrefix("die ") ? String(normalized.dropFirst(4)) : normalized
    }
}
