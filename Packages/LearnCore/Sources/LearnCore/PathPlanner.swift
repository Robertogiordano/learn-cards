import Foundation

/// One question to ask: a word trained in one area.
public struct StudyItem: Hashable, Sendable {
    public var wordID: UUID
    public var area: StudyArea

    public init(wordID: UUID, area: StudyArea) {
        self.wordID = wordID
        self.area = area
    }
}

/// What the path needs to know about a word.
public struct PathWord: Sendable {
    public var id: UUID
    public var category: String
    public var createdAt: Date
    /// One schedule per area the word takes part in (no article area for verbs, ...).
    public var schedules: [StudyArea: SRSState]
    /// Correct answers in a row per area, any kind of exercise, counting every session
    /// (practice included): drives the adaptive kind. Missing areas fall back to the
    /// schedule's repetitions.
    public var streaks: [StudyArea: Int]
    /// Correct answers in a row per area and kind of exercise: drives the percentages.
    public var kindStreaks: [StudyArea: [ExerciseKind: Int]]

    public init(id: UUID, category: String, createdAt: Date, schedules: [StudyArea: SRSState],
                streaks: [StudyArea: Int] = [:], kindStreaks: [StudyArea: [ExerciseKind: Int]] = [:]) {
        self.id = id
        self.category = category
        self.createdAt = createdAt
        self.schedules = schedules
        self.streaks = streaks
        self.kindStreaks = kindStreaks
    }

    /// Right answers in a row with one kind of exercise in an area.
    public func level(in area: StudyArea, kind: ExerciseKind) -> Int {
        kindStreaks[area]?[kind] ?? 0
    }

    /// Never studied in any area.
    public var isNew: Bool { schedules.values.allSatisfy(\.isNew) }

    /// How far the word got in an area: 0 new or just missed, 1 right once, 2+ mastered.
    public func level(in area: StudyArea) -> Int {
        streaks[area] ?? schedules[area]?.repetitions ?? 0
    }
}

public struct ThemeProgress: Identifiable, Sendable {
    public var theme: String
    public var wordCount: Int
    /// Words never studied: shown as "+N nuove".
    public var newCount: Int
    /// Share of mastery per area and kind of exercise; areas with no applicable word are absent.
    public var kindMastery: [StudyArea: [ExerciseKind: Double]]

    public var id: String { theme }

    /// Per area: the average of its kinds of exercise.
    public var mastery: [StudyArea: Double] {
        kindMastery.mapValues { kinds in
            kinds.isEmpty ? 0 : kinds.values.reduce(0, +) / Double(kinds.count)
        }
    }

    public func hasStar(_ area: StudyArea) -> Bool {
        (mastery[area] ?? 0) >= PathPlanner.starThreshold
    }

    public var averageMastery: Double {
        mastery.isEmpty ? 0 : mastery.values.reduce(0, +) / Double(mastery.count)
    }
}

/// The guided path: theme map, "continue" lessons and the mixed bonus review.
/// Everything is derived from per-word state, so new themes and new words simply
/// show up without resetting any progress.
public enum PathPlanner {
    public static let starThreshold = 0.8
    public static let masteryRepetitions = 2

    /// Share of mastery a word brings to its theme for one kind of exercise:
    /// one right answer is half way, two in a row is full; a mistake starts over.
    public static func progress(level: Int) -> Double {
        Double(min(max(level, 0), masteryRepetitions)) / Double(masteryRepetitions)
    }

    /// Themes with new words first, then alphabetical, the catch-all theme last.
    public static func themeProgress(_ words: [PathWord]) -> [ThemeProgress] {
        let progress = Dictionary(grouping: words, by: \.category).map { theme, themeWords in
            var kindMastery: [StudyArea: [ExerciseKind: Double]] = [:]
            for area in StudyArea.allCases {
                let applicable = themeWords.filter { $0.schedules[area] != nil }
                guard !applicable.isEmpty else { continue }
                var kinds: [ExerciseKind: Double] = [:]
                for kind in area.kinds {
                    let total = applicable.map { progress(level: $0.level(in: area, kind: kind)) }.reduce(0, +)
                    kinds[kind] = total / Double(applicable.count)
                }
                kindMastery[area] = kinds
            }
            return ThemeProgress(
                theme: theme,
                wordCount: themeWords.count,
                newCount: themeWords.filter(\.isNew).count,
                kindMastery: kindMastery
            )
        }
        return progress.sorted { lhs, rhs in
            if (lhs.newCount > 0) != (rhs.newCount > 0) { return lhs.newCount > 0 }
            if lhs.theme == VocabEntry.defaultCategory { return false }
            if rhs.theme == VocabEntry.defaultCategory { return true }
            return lhs.theme.localizedCaseInsensitiveCompare(rhs.theme) == .orderedAscending
        }
    }

    /// The theme of the most recently added new word (usually the page just imported);
    /// without new words, the weakest theme.
    public static func focusTheme(_ words: [PathWord]) -> String? {
        if let newest = words.filter(\.isNew).max(by: { $0.createdAt < $1.createdAt }) {
            return newest.category
        }
        return themeProgress(words)
            .min { lhs, rhs in
                lhs.averageMastery != rhs.averageMastery
                    ? lhs.averageMastery < rhs.averageMastery
                    : lhs.theme.localizedCaseInsensitiveCompare(rhs.theme) == .orderedAscending
            }?
            .theme
    }

    /// Lesson on the focus theme: its due reviews, then up to `newLimit` new items.
    /// Article and plural of a word come only after its translation was answered right once.
    public static func lesson(_ words: [PathWord], now: Date, newLimit: Int, reviewLimit: Int = 20) -> [StudyItem] {
        guard let theme = focusTheme(words) else { return [] }
        let themeWords = words.filter { $0.category == theme }.sorted { $0.createdAt < $1.createdAt }

        let reviews = themeWords
            .flatMap { word in
                word.schedules.compactMap { area, state -> (item: StudyItem, due: Date)? in
                    !state.isNew && state.isDue(at: now) ? (StudyItem(wordID: word.id, area: area), state.dueDate) : nil
                }
            }
            .sorted { $0.due < $1.due }
            .prefix(reviewLimit)
            .map { $0.item }

        var fresh: [StudyItem] = []
        for word in themeWords {
            let translationKnown = word.level(in: .translation) >= 1
            for area in StudyArea.allCases {
                guard let state = word.schedules[area], state.isNew else { continue }
                if area != .translation && !translationKnown { continue }
                fresh.append(StudyItem(wordID: word.id, area: area))
            }
        }
        return Array(reviews) + fresh.prefix(newLimit)
    }

    /// Mixed review of everything already seen, across themes and areas:
    /// overdue first, then the most missed, then the closest to being due; shuffled.
    public static func bonus<R: RandomNumberGenerator>(
        _ words: [PathWord],
        now: Date,
        limit: Int,
        excluding excluded: Set<StudyItem> = [],
        using rng: inout R
    ) -> [StudyItem] {
        let seen = words.flatMap { word in
            word.schedules.compactMap { area, state -> (item: StudyItem, state: SRSState)? in
                let item = StudyItem(wordID: word.id, area: area)
                return state.isNew || excluded.contains(item) ? nil : (item, state)
            }
        }
        let ranked = seen.sorted { lhs, rhs in
            let lhsDue = lhs.state.isDue(at: now), rhsDue = rhs.state.isDue(at: now)
            if lhsDue != rhsDue { return lhsDue }
            if lhsDue { return lhs.state.dueDate < rhs.state.dueDate }
            if lhs.state.lapses != rhs.state.lapses { return lhs.state.lapses > rhs.state.lapses }
            return lhs.state.dueDate < rhs.state.dueDate
        }
        return ranked.prefix(limit).map { $0.item }.shuffled(using: &rng)
    }

    public static func bonus(_ words: [PathWord], now: Date, limit: Int, excluding excluded: Set<StudyItem> = []) -> [StudyItem] {
        var rng = SystemRandomNumberGenerator()
        return bonus(words, now: now, limit: limit, excluding: excluded, using: &rng)
    }

    /// From recognising to producing, by the word's level in the area: multiple choice
    /// for new or just-missed words, then typing, then typing or speaking with an
    /// occasional multiple choice.
    public static func kind<R: RandomNumberGenerator>(
        level: Int,
        area: StudyArea,
        allowSpeaking: Bool,
        using rng: inout R
    ) -> ExerciseKind {
        let typing: [ExerciseKind] = area == .translation ? [.typeGerman, .typeEnglish] : [.typeGerman]
        switch level {
        case ...0:
            return .multipleChoice
        case 1:
            return typing.randomElement(using: &rng) ?? .typeGerman
        default:
            var kinds = typing + [.multipleChoice]
            if allowSpeaking { kinds.append(.speakGerman) }
            return kinds.randomElement(using: &rng) ?? .typeGerman
        }
    }
}
