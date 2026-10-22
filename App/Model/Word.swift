import Foundation
import LearnCore
import SwiftData

/// A word in the vocabulary, with its spaced-repetition state.
@Model
final class Word {
    @Attribute(.unique) var id: UUID
    var german: String
    var articleRaw: String?
    var plural: String?
    var english: [String]
    var partOfSpeechRaw: String
    var emoji: String
    var createdAt: Date
    var updatedAt: Date

    var ease: Double
    var intervalDays: Double
    var repetitions: Int
    var lapses: Int
    var dueDate: Date
    var lastReviewed: Date?
    var timesCorrect: Int
    var timesWrong: Int

    init(entry: VocabEntry, now: Date = .now) {
        let srs = SRSState.new(now: now)
        id = entry.id
        german = entry.german
        articleRaw = entry.article?.rawValue
        plural = entry.plural
        english = entry.english
        partOfSpeechRaw = entry.partOfSpeech.rawValue
        emoji = entry.emoji
        createdAt = now
        updatedAt = now
        ease = srs.ease
        intervalDays = srs.intervalDays
        repetitions = srs.repetitions
        lapses = srs.lapses
        dueDate = srs.dueDate
        lastReviewed = srs.lastReviewed
        timesCorrect = 0
        timesWrong = 0
    }

    init(backup: BackupWord) {
        id = backup.id
        german = backup.german
        articleRaw = backup.article?.rawValue
        plural = backup.plural
        english = backup.english
        partOfSpeechRaw = backup.partOfSpeech.rawValue
        emoji = backup.emoji
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
                   partOfSpeech: partOfSpeech, emoji: emoji)
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

    var backup: BackupWord {
        BackupWord(entry: entry, createdAt: createdAt, updatedAt: updatedAt, srs: srs,
                   timesCorrect: timesCorrect, timesWrong: timesWrong)
    }

    /// Edits the vocabulary fields, keeping identity and learning history.
    func update(from entry: VocabEntry) {
        german = entry.german
        article = entry.article
        plural = entry.plural
        english = entry.english
        partOfSpeech = entry.partOfSpeech
        emoji = entry.emoji
        updatedAt = .now
    }

    /// Takes everything from a newer backup copy except the identity.
    func apply(_ backup: BackupWord) {
        german = backup.german
        article = backup.article
        plural = backup.plural
        english = backup.english
        partOfSpeech = backup.partOfSpeech
        emoji = backup.emoji
        createdAt = min(createdAt, backup.createdAt)
        updatedAt = backup.updatedAt
        srs = backup.srs
        timesCorrect = backup.timesCorrect
        timesWrong = backup.timesWrong
    }
}
