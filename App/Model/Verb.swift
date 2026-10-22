import Foundation
import LearnCore
import SwiftData

/// A verb with its present tense, review schedule and progress.
@Model
final class Verb {
    @Attribute(.unique) var id: UUID
    var infinitive: String
    var english: String
    /// Present tense in `Person` order.
    var forms: [String]
    var groupRaw: String
    var note: String?
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
    /// Right answers in a row per kind of exercise, as JSON {"typeForm": 2}: the percentages.
    var kindStreaksJSON: String = ""

    init(entry: VerbEntry, now: Date = .now) {
        id = entry.id
        infinitive = entry.infinitive
        english = entry.english
        forms = entry.forms
        groupRaw = entry.group.rawValue
        note = entry.note
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

    init(backup: BackupVerb) {
        id = backup.id
        infinitive = backup.infinitive
        english = backup.english
        forms = backup.forms
        groupRaw = backup.group.rawValue
        note = backup.note
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

    var group: VerbGroup {
        get { VerbGroup(rawValue: groupRaw) ?? .regular }
        set { groupRaw = newValue.rawValue }
    }

    var entry: VerbEntry {
        VerbEntry(id: id, infinitive: infinitive, english: english, forms: forms, group: group, note: note, emoji: emoji)
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

    /// `kind` is the exercise being trained; nil weighs the verb as a whole.
    func candidate(for kind: VerbExerciseKind? = nil) -> StudyCandidate {
        let level = kind.map { kindStreaks[$0] ?? 0 } ?? streak
        return StudyCandidate(id: id, srs: srs, createdAt: createdAt, level: level)
    }

    var kindStreaks: [VerbExerciseKind: Int] {
        get {
            guard let data = kindStreaksJSON.data(using: .utf8),
                  let flat = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
            var result: [VerbExerciseKind: Int] = [:]
            for (key, value) in flat {
                if let kind = VerbExerciseKind(rawValue: key) { result[kind] = value }
            }
            return result
        }
        set {
            let flat = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            let data = (try? JSONEncoder().encode(flat)) ?? Data()
            kindStreaksJSON = String(decoding: data, as: UTF8.self)
        }
    }

    var backup: BackupVerb {
        BackupVerb(entry: entry, createdAt: createdAt, updatedAt: updatedAt, srs: srs,
                   streak: streak, kindStreaks: kindStreaks)
    }

    func update(from entry: VerbEntry) {
        infinitive = entry.infinitive
        english = entry.english
        forms = entry.forms
        group = entry.group
        note = entry.note
        emoji = entry.emoji
        updatedAt = .now
    }

    func apply(_ backup: BackupVerb) {
        update(from: backup.entry)
        createdAt = min(createdAt, backup.createdAt)
        updatedAt = backup.updatedAt
        srs = backup.srs
        streak = backup.streak
        kindStreaks = backup.streaksByKind
    }
}

extension Array where Element == Verb {
    /// Groups present in the list, in the order of `VerbGroup`.
    var groups: [VerbGroup] {
        let present = Set(map(\.group))
        return VerbGroup.allCases.filter { present.contains($0) }
    }
}
