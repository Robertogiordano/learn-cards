import Foundation

public struct StudyCandidate: Hashable, Sendable {
    public var id: UUID
    public var srs: SRSState
    public var createdAt: Date

    public init(id: UUID, srs: SRSState, createdAt: Date) {
        self.id = id
        self.srs = srs
        self.createdAt = createdAt
    }
}

public enum SessionPlanner {
    /// Due reviews first (most overdue first), then new words in the order they were added.
    /// With `includeNotDue` the session is topped up with the words closest to being due.
    public static func select(_ candidates: [StudyCandidate], now: Date, limit: Int, includeNotDue: Bool = false) -> [UUID] {
        let due = candidates.filter { $0.srs.isDue(at: now) }
        let reviews = due.filter { !$0.srs.isNew }.sorted { $0.srs.dueDate < $1.srs.dueDate }
        let fresh = due.filter { $0.srs.isNew }.sorted { $0.createdAt < $1.createdAt }
        var picked = Array((reviews + fresh).prefix(limit))
        if includeNotDue, picked.count < limit {
            let upcoming = candidates
                .filter { !$0.srs.isDue(at: now) }
                .sorted { $0.srs.dueDate < $1.srs.dueDate }
            picked += upcoming.prefix(limit - picked.count)
        }
        return picked.map(\.id)
    }

    public static func dueCount(_ candidates: [StudyCandidate], now: Date) -> Int {
        candidates.filter { $0.srs.isDue(at: now) }.count
    }
}
