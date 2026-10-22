import Foundation

/// Ranges of numbers, trained one at a time.
public enum NumberLevel: Int, CaseIterable, Codable, Hashable, Sendable {
    case upTo20 = 1, upTo100, upTo1000, upToMillion

    public var range: ClosedRange<Int> {
        switch self {
        case .upTo20: return 0...20
        case .upTo100: return 21...100
        case .upTo1000: return 101...1000
        case .upToMillion: return 1001...GermanNumbers.maximum
        }
    }

    public var title: String {
        "\(GermanNumbers.digits(range.lowerBound))–\(GermanNumbers.digits(range.upperBound))"
    }

    /// Big numbers come in every size, not only six digits.
    public func random<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        guard self == .upToMillion else { return Int.random(in: range, using: &rng) }
        let length = Int.random(in: 4...7, using: &rng)
        let low = Int(pow(10, Double(length - 1)))
        let high = min(Int(pow(10, Double(length))) - 1, GermanNumbers.maximum)
        return Int.random(in: max(low, range.lowerBound)...high, using: &rng)
    }
}

public enum NumberExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Hear the number, pick it among four.
    case listenChoice
    /// Hear the number, type the digits.
    case listenDigits
    /// See the digits, write the number in words.
    case writeWords
    /// See the digits, say the number.
    case speak

    public var title: String {
        switch self {
        case .listenChoice: return "Ascolta e scegli"
        case .listenDigits: return "Ascolta e scrivi le cifre"
        case .writeWords: return "Scrivi a lettere"
        case .speak: return "Pronuncia"
        }
    }

    public var isListening: Bool { self == .listenChoice || self == .listenDigits }
}

public struct NumberExercise: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: NumberExerciseKind
    public let level: NumberLevel
    public let number: Int
    /// Multiple-choice options (listenChoice only).
    public let options: [Int]

    public init(id: UUID = UUID(), kind: NumberExerciseKind, level: NumberLevel, number: Int, options: [Int] = []) {
        self.id = id
        self.kind = kind
        self.level = level
        self.number = number
        self.options = options
    }

    public var correctIndex: Int? { options.firstIndex(of: number) }
    public var words: String { GermanNumbers.spell(number) }
    public var digits: String { GermanNumbers.digits(number) }
}

public enum NumberQuiz {
    /// Share of questions that bring back a number recently missed.
    public static let mistakeShare = 0.3

    public static func make<R: RandomNumberGenerator>(
        kind: NumberExerciseKind,
        level: NumberLevel,
        stats: NumberStats,
        using rng: inout R
    ) -> NumberExercise {
        let missed = stats.mistakes(in: level)
        let number: Int
        if !missed.isEmpty, Double.random(in: 0..<1, using: &rng) < mistakeShare, let pick = missed.randomElement(using: &rng) {
            number = pick
        } else {
            number = level.random(using: &rng)
        }
        guard kind == .listenChoice else {
            return NumberExercise(kind: kind, level: level, number: number)
        }
        var options = Array(distractors(for: number, level: level, using: &rng).prefix(3)) + [number]
        options.shuffle(using: &rng)
        return NumberExercise(kind: kind, level: level, number: number, options: options)
    }

    /// Numbers that really get confused when heard: swapped digits (21 ↔ 12, the units
    /// come first in German), -zehn/-zig (13 ↔ 30), then neighbours.
    public static func distractors<R: RandomNumberGenerator>(for number: Int, level: NumberLevel, using rng: inout R) -> [Int] {
        let units = number % 10, tens = (number / 10) % 10, lastTwo = number % 100
        var tricky: [Int] = []
        if number >= 10, units != 0, units != tens {
            tricky.append(number - units - tens * 10 + units * 10 + tens)
        }
        if (13...19).contains(lastTwo) {
            tricky.append(number - lastTwo + units * 10)
        }
        if lastTwo >= 30, units == 0 {
            tricky.append(number - lastTwo + tens + 10)
        }
        var near = [number + 1, number - 1, number + 10, number - 10]
        if number >= 100 { near += [number + 100, number - 100] }
        if number >= 1000 { near += [number + 1000, number - 1000] }

        var result: [Int] = []
        for candidate in tricky + near.shuffled(using: &rng)
        where candidate != number && (0...GermanNumbers.maximum).contains(candidate) && !result.contains(candidate) {
            result.append(candidate)
        }
        while result.count < 3 {
            let candidate = level.random(using: &rng)
            if candidate != number && !result.contains(candidate) { result.append(candidate) }
        }
        return result
    }

    // MARK: - Checking answers

    /// Digits typed after listening; "1000" and "1.000" both count.
    public static func checkDigits(_ given: String, number: Int) -> Verdict {
        let compact = given.filter { !$0.isWhitespace && $0 != "." }
        guard !compact.isEmpty, compact.allSatisfy(\.isNumber) else { return .wrong }
        return Int(compact) == number ? .correct : .wrong
    }

    /// The number in words: any correct spelling counts (hundert / einhundert, ss for ß,
    /// spaces); one or two typos on long words count as almost. Digits are not words.
    public static func checkWords(_ given: String, number: Int) -> Verdict {
        guard !given.contains(where: \.isNumber) else { return .wrong }
        if GermanNumbers.parse(given) == number { return .correct }
        let folded = GermanNumbers.fold(given)
        let expected = GermanNumbers.fold(GermanNumbers.spell(number))
        guard !folded.isEmpty else { return .wrong }
        let tolerance = expected.count > 12 ? 2 : 1
        return AnswerChecker.levenshtein(folded, expected) <= tolerance && expected.count >= 4 ? .almost : .wrong
    }

    /// Recognised speech, digits or words.
    public static func checkSpoken(_ transcripts: [String], number: Int) -> Verdict {
        transcripts.contains { GermanNumbers.parse($0) == number } ? .correct : .wrong
    }
}

/// Number practice history: the last answers per level and kind (the percentages)
/// and recently missed numbers per level (asked again more often).
public struct NumberStats: Codable, Equatable, Sendable {
    public static let window = 20
    public static let maximumMistakes = 10

    public var results: [String: [Bool]]
    public var mistakes: [String: [Int]]

    public init(results: [String: [Bool]] = [:], mistakes: [String: [Int]] = [:]) {
        self.results = results
        self.mistakes = mistakes
    }

    public var isEmpty: Bool { results.isEmpty }

    private static func key(_ level: NumberLevel, _ kind: NumberExerciseKind) -> String {
        "\(level.rawValue).\(kind.rawValue)"
    }

    /// Right answers among the last 20, over 20: it fills up as you practise.
    public func progress(_ level: NumberLevel, _ kind: NumberExerciseKind) -> Double {
        let recent = results[Self.key(level, kind)] ?? []
        return Double(recent.filter { $0 }.count) / Double(Self.window)
    }

    /// Average of the level's kinds of exercise.
    public func progress(_ level: NumberLevel) -> Double {
        let kinds = NumberExerciseKind.allCases
        return kinds.map { progress(level, $0) }.reduce(0, +) / Double(kinds.count)
    }

    public func mistakes(in level: NumberLevel) -> [Int] {
        mistakes[String(level.rawValue)] ?? []
    }

    public mutating func record(_ correct: Bool, number: Int, level: NumberLevel, kind: NumberExerciseKind) {
        let key = Self.key(level, kind)
        results[key, default: []].append(correct)
        if let count = results[key]?.count, count > Self.window {
            results[key]?.removeFirst(count - Self.window)
        }
        updateMistakes(correct, number: number, level: level)
    }

    /// Changes the last recorded answer of that level and kind ("I was right").
    public mutating func replaceLast(with correct: Bool, number: Int, level: NumberLevel, kind: NumberExerciseKind) {
        let key = Self.key(level, kind)
        guard let last = results[key]?.indices.last else { return }
        results[key]?[last] = correct
        updateMistakes(correct, number: number, level: level)
    }

    private mutating func updateMistakes(_ correct: Bool, number: Int, level: NumberLevel) {
        let key = String(level.rawValue)
        var list = mistakes[key] ?? []
        list.removeAll { $0 == number }
        if !correct {
            list.append(number)
            if list.count > Self.maximumMistakes { list.removeFirst(list.count - Self.maximumMistakes) }
        }
        mistakes[key] = list.isEmpty ? nil : list
    }
}
