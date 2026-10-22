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
    public var category: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Translation schedule (the only one in schema v1).
    public var srs: SRSState
    public var articleSrs: SRSState
    public var pluralSrs: SRSState
    /// Right answers in a row per area (keyed by `StudyArea.rawValue`), which drive the
    /// path's percentages. Absent in older backups: the schedules' repetitions stand in.
    public var streaks: [String: Int]
    public var timesCorrect: Int
    public var timesWrong: Int

    public init(
        entry: VocabEntry,
        createdAt: Date,
        updatedAt: Date,
        srs: SRSState,
        articleSrs: SRSState? = nil,
        pluralSrs: SRSState? = nil,
        streaks: [StudyArea: Int] = [:],
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
        category = entry.category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.articleSrs = articleSrs ?? .new(now: createdAt)
        self.pluralSrs = pluralSrs ?? .new(now: createdAt)
        self.streaks = Dictionary(uniqueKeysWithValues: streaks.map { ($0.key.rawValue, $0.value) })
        self.timesCorrect = timesCorrect
        self.timesWrong = timesWrong
    }

    enum CodingKeys: String, CodingKey {
        case id, german, article, plural, english, partOfSpeech, emoji, category
        case createdAt, updatedAt, srs, articleSrs, pluralSrs, streaks, timesCorrect, timesWrong
    }

    /// Fields added in schema v2 are optional so v1 backups still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        german = try container.decode(String.self, forKey: .german)
        article = try container.decodeIfPresent(Article.self, forKey: .article)
        plural = try container.decodeIfPresent(String.self, forKey: .plural)
        english = try container.decode([String].self, forKey: .english)
        partOfSpeech = try container.decode(PartOfSpeech.self, forKey: .partOfSpeech)
        emoji = try container.decode(String.self, forKey: .emoji)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? VocabEntry.defaultCategory
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        srs = try container.decode(SRSState.self, forKey: .srs)
        articleSrs = try container.decodeIfPresent(SRSState.self, forKey: .articleSrs) ?? .new(now: createdAt)
        pluralSrs = try container.decodeIfPresent(SRSState.self, forKey: .pluralSrs) ?? .new(now: createdAt)
        streaks = try container.decodeIfPresent([String: Int].self, forKey: .streaks) ?? [:]
        timesCorrect = try container.decodeIfPresent(Int.self, forKey: .timesCorrect) ?? 0
        timesWrong = try container.decodeIfPresent(Int.self, forKey: .timesWrong) ?? 0
    }

    public var entry: VocabEntry {
        VocabEntry(id: id, german: german, article: article, plural: plural, english: english,
                   partOfSpeech: partOfSpeech, emoji: emoji, category: category)
    }

    public var dedupeKey: String { VocabEntry.dedupeKey(german: german, article: article) }

    /// Right answers in a row in an area, nil when the backup does not know it.
    public func streak(for area: StudyArea) -> Int? {
        streaks[area.rawValue]
    }

    /// Most recent edit or review in any area: decides which copy wins when merging.
    public var lastActivity: Date {
        [updatedAt, srs.lastReviewed, articleSrs.lastReviewed, pluralSrs.lastReviewed]
            .compactMap { $0 }
            .max() ?? updatedAt
    }
}

public struct Backup: Codable, Sendable {
    public static let currentSchemaVersion = 2

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
