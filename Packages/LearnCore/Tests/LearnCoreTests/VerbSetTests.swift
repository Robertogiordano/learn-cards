import XCTest
@testable import LearnCore

final class VerbSetTests: XCTestCase {
    private func verb(new: Bool, streak: Int = 0) -> VerbSetCandidate {
        let streaks = Dictionary(uniqueKeysWithValues: VerbExerciseKind.allCases.map { ($0, streak) })
        return VerbSetCandidate(id: UUID(), isNew: new, kindStreaks: new ? [:] : streaks)
    }

    func testPickReturnsDistinctVerbs() {
        let verbs = (0..<12).map { _ in verb(new: false, streak: 1) }
        var rng = SeededGenerator(state: 5)
        let picked = VerbSetPicker.pick(verbs, count: 10, using: &rng)
        XCTAssertEqual(Set(picked).count, 10)
        XCTAssertTrue(Set(picked).isSubset(of: verbs.map(\.id)))
        XCTAssertEqual(VerbSetPicker.pick(Array(verbs.prefix(3)), count: 10, using: &rng).count, 3)
    }

    func testNewVerbsWeighMore() {
        XCTAssertEqual(VerbSetPicker.weight(of: verb(new: true)), 4)
        XCTAssertEqual(VerbSetPicker.weight(of: verb(new: false, streak: 2)), 1, accuracy: 0.001)
        let fresh = (0..<10).map { _ in verb(new: true) }
        let mastered = (0..<10).map { _ in verb(new: false, streak: 2) }
        let freshIDs = Set(fresh.map(\.id))
        var rng = SeededGenerator(state: 11)
        var freshCount = 0
        for _ in 0..<200 {
            freshCount += VerbSetPicker.pick(fresh + mastered, count: 5, using: &rng).filter(freshIDs.contains).count
        }
        XCTAssertGreaterThan(freshCount, 600)
    }

    func testNextNameAndMerge() {
        XCTAssertEqual(VerbSetPicker.nextName(existing: ["Verb set 1", "Set 2"]), "Verb set 2")
        let a = VerbSet(name: "A", verbIDs: [])
        var changed = a
        changed.name = "B"
        let merged = VerbSetMerger.merge(existing: [a], incoming: [changed, VerbSet(name: "C", verbIDs: [])])
        XCTAssertEqual(merged.map(\.name), ["B", "C"])
    }

    func testBackupKeepsVerbSets() throws {
        let set = VerbSet(name: "Irregular", verbIDs: [UUID()], createdAt: Date(timeIntervalSince1970: 1_780_000_000))
        let data = try BackupCodec.encode(Backup(exportedAt: Date(timeIntervalSince1970: 0), words: [], verbSets: [set]))
        XCTAssertEqual(try BackupCodec.decode(data).verbSets, [set])
    }
}
