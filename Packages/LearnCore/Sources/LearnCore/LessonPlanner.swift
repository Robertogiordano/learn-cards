import Foundation

/// One question of a planned lesson, stored so the lesson stays the same all day.
public struct LessonItem: Codable, Hashable, Sendable {
    public enum Domain: String, Codable, CaseIterable, Sendable {
        case word, phrase, verb, number, compound
    }

    public enum Reason: String, Codable, Sendable {
        case error, focus, due, new, practice
    }

    public var domain: Domain
    /// Word (also for compounds), phrase or verb; nil for numbers.
    public var id: UUID?
    /// For words.
    public var area: StudyArea?
    /// A forced kind of exercise (raw value of the domain's kind enum); nil means automatic.
    public var kind: String?
    /// For numbers.
    public var numberLevel: Int?
    public var reason: Reason

    public init(domain: Domain, id: UUID? = nil, area: StudyArea? = nil, kind: String? = nil,
                numberLevel: Int? = nil, reason: Reason) {
        self.domain = domain
        self.id = id
        self.area = area
        self.kind = kind
        self.numberLevel = numberLevel
        self.reason = reason
    }

    /// Same question regardless of why or how it is asked.
    var identity: String {
        "\(domain.rawValue)|\(id?.uuidString ?? "")|\(area?.rawValue ?? "")"
    }

    /// Typical time to answer, to fit a lesson into the daily goal.
    public var estimatedSeconds: Int {
        switch domain {
        case .word: return 12
        case .phrase: return 25
        case .verb: return 20
        case .number: return 10
        case .compound: return 15
        }
    }
}

/// What the planner knows about a possible question.
public struct LessonCandidate: Sendable {
    public var item: LessonItem
    /// Theme, phrase category or verb group label.
    public var theme: String?
    public var isDue: Bool
    public var isNew: Bool
    /// Mistakes on this item in the last days.
    public var recentErrors: Int
    /// 0...1, how well it is known.
    public var mastery: Double

    public init(item: LessonItem, theme: String?, isDue: Bool, isNew: Bool, recentErrors: Int, mastery: Double) {
        self.item = item
        self.theme = theme
        self.isDue = isDue
        self.isNew = isNew
        self.recentErrors = recentErrors
        self.mastery = mastery
    }
}

public struct ThemeScore: Sendable {
    public var name: String
    public var recentErrors: Int
    public var mastery: Double

    public init(name: String, recentErrors: Int, mastery: Double) {
        self.name = name
        self.recentErrors = recentErrors
        self.mastery = mastery
    }
}

/// Builds the daily lesson locally: mistakes, focus themes, due reviews, a few new items and numbers.
public enum LessonPlanner {
    /// Two themes to focus on: among the four most in need (mistakes first, then low mastery),
    /// rotating day by day so the same pair does not come back every day.
    public static func focusThemes(_ themes: [ThemeScore], dayIndex: Int, count: Int = 2) -> [String] {
        let ranked = themes.sorted { lhs, rhs in
            if lhs.recentErrors != rhs.recentErrors { return lhs.recentErrors > rhs.recentErrors }
            if lhs.mastery != rhs.mastery { return lhs.mastery < rhs.mastery }
            return lhs.name < rhs.name
        }
        let pool = Array(ranked.prefix(max(count, 4)))
        guard !pool.isEmpty else { return [] }
        let start = ((dayIndex % pool.count) + pool.count) % pool.count
        return (0..<min(count, pool.count)).map { pool[(start + $0) % pool.count].name }
    }

    /// Fills `budgetSeconds` with: recent mistakes (~35%), the focus themes (~35%),
    /// other due reviews and weak items, and ~10% numbers. `difficulty` (-1 easier,
    /// +1 harder, from the learner's feedback) changes how many new items come in.
    public static func compose<R: RandomNumberGenerator>(
        candidates: [LessonCandidate],
        budgetSeconds: Int,
        focusThemes: [String],
        numberLevel: Int?,
        difficulty: Int = 0,
        using rng: inout R
    ) -> [LessonItem] {
        let numbersBudget = numberLevel == nil ? 0 : budgetSeconds / 10
        let wordsBudget = budgetSeconds - numbersBudget
        var chosen: [LessonItem] = []
        var used = Set<String>()
        var spent = 0

        func take(_ list: [LessonCandidate], reason: LessonItem.Reason, upTo limit: Int) {
            var partSpent = 0
            for candidate in list where partSpent < limit && spent < wordsBudget {
                guard used.insert(candidate.item.identity).inserted else { continue }
                var item = candidate.item
                item.reason = reason
                chosen.append(item)
                partSpent += item.estimatedSeconds
                spent += item.estimatedSeconds
            }
        }

        let newShare = max(0, min(0.3, 0.15 + 0.1 * Double(difficulty)))

        let mistakes = candidates.filter { $0.recentErrors > 0 }
            .sorted { $0.recentErrors > $1.recentErrors }
        take(mistakes, reason: .error, upTo: wordsBudget * 35 / 100)

        let focused = candidates.filter { candidate in candidate.theme.map { focusThemes.contains($0) } ?? false }
        let focusedDue = focused.filter { $0.isDue && !$0.isNew }.shuffled(using: &rng)
        let focusedNew = focused.filter(\.isNew).shuffled(using: &rng)
        let focusedWeak = focused.filter { !$0.isNew && !$0.isDue }.sorted { $0.mastery < $1.mastery }
        let focusBudget = wordsBudget * 35 / 100
        take(focusedNew, reason: .new, upTo: Int(Double(focusBudget) * newShare * 2))
        take(focusedDue + focusedWeak, reason: .focus, upTo: focusBudget)

        let due = candidates.filter { $0.isDue && !$0.isNew }.shuffled(using: &rng)
        let weak = candidates.filter { !$0.isNew && !$0.isDue }.sorted { $0.mastery < $1.mastery }
        let fresh = candidates.filter(\.isNew).shuffled(using: &rng)
        take(due, reason: .due, upTo: wordsBudget)
        take(fresh, reason: .new, upTo: Int(Double(wordsBudget) * newShare))
        take(weak, reason: .practice, upTo: wordsBudget)

        if let numberLevel {
            for _ in 0..<max(1, numbersBudget / 10) {
                chosen.append(LessonItem(domain: .number, numberLevel: numberLevel, reason: .practice))
            }
        }
        chosen.shuffle(using: &rng)
        return chosen
    }

    public static func estimatedMinutes(_ items: [LessonItem]) -> Int {
        Int((Double(items.map(\.estimatedSeconds).reduce(0, +)) / 60).rounded(.up))
    }
}
