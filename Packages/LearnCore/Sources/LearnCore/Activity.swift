import Foundation

/// A mistake (or near miss), kept to plan lessons on what goes wrong.
public struct ErrorRecord: Codable, Hashable, Sendable {
    public var date: Date
    public var domain: LessonItem.Domain
    /// The word, phrase or verb; nil for numbers.
    public var itemID: UUID?
    /// "translation.typeGerman", "verb.typeForm", "number.listenChoice"...
    public var exercise: String
    /// What was asked, readable: "du · fahren", "table", "47".
    public var prompt: String
    public var given: String
    public var expected: String
    /// Theme, phrase category or verb group.
    public var theme: String?

    public init(date: Date, domain: LessonItem.Domain, itemID: UUID?, exercise: String, prompt: String,
                given: String, expected: String, theme: String?) {
        self.date = date
        self.domain = domain
        self.itemID = itemID
        self.exercise = exercise
        self.prompt = prompt
        self.given = given
        self.expected = expected
        self.theme = theme
    }
}

/// Daily study time and recent mistakes.
public struct ActivityStats: Codable, Equatable, Sendable {
    public static let maximumErrors = 300

    /// Active seconds per day, keyed "yyyy-MM-dd".
    public var secondsByDay: [String: Int]
    public var errors: [ErrorRecord]

    public init(secondsByDay: [String: Int] = [:], errors: [ErrorRecord] = []) {
        self.secondsByDay = secondsByDay
        self.errors = errors
    }

    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public func seconds(on date: Date, calendar: Calendar = .current) -> Int {
        secondsByDay[Self.dayKey(date, calendar: calendar)] ?? 0
    }

    public mutating func add(seconds: Int, on date: Date, calendar: Calendar = .current) {
        guard seconds > 0 else { return }
        secondsByDay[Self.dayKey(date, calendar: calendar), default: 0] += seconds
    }

    public mutating func log(_ error: ErrorRecord) {
        errors.append(error)
        if errors.count > Self.maximumErrors {
            errors.removeFirst(errors.count - Self.maximumErrors)
        }
    }

    public func errors(since date: Date) -> [ErrorRecord] {
        errors.filter { $0.date >= date }
    }

    /// Days in a row with the goal reached. Today counts once reached and does not break
    /// the streak before; each calendar week forgives one missed day.
    public func streak(goalMinutes: Int, today: Date, calendar: Calendar = .current) -> Int {
        guard goalMinutes > 0 else { return 0 }
        let goal = goalMinutes * 60
        let firstDay = secondsByDay.keys.min()
        var day = calendar.startOfDay(for: today)
        if seconds(on: day, calendar: calendar) < goal {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        var usedJokers = Set<String>()
        while let first = firstDay, Self.dayKey(day, calendar: calendar) >= first {
            if seconds(on: day, calendar: calendar) >= goal {
                streak += 1
            } else {
                let week = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
                let weekKey = "\(week.yearForWeekOfYear ?? 0)-\(week.weekOfYear ?? 0)"
                guard usedJokers.insert(weekKey).inserted else { break }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The last `count` days, oldest first, with their active seconds.
    public func lastDays(_ count: Int, today: Date, calendar: Calendar = .current) -> [(date: Date, seconds: Int)] {
        let start = calendar.startOfDay(for: today)
        return (0..<count).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start).map { ($0, seconds(on: $0, calendar: calendar)) }
        }
    }
}
