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
    static func exportData(words: [Word]) throws -> Data {
        try BackupCodec.encode(Backup(exportedAt: .now, words: words.map(\.backup)))
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

    static func applyMerge(_ merge: MergeResult, existing: [Word], context: ModelContext) throws {
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for word in merge.updates {
            byID[word.id]?.apply(word)
        }
        for word in merge.inserts {
            context.insert(Word(backup: word))
        }
        try context.save()
    }

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
