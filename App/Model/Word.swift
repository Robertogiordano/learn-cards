import Foundation
import LearnCore
import SwiftData

/// A word in the vocabulary, with one spaced-repetition schedule per study area.
@Model
final class Word {
    @Attribute(.unique) var id: UUID
    var german: String
    var articleRaw: String?
    var plural: String?
    var english: [String]
    var partOfSpeechRaw: String
    var emoji: String
    // Added in v2: defaults let SwiftData migrate existing stores automatically.
    var category: String = "Misc"
    var createdAt: Date
    var updatedAt: Date

    // Translation schedule (the only one in v1, hence the unprefixed names).
    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var lapses: Int
    var dueDate: Date
    var lastReviewed: Date?

    var articleEase: Double = 2.5
    var articleIntervalDays: Double = 0
    var articleRepetitions: Int = 0
    var articleLapses: Int = 0
    var articleDueDate: Date = Date.distantPast
    var articleLastReviewed: Date? = nil

    var pluralEase: Double = 2.5
    var pluralIntervalDays: Double = 0
    var pluralRepetitions: Int = 0
    var pluralLapses: Int = 0
    var pluralDueDate: Date = Date.distantPast
    var pluralLastReviewed: Date? = nil

    // Correct answers in a row per area, counting practice too: drives the path's
    // percentages and stars. -1 means "not tracked yet" (stores created before v3),
    // in which case the schedule's repetitions stand in.
    var translationStreak: Int = -1
    var articleStreak: Int = -1
    var pluralStreak: Int = -1
    /// Right answers in a row per area and kind of exercise, as JSON {"article.multipleChoice": 2}:
    /// the path's percentages. Empty for words never practised that way.
    var kindStreaksJSON: String = ""

    var timesCorrect: Int
    var timesWrong: Int

    init(entry: VocabEntry, now: Date = .now) {
        id = entry.id
        german = entry.german
        articleRaw = entry.article?.rawValue
        plural = entry.plural
        english = entry.english
        partOfSpeechRaw = entry.partOfSpeech.rawValue
        emoji = entry.emoji
        category = entry.category
        createdAt = now
        updatedAt = now
        let fresh = SRSState.new(now: now)
        ease = fresh.ease
        intervalDays = fresh.intervalDays
        repetitions = fresh.repetitions
        lapses = fresh.lapses
        dueDate = fresh.dueDate
        lastReviewed = fresh.lastReviewed
        timesCorrect = 0
        timesWrong = 0
        setSRS(fresh, for: .article)
        setSRS(fresh, for: .plural)
    }

    init(backup: BackupWord) {
        id = backup.id
        german = backup.german
        articleRaw = backup.article?.rawValue
        plural = backup.plural
        english = backup.english
        partOfSpeechRaw = backup.partOfSpeech.rawValue
        emoji = backup.emoji
        category = backup.category
        createdAt = backup.createdAt
        updatedAt = backup.updatedAt
        ease = backup.srs.ease
        intervalDays = backup.srs.intervalDays
        repetitions = backup.srs.repetitions
        lapses = backup.srs.lapses
        dueDate = backup.srs.dueDate
        lastReviewed = backup.srs.lastReviewed
        timesCorrect = backup.timesCorrect
        timesWrong = backup.timesWrong
        setSRS(backup.articleSrs, for: .article)
        setSRS(backup.pluralSrs, for: .plural)
        applyStreaks(from: backup)
    }

    var article: Article? {
        get { articleRaw.flatMap(Article.init(rawValue:)) }
        set { articleRaw = newValue?.rawValue }
    }

    var partOfSpeech: PartOfSpeech {
        get { PartOfSpeech(rawValue: partOfSpeechRaw) ?? .other }
        set { partOfSpeechRaw = newValue.rawValue }
    }

    var entry: VocabEntry {
        VocabEntry(id: id, german: german, article: article, plural: plural, english: english,
                   partOfSpeech: partOfSpeech, emoji: emoji, category: category)
    }

    var dedupeKey: String { entry.dedupeKey }

    func srs(for area: StudyArea) -> SRSState {
        switch area {
        case .translation:
            return SRSState(ease: ease, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses,
                            dueDate: dueDate, lastReviewed: lastReviewed)
        case .article:
            return SRSState(ease: articleEase, intervalDays: articleIntervalDays, repetitions: articleRepetitions,
                            lapses: articleLapses, dueDate: articleDueDate, lastReviewed: articleLastReviewed)
        case .plural:
            return SRSState(ease: pluralEase, intervalDays: pluralIntervalDays, repetitions: pluralRepetitions,
                            lapses: pluralLapses, dueDate: pluralDueDate, lastReviewed: pluralLastReviewed)
        }
    }

    func setSRS(_ state: SRSState, for area: StudyArea) {
        switch area {
        case .translation:
            ease = state.ease
            intervalDays = state.intervalDays
            repetitions = state.repetitions
            lapses = state.lapses
            dueDate = state.dueDate
            lastReviewed = state.lastReviewed
        case .article:
            articleEase = state.ease
            articleIntervalDays = state.intervalDays
            articleRepetitions = state.repetitions
            articleLapses = state.lapses
            articleDueDate = state.dueDate
            articleLastReviewed = state.lastReviewed
        case .plural:
            pluralEase = state.ease
            pluralIntervalDays = state.intervalDays
            pluralRepetitions = state.repetitions
            pluralLapses = state.lapses
            pluralDueDate = state.dueDate
            pluralLastReviewed = state.lastReviewed
        }
    }

    func isApplicable(to area: StudyArea) -> Bool { area.isApplicable(to: entry) }

    /// Correct answers in a row in an area (falls back to the schedule for older data).
    func streak(for area: StudyArea) -> Int {
        let stored: Int
        switch area {
        case .translation: stored = translationStreak
        case .article: stored = articleStreak
        case .plural: stored = pluralStreak
        }
        return stored >= 0 ? stored : srs(for: area).repetitions
    }

    var kindStreaks: [StudyArea: [ExerciseKind: Int]] {
        get {
            guard let data = kindStreaksJSON.data(using: .utf8),
                  let flat = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            var result: [StudyArea: [ExerciseKind: Int]] = [:]
            for (key, value) in flat {
                let parts = key.split(separator: ".").map(String.init)
                guard parts.count == 2, let area = StudyArea(rawValue: parts[0]),
                      let kind = ExerciseKind(rawValue: parts[1]) else { continue }
                result[area, default: [:]][kind] = value
            }
            return result
        }
        set {
            var flat: [String: Int] = [:]
            for (area, kinds) in newValue {
                for (kind, value) in kinds {
                    flat["\(area.rawValue).\(kind.rawValue)"] = value
                }
            }
            let data = (try? JSONEncoder().encode(flat)) ?? Data()
            kindStreaksJSON = String(decoding: data, as: UTF8.self)
        }
    }

    func kindStreak(for area: StudyArea, kind: ExerciseKind) -> Int {
        kindStreaks[area]?[kind] ?? 0
    }

    func setKindStreak(_ value: Int, for area: StudyArea, kind: ExerciseKind) {
        var streaks = kindStreaks
        streaks[area, default: [:]][kind] = value
        kindStreaks = streaks
    }

    func setStreak(_ value: Int, for area: StudyArea) {
        switch area {
        case .translation: translationStreak = value
        case .article: articleStreak = value
        case .plural: pluralStreak = value
        }
    }

    /// Due in an area the word takes part in.
    func isDue(in area: StudyArea, now: Date = .now) -> Bool {
        isApplicable(to: area) && srs(for: area).isDue(at: now)
    }

    /// Due in any area: drives the dot in the vocabulary list.
    var isDueAnywhere: Bool { StudyArea.allCases.contains { isDue(in: $0) } }

    /// `kind` is the exercise being trained; nil weighs the whole area.
    func candidate(for area: StudyArea, kind: ExerciseKind? = nil) -> StudyCandidate {
        let level = kind.map { kindStreak(for: area, kind: $0) } ?? streak(for: area)
        return StudyCandidate(id: id, srs: srs(for: area), createdAt: createdAt, level: level)
    }

    /// The word as the guided path sees it: one schedule per area it takes part in.
    var pathWord: PathWord {
        var schedules: [StudyArea: SRSState] = [:]
        var streaks: [StudyArea: Int] = [:]
        for area in StudyArea.allCases where isApplicable(to: area) {
            schedules[area] = srs(for: area)
            streaks[area] = streak(for: area)
        }
        return PathWord(id: id, category: category, createdAt: createdAt, schedules: schedules,
                        streaks: streaks, kindStreaks: kindStreaks)
    }

    var backup: BackupWord {
        BackupWord(entry: entry, createdAt: createdAt, updatedAt: updatedAt, srs: srs(for: .translation),
                   articleSrs: srs(for: .article), pluralSrs: srs(for: .plural),
                   streaks: trackedStreaks, kindStreaks: kindStreaks,
                   timesCorrect: timesCorrect, timesWrong: timesWrong)
    }

    /// Only streaks actually recorded; untracked ones stay out of the backup.
    private var trackedStreaks: [StudyArea: Int] {
        var streaks: [StudyArea: Int] = [:]
        for area in StudyArea.allCases {
            let stored: Int
            switch area {
            case .translation: stored = translationStreak
            case .article: stored = articleStreak
            case .plural: stored = pluralStreak
            }
            if stored >= 0 { streaks[area] = stored }
        }
        return streaks
    }

    /// Unknown streaks go back to "not tracked", so the schedules stand in.
    private func applyStreaks(from backup: BackupWord) {
        var kinds: [StudyArea: [ExerciseKind: Int]] = [:]
        for area in StudyArea.allCases {
            setStreak(backup.streak(for: area) ?? -1, for: area)
            for kind in area.kinds {
                if let value = backup.streak(for: area, kind: kind) {
                    kinds[area, default: [:]][kind] = value
                }
            }
        }
        kindStreaks = kinds
    }

    /// Edits the vocabulary fields, keeping identity and learning history.
    func update(from entry: VocabEntry) {
        german = entry.german
        article = entry.article
        plural = entry.plural
        english = entry.english
        partOfSpeech = entry.partOfSpeech
        emoji = entry.emoji
        category = entry.category
        updatedAt = .now
    }

    /// Takes everything from a newer backup copy except the identity.
    func apply(_ backup: BackupWord) {
        update(from: backup.entry)
        createdAt = min(createdAt, backup.createdAt)
        updatedAt = backup.updatedAt
        setSRS(backup.srs, for: .translation)
        setSRS(backup.articleSrs, for: .article)
        setSRS(backup.pluralSrs, for: .plural)
        applyStreaks(from: backup)
        timesCorrect = backup.timesCorrect
        timesWrong = backup.timesWrong
    }
}

extension Array where Element == Word {
    /// Distinct themes, alphabetical, with the catch-all theme last.
    var categories: [String] {
        Set(map(\.category)).sorted { lhs, rhs in
            if lhs == VocabEntry.defaultCategory { return false }
            if rhs == VocabEntry.defaultCategory { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}
