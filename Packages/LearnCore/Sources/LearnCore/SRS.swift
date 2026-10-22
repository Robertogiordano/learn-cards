import Foundation

/// Spaced-repetition state of one word (SM-2 style).
public struct SRSState: Codable, Hashable, Sendable {
    public var ease: Double
    public var intervalDays: Double
    public var repetitions: Int
    public var lapses: Int
    public var dueDate: Date
    public var lastReviewed: Date?

    public init(ease: Double, intervalDays: Double, repetitions: Int, lapses: Int, dueDate: Date, lastReviewed: Date?) {
        self.ease = ease
        self.intervalDays = intervalDays
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueDate = dueDate
        self.lastReviewed = lastReviewed
    }

    /// A word that has never been studied, due immediately.
    public static func new(now: Date = Date()) -> SRSState {
        SRSState(ease: 2.5, intervalDays: 0, repetitions: 0, lapses: 0, dueDate: now, lastReviewed: nil)
    }

    public var isNew: Bool { lastReviewed == nil }

    public func isDue(at now: Date) -> Bool { dueDate <= now }
}

public enum ReviewGrade: Int, Codable, Sendable {
    case again, hard, good, easy

    /// Multiple choice is recognition, so it never earns "easy".
    public static func from(verdict: Verdict, kind: ExerciseKind, responseTime: TimeInterval) -> ReviewGrade {
        switch verdict {
        case .wrong:
            return .again
        case .almost:
            return .hard
        case .correct:
            return kind != .multipleChoice && responseTime < 8 ? .easy : .good
        }
    }
}

public enum SRS {
    public static let minimumEase = 1.3
    public static let maximumIntervalDays = 365.0

    public static func review(
        _ state: SRSState,
        grade: ReviewGrade,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SRSState {
        var next = state
        switch grade {
        case .again:
            next.repetitions = 0
            next.lapses += 1
            next.ease -= 0.2
            next.intervalDays = 1
        case .hard:
            next.ease -= 0.15
            next.intervalDays = state.repetitions == 0 ? 1 : max(1, state.intervalDays * 1.2)
            next.repetitions += 1
        case .good:
            switch state.repetitions {
            case 0: next.intervalDays = 1
            case 1: next.intervalDays = 3
            default: next.intervalDays = state.intervalDays * state.ease
            }
            next.repetitions += 1
        case .easy:
            next.ease += 0.15
            switch state.repetitions {
            case 0: next.intervalDays = 3
            case 1: next.intervalDays = 5
            default: next.intervalDays = state.intervalDays * next.ease * 1.3
            }
            next.repetitions += 1
        }
        next.ease = max(minimumEase, next.ease)
        next.intervalDays = min(maximumIntervalDays, next.intervalDays)
        next.lastReviewed = now

        // Due at the start of the target day, so a word reviewed in the evening is ready the next morning.
        let days = max(1, Int(next.intervalDays.rounded()))
        next.dueDate = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(Double(days) * 86_400)
        return next
    }
}
