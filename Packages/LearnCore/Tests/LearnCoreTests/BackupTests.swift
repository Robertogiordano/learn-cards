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
