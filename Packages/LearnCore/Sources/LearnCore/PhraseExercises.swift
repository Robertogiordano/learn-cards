import Foundation

/// Checks a whole sentence against its accepted forms.
public enum PhraseChecker {
    /// Words of a sentence, lowercased and without punctuation.
    public static func tokens(_ text: String) -> [String] {
        AnswerChecker.normalize(text).split(separator: " ").map(String.init)
    }

    /// Duplicate key: also ignores the spelling of umlauts and ß.
    public static func key(_ text: String) -> String {
        AnswerChecker.foldGerman(AnswerChecker.normalize(text))
    }

    /// Right if it matches a form word for word (case, punctuation, ae/oe/ue/ss do not matter);
    /// almost if exactly one word has a small typo; wrong otherwise.
    public static func check(_ given: String, accepted: [String]) -> Verdict {
        let words = tokens(given)
        guard !words.isEmpty else { return .wrong }
        var best = Verdict.wrong
        for form in accepted {
            let expected = tokens(form)
            guard expected.count == words.count else { continue }
            let verdicts = zip(words, expected).map { pair in AnswerChecker.compareGerman(pair.0, pair.1) }
            if verdicts.allSatisfy({ $0 == .correct }) { return .correct }
            if !verdicts.contains(.wrong), verdicts.filter({ $0 == .almost }).count == 1 {
                best = .almost
            }
        }
        return best
    }

    /// Spoken answers: the best of the recognizer's candidates.
    public static func checkSpoken(_ transcripts: [String], accepted: [String]) -> Verdict {
        transcripts.map { check($0, accepted: accepted) }.max() ?? .wrong
    }

    /// Positions of the words of `expected` missing from `given`, to highlight them in the solution.
    public static func missingWords(in given: String, expected: String) -> Set<Int> {
        var available = tokens(given).map { AnswerChecker.foldGerman($0) }
        var missing = Set<Int>()
        for (index, word) in tokens(expected).enumerated() {
            if let match = available.firstIndex(of: AnswerChecker.foldGerman(word)) {
                available.remove(at: match)
            } else {
                missing.insert(index)
            }
        }
        return missing
    }
}

/// Builds the phrase exercises and their progress.
public enum PhraseExercises {
    private static let edgePunctuation = CharacterSet(charactersIn: ".,;:!?\"'«»„“”‚‘’()")

    /// The sentence's words as written, without the punctuation around them.
    public static func tiles(for sentence: String) -> [String] {
        sentence.split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty }
    }

    /// Tiles in an order different from the sentence (when that is possible).
    public static func shuffledTiles<R: RandomNumberGenerator>(for sentence: String, using rng: inout R) -> [String] {
        let original = tiles(for: sentence)
        guard Set(original).count > 1 else { return original }
        var shuffled = original
        for _ in 0..<10 {
            shuffled.shuffle(using: &rng)
            if shuffled != original { break }
        }
        return shuffled
    }

    /// Tiles put in order: right only if they form one of the accepted sentences exactly.
    public static func checkReorder(_ chosen: [String], entry: PhraseEntry) -> Verdict {
        PhraseChecker.check(chosen.joined(separator: " "), accepted: entry.accepted) == .correct ? .correct : .wrong
    }

    /// The word to hide: the longest one after the first, at least three letters.
    public static func clozeIndex(in sentence: String) -> Int? {
        let words = tiles(for: sentence)
        guard words.count >= 2 else { return nil }
        var best: Int?
        for index in 1..<words.count where words[index].count >= 3 {
            if best.map({ words[index].count > words[$0].count }) ?? true {
                best = index
            }
        }
        return best
    }

    /// The sentence with the hidden word as a blank, and the hidden word.
    public static func cloze(for sentence: String) -> (shown: String, answer: String)? {
        guard let index = clozeIndex(in: sentence) else { return nil }
        var words = tiles(for: sentence)
        let answer = words[index]
        words[index] = "_____"
        let ending = sentence.trimmingCharacters(in: .whitespaces).last.map { "?!.".contains($0) ? String($0) : "" } ?? ""
        return (words.joined(separator: " ") + ending, answer)
    }

    /// From building to producing, by right answers in a row on the phrase:
    /// reorder first, then fill in or dictation, then translate, speak or find the question.
    public static func kind<R: RandomNumberGenerator>(
        level: Int,
        entry: PhraseEntry,
        allowSpeaking: Bool,
        using rng: inout R
    ) -> PhraseExerciseKind {
        let candidates: [PhraseExerciseKind]
        switch level {
        case ...0: candidates = [.reorder]
        case 1: candidates = [.cloze, .dictation]
        default:
            candidates = [.translate, .questionFromAnswer, .dictation] + (allowSpeaking ? [.speak] : [])
        }
        let applicable = candidates.filter { $0.isApplicable(to: entry) }
        return applicable.randomElement(using: &rng) ?? .translate
    }

    /// Per kind of exercise: average progress over the phrases it applies to.
    public static func kindMastery(_ phrases: [(entry: PhraseEntry, streaks: [PhraseExerciseKind: Int])]) -> [PhraseExerciseKind: Double] {
        var result: [PhraseExerciseKind: Double] = [:]
        for kind in PhraseExerciseKind.allCases {
            let applicable = phrases.filter { kind.isApplicable(to: $0.entry) }
            guard !applicable.isEmpty else { continue }
            let total = applicable.map { PathPlanner.progress(level: $0.streaks[kind] ?? 0) }.reduce(0, +)
            result[kind] = total / Double(applicable.count)
        }
        return result
    }

    /// Average of the kinds.
    public static func mastery(_ phrases: [(entry: PhraseEntry, streaks: [PhraseExerciseKind: Int])]) -> Double {
        let kinds = kindMastery(phrases)
        return kinds.isEmpty ? 0 : kinds.values.reduce(0, +) / Double(kinds.count)
    }
}
