import XCTest
@testable import LearnCore

final class WordSetTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func word(level: Int?) -> PathWord {
        var srs = SRSState.new(now: now)
        if level != nil {
            srs.lastReviewed = now
            srs.repetitions = 2
        }
        return PathWord(id: UUID(), category: "Food", createdAt: now, schedules: [.translation: srs],
                        streaks: level.map { [.translation: $0] } ?? [:])
    }

    func testPickReturnsDistinctWords() {
        let words = (0..<15).map { _ in word(level: 1) }
        var rng = SeededGenerator(state: 7)
        let picked = WordSetPicker.pick(words, count: 10, using: &rng)
        XCTAssertEqual(picked.count, 10)
        XCTAssertEqual(Set(picked).count, 10)
        XCTAssertTrue(Set(picked).isSubset(of: words.map(\.id)))
        XCTAssertEqual(Set(WordSetPicker.pick(Array(words.prefix(4)), count: 10, using: &rng)).count, 4)
    }

    func testWeakWordsComeUpMoreOften() {
        let fresh = (0..<10).map { _ in word(level: nil) }
        let mastered = (0..<10).map { _ in word(level: 2) }
        let freshIDs = Set(fresh.map(\.id))
        XCTAssertEqual(WordSetPicker.weight(of: fresh[0]), 4)
        XCTAssertEqual(WordSetPicker.weight(of: mastered[0]), 1)

        var rng = SeededGenerator(state: 3)
        var freshCount = 0
        for _ in 0..<200 {
            freshCount += WordSetPicker.pick(fresh + mastered, count: 5, using: &rng).filter(freshIDs.contains).count
        }
        // Four times the weight: well over half of the picks.
        XCTAssertGreaterThan(freshCount, 200 * 5 * 6 / 10)
    }

    func testNextNameFillsGaps() {
        XCTAssertEqual(WordSetPicker.nextName(existing: []), "Set 1")
        XCTAssertEqual(WordSetPicker.nextName(existing: ["Set 1", "Set 3"]), "Set 2")
        XCTAssertEqual(WordSetPicker.nextName(existing: ["Set 1", "Verbs to fix"]), "Set 2")
    }

    func testBackupRoundTripAndMerge() throws {
        let set = WordSet(name: "Set 1", wordIDs: [UUID(), UUID()], createdAt: now)
        let decoded = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: now, words: [], wordSets: [set])))
        XCTAssertEqual(decoded.wordSets, [set])
        XCTAssertNil(try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: now, words: []))).wordSets)

        var renamed = set
        renamed.name = "Kitchen"
        let other = WordSet(name: "Set 2", wordIDs: [], createdAt: now)
        XCTAssertEqual(WordSetMerger.merge(existing: [set], incoming: [renamed, other]), [renamed, other])
    }
}
