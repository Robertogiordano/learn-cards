import Foundation

public struct StudyCandidate: Hashable, Sendable {
    public var id: UUID
    public var srs: SRSState
    public var createdAt: Date
    /// Right answers in a row in the exercise being trained (2 = mastered).
    public var level: Int

    public init(id: UUID, srs: SRSState, createdAt: Date, level: Int = 0) {
        self.id = id
        self.srs = srs
        self.createdAt = createdAt
        self.level = level
    }
}

public enum SessionPlanner {
    /// Right answers in a row after which an item counts as mastered in an exercise.
    public static let masteredLevel = 2

    /// Due reviews first (most overdue first), then new items in the order they were added,
    /// at most `newLimit` of them when there are reviews too.
    /// With `includeNotDue` the session is topped up with the weakest items in the exercise
    /// being trained, shuffled among equals so that extra practice rotates; mastered items come last.
    public static func select<R: RandomNumberGenerator>(
        _ candidates: [StudyCandidate],
        now: Date,
        limit: Int,
        includeNotDue: Bool = false,
        newLimit: Int? = nil,
        using rng: inout R
    ) -> [UUID] {
        let due = candidates.filter { $0.srs.isDue(at: now) }
        let reviews = due.filter { !$0.srs.isNew }.sorted { $0.srs.dueDate < $1.srs.dueDate }
        var fresh = due.filter { $0.srs.isNew }.sorted { $0.createdAt < $1.createdAt }
        if let newLimit, !reviews.isEmpty {
            fresh = Array(fresh.prefix(newLimit))
        }
        var picked = Array((reviews + fresh).prefix(limit))
        if includeNotDue, picked.count < limit {
            let chosen = Set(picked.map(\.id))
            let rest = candidates.filter { !chosen.contains($0.id) && !$0.srs.isNew }
            // Shuffle first, then a stable sort by level keeps the shuffle among equals.
            let ranked = rest.shuffled(using: &rng)
                .enumerated()
                .sorted { lhs, rhs in
                    let left = min(lhs.element.level, masteredLevel), right = min(rhs.element.level, masteredLevel)
                    return left != right ? left < right : lhs.offset < rhs.offset
                }
                .map(\.element)
            picked += ranked.prefix(limit - picked.count)
        }
        return picked.map(\.id)
    }

    public static func select(_ candidates: [StudyCandidate], now: Date, limit: Int,
                              includeNotDue: Bool = false, newLimit: Int? = nil) -> [UUID] {
        var rng = SystemRandomNumberGenerator()
        return select(candidates, now: now, limit: limit, includeNotDue: includeNotDue, newLimit: newLimit, using: &rng)
    }

    public static func dueCount(_ candidates: [StudyCandidate], now: Date) -> Int {
        candidates.filter { $0.srs.isDue(at: now) }.count
    }
}
