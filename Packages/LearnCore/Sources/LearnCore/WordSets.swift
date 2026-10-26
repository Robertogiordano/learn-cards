import Foundation

/// A fixed group of words picked at random, trained like a theme.
public struct WordSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var wordIDs: [UUID]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, wordIDs: [UUID], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.wordIDs = wordIDs
        self.createdAt = createdAt
    }
}

public enum WordSetPicker {
    public static let sizes = [10, 20, 30]
    public static let defaultSize = 20

    /// Draws `count` distinct words at random, favouring new and weak ones:
    /// a word nobody has studied weighs four times one mastered in every area.
    public static func pick<R: RandomNumberGenerator>(_ words: [PathWord], count: Int, using rng: inout R) -> [UUID] {
        var pool = words.map { (id: $0.id, weight: weight(of: $0)) }
        var picked: [UUID] = []
        while picked.count < count, !pool.isEmpty {
            let total = pool.reduce(0) { $0 + $1.weight }
            var target = Double.random(in: 0..<total, using: &rng)
            var index = pool.count - 1
            for (offset, entry) in pool.enumerated() {
                if target < entry.weight {
                    index = offset
                    break
                }
                target -= entry.weight
            }
            picked.append(pool.remove(at: index).id)
        }
        return picked
    }

    public static func pick(_ words: [PathWord], count: Int) -> [UUID] {
        var rng = SystemRandomNumberGenerator()
        return pick(words, count: count, using: &rng)
    }

    /// 1 for a word mastered everywhere, up to 4 for a new or forgotten one.
    public static func weight(of word: PathWord) -> Double {
        guard !word.isNew, !word.schedules.isEmpty else { return 4 }
        let known = word.schedules.keys
            .map { PathPlanner.progress(level: word.level(in: $0)) }
            .reduce(0, +) / Double(word.schedules.count)
        return 1 + 3 * (1 - known)
    }

    /// "Set 1", "Set 2"…: the first number not taken.
    public static func nextName(existing: [String]) -> String {
        let taken = Set(existing)
        var number = 1
        while taken.contains("Set \(number)") { number += 1 }
        return "Set \(number)"
    }
}

public enum WordSetMerger {
    /// Sets matched by id; the copy from the backup replaces the one on the phone.
    public static func merge(existing: [WordSet], incoming: [WordSet]) -> [WordSet] {
        var result = existing
        for set in incoming {
            if let index = result.firstIndex(where: { $0.id == set.id }) {
                result[index] = set
            } else {
                result.append(set)
            }
        }
        return result
    }
}
