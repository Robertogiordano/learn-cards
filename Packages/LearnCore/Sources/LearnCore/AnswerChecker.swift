import Foundation

public enum Verdict: Int, Codable, Hashable, Sendable, Comparable {
    case wrong = 0
    /// Right word with a small typo or a missing umlaut.
    case almost = 1
    case correct = 2

    public static func < (lhs: Verdict, rhs: Verdict) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What the learner typed in a German answer.
public struct GermanAnswer: Hashable, Sendable {
    public var article: Article?
    public var word: String
    public var plural: String

    public init(article: Article? = nil, word: String, plural: String = "") {
        self.article = article
        self.word = word
        self.plural = plural
    }
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

    // MARK: - Full answers

    public static func checkGerman(_ answer: GermanAnswer, entry: VocabEntry, level: StudyLevel) -> Verdict {
        var word = normalize(answer.word)
        var article = answer.article
        // Accept "der Tisch" typed straight into the word field.
        let tokens = word.split(separator: " ")
        if entry.hasArticle, tokens.count > 1, let typed = Article(rawValue: String(tokens[0])) {
            word = tokens.dropFirst().joined(separator: " ")
            if article == nil { article = typed }
        }

        var verdict = compareGerman(word, entry.german)
        if level.requiresArticle(for: entry), article != entry.article {
            verdict = .wrong
        }
        if level.requiresPlural(for: entry), let plural = entry.plural {
            verdict = min(verdict, compareGerman(dropLeadingDie(answer.plural), plural))
        }
        return verdict
    }

    private struct SpokenPart {
        let text: String
        let isArticle: Bool
    }

    /// Checks the speech recognizer's candidate transcriptions; the best one wins.
    public static func checkSpoken(_ transcripts: [String], entry: VocabEntry, level: StudyLevel) -> Verdict {
        func words(_ text: String) -> [SpokenPart] {
            normalize(text).split(separator: " ").map { SpokenPart(text: String($0), isArticle: false) }
        }
        var expected: [SpokenPart] = []
        if level.requiresArticle(for: entry), let article = entry.article {
            expected.append(SpokenPart(text: article.rawValue, isArticle: true))
        }
        expected += words(entry.german)
        if level.requiresPlural(for: entry), let plural = entry.plural {
            expected.append(SpokenPart(text: "die", isArticle: true))
            expected += words(plural)
        }

        var best = Verdict.wrong
        for transcript in transcripts {
            var tokens = normalize(transcript).split(separator: " ").map(String.init)
            // Saying the article when it is not required is fine.
            if entry.hasArticle, !level.requiresArticle(for: entry), tokens.count > 1,
               Article(rawValue: tokens[0]) != nil {
                tokens.removeFirst()
            }
            let verdict: Verdict
            if tokens.count == expected.count {
                verdict = zip(tokens, expected).map { (token, part) -> Verdict in
                    if part.isArticle { return token == part.text ? .correct : .wrong }
                    return compareGerman(token, part.text)
                }.min() ?? .wrong
            } else {
                // The recognizer may split or merge compound words.
                verdict = compareGerman(tokens.joined(), expected.map(\.text).joined())
            }
            best = max(best, verdict)
            if best == .correct { break }
        }
        return best
    }

    private static func dropLeadingDie(_ text: String) -> String {
        let normalized = normalize(text)
        return normalized.hasPrefix("die ") ? String(normalized.dropFirst(4)) : normalized
    }
}
