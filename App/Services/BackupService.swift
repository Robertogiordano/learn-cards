import Foundation
import LearnCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PendingImport: Identifiable {
    let id = UUID()
    let backup: Backup
    let merge: MergeResult
    let phraseMerge: PhraseMergeResult
    let verbMerge: VerbMergeResult

    /// New and updated items: words, phrases and verbs together.
    var newCount: Int { merge.inserts.count + phraseMerge.inserts.count + verbMerge.inserts.count }
    var updatedCount: Int { merge.updates.count + phraseMerge.updates.count + verbMerge.updates.count }
    var phraseCount: Int { backup.phrases?.count ?? 0 }
    var verbCount: Int { backup.verbs?.count ?? 0 }
}

enum BackupService {
    @MainActor
    static func exportData(words: [Word], phrases: [Phrase], verbs: [Verb]) throws -> Data {
        let numbers = NumberStatsStore.shared.stats
        return try BackupCodec.encode(Backup(exportedAt: .now, words: words.map(\.backup),
                                             numbers: numbers.isEmpty ? nil : numbers,
                                             phrases: phrases.map(\.backup),
                                             verbs: verbs.map(\.backup)))
    }

    static func defaultFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "learncards-backup-\(formatter.string(from: date))"
    }

    static func prepareImport(from url: URL, existing: [Word], existingPhrases: [Phrase],
                              existingVerbs: [Verb]) throws -> PendingImport {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let backup = try BackupCodec.decode(Data(contentsOf: url))
        let merge = BackupMerger.merge(existing: existing.map(\.backup), incoming: backup.words)
        let phraseMerge = BackupPhraseMerger.merge(existing: existingPhrases.map(\.backup), incoming: backup.phrases ?? [])
        let verbMerge = BackupVerbMerger.merge(existing: existingVerbs.map(\.backup), incoming: backup.verbs ?? [])
        return PendingImport(backup: backup, merge: merge, phraseMerge: phraseMerge, verbMerge: verbMerge)
    }

    /// Number history is taken from the backup only when there is none on this phone.
    @MainActor
    static func applyMerge(_ pending: PendingImport, existing: [Word], existingPhrases: [Phrase],
                           existingVerbs: [Verb], context: ModelContext) throws {
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for word in pending.merge.updates {
            byID[word.id]?.apply(word)
        }
        for word in pending.merge.inserts {
            context.insert(Word(backup: word))
        }
        let phrasesByID = Dictionary(existingPhrases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for phrase in pending.phraseMerge.updates {
            phrasesByID[phrase.id]?.apply(phrase)
        }
        for phrase in pending.phraseMerge.inserts {
            context.insert(Phrase(backup: phrase))
        }
        let verbsByID = Dictionary(existingVerbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for verb in pending.verbMerge.updates {
            verbsByID[verb.id]?.apply(verb)
        }
        for verb in pending.verbMerge.inserts {
            context.insert(Verb(backup: verb))
        }
        try context.save()
        if let numbers = pending.backup.numbers, NumberStatsStore.shared.stats.isEmpty {
            NumberStatsStore.shared.replace(with: numbers)
        }
    }

    @MainActor
    static func replaceAll(with backup: Backup, existing: [Word], existingPhrases: [Phrase],
                           existingVerbs: [Verb], context: ModelContext) throws {
        for word in existing {
            context.delete(word)
        }
        for phrase in existingPhrases {
            context.delete(phrase)
        }
        for verb in existingVerbs {
            context.delete(verb)
        }
        try context.save()
        // Merging into nothing drops duplicates inside the file.
        for word in BackupMerger.merge(existing: [], incoming: backup.words).inserts {
            context.insert(Word(backup: word))
        }
        for phrase in BackupPhraseMerger.merge(existing: [], incoming: backup.phrases ?? []).inserts {
            context.insert(Phrase(backup: phrase))
        }
        for verb in BackupVerbMerger.merge(existing: [], incoming: backup.verbs ?? []).inserts {
            context.insert(Verb(backup: verb))
        }
        try context.save()
        NumberStatsStore.shared.replace(with: backup.numbers ?? NumberStats())
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
