import XCTest
@testable import LearnCore

final class BackupTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_780_000_000)

    private func word(_ german: String, article: Article? = .der, updatedAt: Date, reviewed: Date? = nil, id: UUID = UUID()) -> BackupWord {
        var srs = SRSState.new(now: base)
        srs.lastReviewed = reviewed
        return BackupWord(
            entry: VocabEntry(id: id, german: german, article: article, english: ["x"], partOfSpeech: .noun),
            createdAt: base,
            updatedAt: updatedAt,
            srs: srs
        )
    }

    func testRoundTrip() throws {
        let original = Backup(exportedAt: base, words: [word("Tisch", updatedAt: base, reviewed: base.addingTimeInterval(60))])
        let decoded = try BackupCodec.decode(BackupCodec.encode(original))
        XCTAssertEqual(decoded.schemaVersion, Backup.currentSchemaVersion)
        XCTAssertEqual(decoded.words, original.words)
    }

    func testRoundTripKeepsAllSchedulesAndCategory() throws {
        var article = SRSState.new(now: base)
        article.lastReviewed = base.addingTimeInterval(30)
        let original = BackupWord(
            entry: VocabEntry(german: "Brot", article: .das, plural: "Brote", english: ["bread"], partOfSpeech: .noun, category: "Cibo"),
            createdAt: base,
            updatedAt: base,
            srs: .new(now: base),
            articleSrs: article
        )
        let decoded = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: base, words: [original])))
        XCTAssertEqual(decoded.words.first?.category, "Cibo")
        XCTAssertEqual(decoded.words.first?.articleSrs, article)
        XCTAssertEqual(decoded.words.first?.lastActivity, base.addingTimeInterval(30))
    }

    func testDecodesSchemaV1() throws {
        let v1 = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-05-28T20:26:40Z",
          "words": [{
            "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "german": "Tisch", "article": "der", "plural": "Tische",
            "english": ["table"], "partOfSpeech": "noun", "emoji": "🪑",
            "createdAt": "2026-05-28T20:26:40Z", "updatedAt": "2026-05-28T20:26:40Z",
            "srs": {"ease": 2.5, "intervalDays": 3, "repetitions": 2, "lapses": 0,
                    "dueDate": "2026-05-31T00:00:00Z", "lastReviewed": "2026-05-28T20:26:40Z"},
            "timesCorrect": 2, "timesWrong": 0
          }]
        }
        """
        let backup = try BackupCodec.decode(Data(v1.utf8))
        let word = try XCTUnwrap(backup.words.first)
        XCTAssertEqual(word.category, VocabEntry.defaultCategory)
        XCTAssertEqual(word.srs.repetitions, 2)
        XCTAssertTrue(word.articleSrs.isNew)
        XCTAssertTrue(word.pluralSrs.isNew)        XCTAssertNil(word.streak(for: .translation))
    }

    func testRoundTripKeepsStreaks() throws {
        let original = BackupWord(
            entry: VocabEntry(german: "Brot", article: .das, plural: "Brote", english: ["bread"], partOfSpeech: .noun),
            createdAt: base,
            updatedAt: base,
            srs: .new(now: base),
            streaks: [.translation: 3, .article: 0],
            kindStreaks: [.article: [.multipleChoice: 2, .speakGerman: 1]]
        )
        let decoded = try XCTUnwrap(BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: base, words: [original]))).words.first)
        XCTAssertEqual(decoded.streak(for: .translation), 3)
        XCTAssertEqual(decoded.streak(for: .article), 0)
        XCTAssertNil(decoded.streak(for: .plural))
        XCTAssertEqual(decoded.streak(for: .article, kind: .multipleChoice), 2)
        XCTAssertEqual(decoded.streak(for: .article, kind: .speakGerman), 1)
        XCTAssertNil(decoded.streak(for: .article, kind: .typeGerman))
    }

    func testRejectsFutureVersion() throws {
        let future = Backup(schemaVersion: 99, exportedAt: base, words: [])
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encode(future))) { error in
            XCTAssertEqual(error as? BackupCodec.CodecError, .unsupportedVersion(99))
        }
    }

    func testMerge() {
        let sharedID = UUID()
        let existing = [
            word("Tisch", updatedAt: base, id: sharedID),
            word("Stuhl", updatedAt: base, reviewed: base.addingTimeInterval(500)),
        ]
        let incoming = [
            // Same id, newer: update.
            word("Tisch", updatedAt: base.addingTimeInterval(100), id: sharedID),
            // Same word under another id, older: skipped.
            word("Stuhl", updatedAt: base.addingTimeInterval(100)),
            // New word.
            word("Lampe", article: .die, updatedAt: base),
            // Duplicate inside the file.
            word("Lampe", article: .die, updatedAt: base),
            // Same spelling, different article: a different word.
            word("Tisch", article: .das, updatedAt: base),
        ]
        let result = BackupMerger.merge(existing: existing, incoming: incoming)
        XCTAssertEqual(result.updates.map(\.id), [sharedID])
        XCTAssertEqual(result.inserts.map(\.german), ["Lampe", "Tisch"])
        XCTAssertEqual(result.skipped, 2)
    }

    func testMergeByKeyKeepsExistingID() {
        let existingWord = word("Tisch", updatedAt: base)
        let newer = word("tisch", updatedAt: base.addingTimeInterval(10))
        let result = BackupMerger.merge(existing: [existingWord], incoming: [newer])
        XCTAssertEqual(result.updates.first?.id, existingWord.id)
    }
}
