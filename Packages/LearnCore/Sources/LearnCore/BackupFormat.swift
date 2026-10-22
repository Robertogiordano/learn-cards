import Foundation

/// A word as written in a backup file: the vocabulary entry plus its learning history.
public struct BackupWord: Codable, Hashable, Sendable {
    public var id: UUID
    public var german: String
    public var article: Article?
    public var plural: String?
    public var english: [String]
    public var partOfSpeech: PartOfSpeech
    public var emoji: String
    public var createdAt: Date
    public var updatedAt: Date
    public var srs: SRSState
    public var timesCorrect: Int
    public var timesWrong: Int

    public init(
        entry: VocabEntry,
        createdAt: Date,
        updatedAt: Date,
        srs: SRSState,
        timesCorrect: Int = 0,
        timesWrong: Int = 0
    ) {
        id = entry.id
        german = entry.german
        article = entry.article
        plural = entry.plural
        english = entry.english
        partOfSpeech = entry.partOfSpeech
        emoji = entry.emoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.timesCorrect = timesCorrect
        self.timesWrong = timesWrong
    }

    public var entry: VocabEntry {
        VocabEntry(id: id, german: german, article: article, plural: plural, english: english,
                   partOfSpeech: partOfSpeech, emoji: emoji)
    }

    public var dedupeKey: String { VocabEntry.dedupeKey(german: german, article: article) }

    /// Most recent edit or review: decides which copy wins when merging.
    public var lastActivity: Date { max(updatedAt, srs.lastReviewed ?? .distantPast) }
}

public struct Backup: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var exportedAt: Date
    public var words: [BackupWord]

    public init(schemaVersion: Int = Backup.currentSchemaVersion, exportedAt: Date, words: [BackupWord]) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.words = words
    }
}

public enum BackupCodec {
    public enum CodecError: LocalizedError, Equatable {
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Questo backup (versione \(version)) è stato creato da una versione più recente dell'app."
            }
        }
    }

    public static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    public static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: data)
        guard backup.schemaVersion <= Backup.currentSchemaVersion else {
            throw CodecError.unsupportedVersion(backup.schemaVersion)
        }
        return backup
    }
}

public struct MergeResult: Sendable {
    /// Words not present yet.
    public var inserts: [BackupWord]
    /// Newer copies of existing words, already carrying the existing word's id.
    public var updates: [BackupWord]
    /// Incoming words that were older, identical or duplicated within the file.
    public var skipped: Int
}

public enum BackupMerger {
    /// Matches by id first, then by German word + article; the copy with the latest activity wins.
    public static func merge(existing: [BackupWord], incoming: [BackupWord]) -> MergeResult {
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(existing.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
        var result = MergeResult(inserts: [], updates: [], skipped: 0)
        var seenKeys = Set<String>()

        for var word in incoming {
            guard seenKeys.insert(word.dedupeKey).inserted else {
                result.skipped += 1
                continue
            }
            if let match = byID[word.id] ?? byKey[word.dedupeKey] {
                if word.lastActivity > match.lastActivity {
                    word.id = match.id
                    result.updates.append(word)
                } else {
                    result.skipped += 1
                }
            } else {
                result.inserts.append(word)
            }
        }
        return result
    }
}
