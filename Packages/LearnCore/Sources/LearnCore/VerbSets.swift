import Foundation

/// A fixed group of verbs, picked at random or by hand, trained like the whole verb section.
public struct VerbSet: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var verbIDs: [UUID]
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, verbIDs: [UUID], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.verbIDs = verbIDs
        self.createdAt = createdAt
    }
}

/// What the random picker needs to know about a verb.
public struct VerbSetCandidate: Hashable, Sendable {
    public var id: UUID
    public var isNew: Bool
    public var kindStreaks: [VerbExerciseKind: Int]

    public init(id: UUID, isNew: Bool, kindStreaks: [VerbExerciseKind: Int]) {
        self.id = id
        self.isNew = isNew
        self.kindStreaks = kindStreaks
    }
}

public enum VerbSetPicker {
    public static let sizes = [5, 10, 20]
    public static let defaultSize = 10

    /// Draws `count` distinct verbs at random, favouring new and weak ones:
    /// a verb never studied weighs four times one mastered in every exercise.
    public static func pick<R: RandomNumberGenerator>(_ verbs: [VerbSetCandidate], count: Int,
                                                      using rng: inout R) -> [UUID] {
        WeightedPicker.pick(verbs.map { (id: $0.id, weight: weight(of: $0)) }, count: count, using: &rng)
    }

    public static func pick(_ verbs: [VerbSetCandidate], count: Int) -> [UUID] {
        var rng = SystemRandomNumberGenerator()
        return pick(verbs, count: count, using: &rng)
    }

    /// 1 for a verb mastered in every exercise, up to 4 for a new one.
    public static func weight(of verb: VerbSetCandidate) -> Double {
        guard !verb.isNew else { return 4 }
        return 1 + 3 * (1 - VerbExercises.mastery([verb.kindStreaks]))
    }

    /// "Verb set 1", "Verb set 2"…: the first number not taken.
    public static func nextName(existing: [String]) -> String {
        WeightedPicker.nextName(prefix: "Verb set", existing: existing)
    }
}

public enum VerbSetMerger {
    /// Sets matched by id; the copy from the backup replaces the one on the phone.
    public static func merge(existing: [VerbSet], incoming: [VerbSet]) -> [VerbSet] {
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
