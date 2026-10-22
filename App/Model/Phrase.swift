import Foundation
import LearnCore
import SwiftData

/// A sentence or idiom to learn, with its review schedule and progress.
@Model
final class Phrase {
    @Attribute(.unique) var id: UUID
    var german: String
    var variants: [String]
    var english: String
    var response: String?
    var note: String?
    var kindRaw: String
    var category: String
    var emoji: String
    var createdAt: Date
    var updatedAt: Date

    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var lapses: Int
    var dueDate: Date
    var lastReviewed: Date?

    /// Right answers in a row, any kind of exercise: drives the automatic kind.
    var streak: Int = 0
    /// Right answers in a row per kind of exercise, as JSON {"reorder": 2}: the percentages.
    var kindStreaksJSON: String = ""

    init(entry: PhraseEntry, now: Date = .now) {
        id = entry.id
        german = entry.german
        variants = entry.variants
        english = entry.english
        response = entry.response
        note = entry.note
        kindRaw = entry.kind.rawValue
        category = entry.category
        emoji = entry.emoji
        createdAt = now
        updatedAt = now
        let fresh = SRSState.new(now: now)
        ease = fresh.ease
        intervalDays = fresh.intervalDays
        repetitions = fresh.repetitions
        lapses = fresh.lapses
        dueDate = fresh.dueDate
        lastReviewed = fresh.lastReviewed
    }

    init(backup: BackupPhrase) {
        id = backup.id
        german = backup.german
        variants = backup.variants
        english = backup.english
        response = backup.response
        note = backup.note
        kindRaw = backup.kind.rawValue
        category = backup.category
        emoji = backup.emoji
        createdAt = backup.createdAt
        updatedAt = backup.updatedAt
        ease = backup.srs.ease
        intervalDays = backup.srs.intervalDays
        repetitions = backup.srs.repetitions
        lapses = backup.srs.lapses
        dueDate = backup.srs.dueDate
        lastReviewed = backup.srs.lastReviewed
        streak = backup.streak
        kindStreaks = backup.streaksByKind
    }

    var kind: PhraseKind {
        get { PhraseKind(rawValue: kindRaw) ?? .sentence }
        set { kindRaw = newValue.rawValue }
    }

    var entry: PhraseEntry {
        PhraseEntry(id: id, german: german, variants: variants, english: english, response: response,
                    note: note, kind: kind, category: category, emoji: emoji)
    }

    var dedupeKey: String { entry.dedupeKey }

    var srs: SRSState {
        get {
            SRSState(ease: ease, intervalDays: intervalDays, repetitions: repetitions, lapses: lapses,
                     dueDate: dueDate, lastReviewed: lastReviewed)
        }
        set {
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            dueDate = newValue.dueDate
            lastReviewed = newValue.lastReviewed
        }
    }

    var isDue: Bool { dueDate <= .now }

    var candidate: StudyCandidate { StudyCandidate(id: id, srs: srs, createdAt: createdAt) }

    var kindStreaks: [PhraseExerciseKind: Int] {
        get {
            guard let data = kindStreaksJSON.data(using: .utf8),
                  let flat = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            var result: [PhraseExerciseKind: Int] = [:]
            for (key, value) in flat {
                if let kind = PhraseExerciseKind(rawValue: key) { result[kind] = value }
            }
            return result
        }
        set {
            let flat = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            let data = (try? JSONEncoder().encode(flat)) ?? Data()
            kindStreaksJSON = String(decoding: data, as: UTF8.self)
        }
    }

    /// For progress: the entry with its per-kind streaks.
    var progressInput: (entry: PhraseEntry, streaks: [PhraseExerciseKind: Int]) { (entry, kindStreaks) }

    var backup: BackupPhrase {
        BackupPhrase(entry: entry, createdAt: createdAt, updatedAt: updatedAt, srs: srs,
                     streak: streak, kindStreaks: kindStreaks)
    }

    func update(from entry: PhraseEntry) {
        german = entry.german
        variants = entry.variants
        english = entry.english
        response = entry.response
        note = entry.note
        kind = entry.kind
        category = entry.category
        emoji = entry.emoji
        updatedAt = .now
    }

    func apply(_ backup: BackupPhrase) {
        update(from: backup.entry)
        createdAt = min(createdAt, backup.createdAt)
        updatedAt = backup.updatedAt
        srs = backup.srs
        streak = backup.streak
        kindStreaks = backup.streaksByKind
    }
}

extension Array where Element == Phrase {
    /// Distinct phrase categories, alphabetical, the default one last.
    var categories: [String] {
        Set(map(\.category)).sorted { lhs, rhs in
            if lhs == PhraseEntry.defaultCategory { return false }
            if rhs == PhraseEntry.defaultCategory { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}
