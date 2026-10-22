import Foundation
import LearnCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct PendingImport: Identifiable {
    let id = UUID()
    let backup: Backup
    let merge: MergeResult
}

enum BackupService {
    @MainActor
    static func exportData(words: [Word]) throws -> Data {
        let numbers = NumberStatsStore.shared.stats
        return try BackupCodec.encode(Backup(exportedAt: .now, words: words.map(\.backup),
                                             numbers: numbers.isEmpty ? nil : numbers))
    }

    static func defaultFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "learncards-backup-\(formatter.string(from: date))"
    }

    static func prepareImport(from url: URL, existing: [Word]) throws -> PendingImport {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
        let backup = try BackupCodec.decode(Data(contentsOf: url))
        let merge = BackupMerger.merge(existing: existing.map(\.backup), incoming: backup.words)
        return PendingImport(backup: backup, merge: merge)
    }

    /// Number history is taken from the backup only when there is none on this phone.
    @MainActor
    static func applyMerge(_ pending: PendingImport, existing: [Word], context: ModelContext) throws {
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for word in pending.merge.updates {
            byID[word.id]?.apply(word)
        }
        for word in pending.merge.inserts {
            context.insert(Word(backup: word))
        }
        try context.save()
        if let numbers = pending.backup.numbers, NumberStatsStore.shared.stats.isEmpty {
            NumberStatsStore.shared.replace(with: numbers)
        }
    }

    @MainActor
    static func replaceAll(with backup: Backup, existing: [Word], context: ModelContext) throws {
        for word in existing {
            context.delete(word)
        }
        try context.save()
        // Merging into nothing drops duplicates inside the file.
        for word in BackupMerger.merge(existing: [], incoming: backup.words).inserts {
            context.insert(Word(backup: word))
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
