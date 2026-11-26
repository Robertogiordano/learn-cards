import XCTest
@testable import LearnCore

final class SeparablePracticeTests: XCTestCase {
    let aufstehen = VerbEntry(infinitive: "aufstehen", english: "get up",
                              forms: ["stehe auf", "stehst auf", "steht auf", "stehen auf", "steht auf", "stehen auf"],
                              separablePrefix: "auf")
    let verstehen = VerbEntry(infinitive: "verstehen", english: "understand",
                              forms: ["verstehe", "verstehst", "versteht", "verstehen", "versteht", "verstehen"])
    let gehen = VerbEntry(infinitive: "gehen", english: "go",
                          forms: ["gehe", "gehst", "geht", "gehen", "geht", "gehen"], group: .irregular)

    func testPrefixes() {
        XCTAssertEqual(SeparablePractice.prefix(of: aufstehen), "auf")
        XCTAssertNil(SeparablePractice.prefix(of: verstehen))
        XCTAssertEqual(SeparablePractice.inseparablePrefix(of: verstehen), "ver")
        XCTAssertNil(SeparablePractice.inseparablePrefix(of: gehen))
        XCTAssertTrue(SeparablePractice.explanation(for: aufstehen).contains("ich stehe auf"))
        XCTAssertTrue(SeparablePractice.explanation(for: verstehen).contains("ver-"))
    }

    func testSentencesKeepThePrefixAtTheEnd() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<30 {
            let built = SeparableSentence.make(verb: aufstehen, using: &rng)!
            XCTAssertTrue(built.accepted.allSatisfy { $0.dropLast().hasSuffix(" auf") }, built.sentence)
            let wrong = built.wrongSentences(verb: aufstehen, using: &rng)
            XCTAssertGreaterThanOrEqual(wrong.count, 3)
            XCTAssertTrue(wrong.contains { $0.lowercased().contains("aufsteh") }, "\(wrong)")
            let acceptedKeys = Set(built.accepted.map(PhraseChecker.key))
            XCTAssertTrue(wrong.allSatisfy { !acceptedKeys.contains(PhraseChecker.key($0)) })
        }
    }

    func testInseparableMistake() {
        var rng = SystemRandomNumberGenerator()
        let built = SeparableSentence.make(verb: verstehen, using: &rng)!
        let wrong = built.wrongSentences(verb: verstehen, using: &rng)
        XCTAssertTrue(wrong.first!.dropLast().hasSuffix(" ver"), "\(wrong)")
    }

    func testMakeMixesKindsAndVerbs() {
        var rng = SystemRandomNumberGenerator()
        let exercises = SeparablePractice.make(count: 12, kind: nil, verbs: [aufstehen, verstehen, gehen], using: &rng)
        XCTAssertFalse(exercises.isEmpty)
        XCTAssertTrue(exercises.contains { !$0.isSeparable })
        for exercise in exercises {
            XCTAssertEqual(exercise.check(exercise.answer), .correct)
            if exercise.kind != .writeSentence {
                XCTAssertTrue(exercise.options.contains(exercise.answer))
                XCTAssertEqual(Set(exercise.options).count, exercise.options.count)
            }
        }
        let find = SeparablePractice.make(count: 3, kind: .findVerb, verbs: [aufstehen], using: &rng)
        XCTAssertTrue(find.allSatisfy { $0.options.count == 4 && $0.options.contains("stehen") })
        XCTAssertTrue(SeparablePractice.make(count: 5, kind: nil, verbs: [verstehen], using: &rng).isEmpty)
    }

    func testWriteAcceptsBothOrders() {
        var rng = SystemRandomNumberGenerator()
        let exercises = SeparablePractice.make(count: 10, kind: .writeSentence, verbs: [aufstehen], using: &rng)
        for exercise in exercises {
            for sentence in exercise.accepted {
                XCTAssertEqual(exercise.check(sentence.lowercased()), .correct)
            }
            XCTAssertEqual(exercise.check(exercise.sentence.replacingOccurrences(of: " auf", with: "")), .wrong)
        }
    }
}
