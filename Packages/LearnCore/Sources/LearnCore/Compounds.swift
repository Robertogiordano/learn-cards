import Foundation

/// The games of the compound words section.
public enum CompoundExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Connect the first parts with the second parts, several compounds at once.
    case matchPairs
    /// "Küche + ___": choose the missing part.
    case completeWord
    /// From the English meaning, tap the parts in order.
    case buildFromMeaning
    /// From the parts, type the compound with its article.
    case typeCompound

    public var title: String {
        switch self {
        case .matchPairs: return "Match the pairs"
        case .completeWord: return "Complete the word"
        case .buildFromMeaning: return "Build from meaning"
        case .typeCompound: return "Type the compound"
        }
    }
}

/// Several two-part compounds to connect: every first part and every second part is unique.
public struct CompoundMatchRound: Hashable, Sendable {
    public var compounds: [VocabEntry]
    public var left: [String]
    public var right: [String]

    /// The compound made by these two tiles, if any.
    public func compound(left first: String, right second: String) -> VocabEntry? {
        compounds.first { entry in
            PhraseChecker.key(entry.parts[0]) == PhraseChecker.key(first)
                && PhraseChecker.key(entry.parts[1]) == PhraseChecker.key(second)
        }
    }

    /// The compound a first part belongs to.
    public func compound(left first: String) -> VocabEntry? {
        compounds.first { PhraseChecker.key($0.parts[0]) == PhraseChecker.key(first) }
    }
}

/// One part hidden, to choose among options.
public struct CompoundCompleteQuestion: Hashable, Sendable {
    public var entry: VocabEntry
    public var missingIndex: Int
    public var options: [String]

    public var answer: String { entry.parts[missingIndex] }
}

/// The English meaning and a pool of parts to tap in order.
public struct CompoundBuildQuestion: Hashable, Sendable {
    public var entry: VocabEntry
    public var tiles: [String]
}

public enum CompoundGame {
    public static let pairsPerRound = 5
    /// A match round needs at least this many two-part compounds.
    public static let minimumPairs = 3

    /// Two-part compounds with no first or second part in common, in the given order.
    public static func matchRound<R: RandomNumberGenerator>(_ compounds: [VocabEntry], using rng: inout R) -> CompoundMatchRound? {
        var picked: [VocabEntry] = []
        var firsts = Set<String>(), seconds = Set<String>()
        for entry in compounds where entry.parts.count == 2 && picked.count < pairsPerRound {
            let first = PhraseChecker.key(entry.parts[0]), second = PhraseChecker.key(entry.parts[1])
            guard !firsts.contains(first), !seconds.contains(second) else { continue }
            firsts.insert(first)
            seconds.insert(second)
            picked.append(entry)
        }
        guard picked.count >= minimumPairs else { return nil }
        return CompoundMatchRound(compounds: picked,
                                  left: picked.map { $0.parts[0] }.shuffled(using: &rng),
                                  right: picked.map { $0.parts[1] }.shuffled(using: &rng))
    }

    /// Hides one part; the options come from the same position in other compounds, then
    /// from other parts and words. Options that would make another known compound are left out.
    public static func complete<R: RandomNumberGenerator>(_ entry: VocabEntry, compounds: [VocabEntry], words: [String],
                                                          using rng: inout R) -> CompoundCompleteQuestion {
        let index = Int.random(in: 0..<entry.parts.count, using: &rng)
        let others = compounds.filter { $0.id != entry.id }
        let samePosition = others.compactMap { index < $0.parts.count ? $0.parts[index] : nil }.shuffled(using: &rng)
        let otherParts = others.flatMap(\.parts).shuffled(using: &rng)
        let known = Set(compounds.map { $0.parts.map(PhraseChecker.key) })
        var keys: Set<String> = [PhraseChecker.key(entry.parts[index])]
        var distractors: [String] = []
        for candidate in samePosition + otherParts + words.shuffled(using: &rng) where distractors.count < 3 {
            var replaced = entry.parts.map(PhraseChecker.key)
            replaced[index] = PhraseChecker.key(candidate)
            guard !known.contains(replaced), keys.insert(PhraseChecker.key(candidate)).inserted else { continue }
            distractors.append(candidate)
        }
        let options = ([entry.parts[index]] + distractors).shuffled(using: &rng)
        return CompoundCompleteQuestion(entry: entry, missingIndex: index, options: options)
    }

    /// The parts plus distractors, 6 to 8 tiles in all.
    public static func build<R: RandomNumberGenerator>(_ entry: VocabEntry, compounds: [VocabEntry], words: [String],
                                                       using rng: inout R) -> CompoundBuildQuestion {
        let target = min(8, max(6, entry.parts.count + 4))
        var keys = Set(entry.parts.map(PhraseChecker.key))
        var tiles = entry.parts
        let candidates = compounds.filter { $0.id != entry.id }.flatMap(\.parts).shuffled(using: &rng)
            + words.shuffled(using: &rng)
        for candidate in candidates where tiles.count < target {
            guard keys.insert(PhraseChecker.key(candidate)).inserted else { continue }
            tiles.append(candidate)
        }
        return CompoundBuildQuestion(entry: entry, tiles: tiles.shuffled(using: &rng))
    }

    /// Right only with every part, in order.
    public static func checkBuild(_ chosen: [String], entry: VocabEntry) -> Verdict {
        chosen.map(PhraseChecker.key) == entry.parts.map(PhraseChecker.key) ? .correct : .wrong
    }

    /// "die Küchentür": right; "Küchentür" without the article: almost; a wrong article: wrong.
    public static func checkTyped(_ given: String, entry: VocabEntry) -> Verdict {
        let full = AnswerChecker.compareGerman(given, entry.withArticle)
        guard full != .correct, entry.article != nil else { return full }
        let words = AnswerChecker.normalize(given).split(separator: " ")
        if words.count == 1, AnswerChecker.compareGerman(given, entry.german) != .wrong {
            return .almost
        }
        // The article is the point: a wrong one is never a typo.
        if let typed = words.first.flatMap({ Article(rawValue: String($0)) }), typed != entry.article {
            return .wrong
        }
        return full
    }

    /// From recognising to producing: matching or completing first, then building, then typing.
    public static func kind<R: RandomNumberGenerator>(level: Int, canMatch: Bool, using rng: inout R) -> CompoundExerciseKind {
        switch level {
        case ...0:
            return canMatch && Bool.random(using: &rng) ? .matchPairs : .completeWord
        case 1:
            return .buildFromMeaning
        default:
            return canMatch && Int.random(in: 0..<4, using: &rng) == 0 ? .matchPairs : .typeCompound
        }
    }

    /// Share of mastery per kind: one right answer is half, two in a row is full.
    public static func kindMastery(_ streaks: [[CompoundExerciseKind: Int]]) -> [CompoundExerciseKind: Double] {
        var result: [CompoundExerciseKind: Double] = [:]
        for kind in CompoundExerciseKind.allCases {
            let total = streaks.map { PathPlanner.progress(level: $0[kind] ?? 0) }.reduce(0, +)
            result[kind] = streaks.isEmpty ? 0 : total / Double(streaks.count)
        }
        return result
    }

    public static func mastery(_ streaks: [[CompoundExerciseKind: Int]]) -> Double {
        let kinds = kindMastery(streaks)
        return kinds.values.reduce(0, +) / Double(max(kinds.count, 1))
    }
}
