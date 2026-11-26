import XCTest
@testable import LearnCore

final class ClockTimeTests: XCTestCase {
    private func t(_ h: Int, _ m: Int) -> ClockTime { ClockTime(hour: h, minute: m) }

    func testInformalPhrasings() {
        XCTAssertEqual(GermanTime.informal(t(15, 0)), "drei Uhr")
        XCTAssertEqual(GermanTime.informal(t(13, 0)), "ein Uhr")
        XCTAssertEqual(GermanTime.informal(t(15, 5)), "fünf nach drei")
        XCTAssertEqual(GermanTime.informal(t(15, 15)), "Viertel nach drei")
        XCTAssertEqual(GermanTime.informal(t(15, 20)), "zwanzig nach drei")
        XCTAssertEqual(GermanTime.informalVariants(t(15, 20)), ["zwanzig nach drei", "zehn vor halb vier"])
        XCTAssertEqual(GermanTime.informal(t(15, 25)), "fünf vor halb vier")
        XCTAssertEqual(GermanTime.informal(t(15, 30)), "halb vier")
        XCTAssertEqual(GermanTime.informal(t(15, 35)), "fünf nach halb vier")
        XCTAssertEqual(GermanTime.informal(t(15, 45)), "Viertel vor vier")
        XCTAssertEqual(GermanTime.informal(t(15, 55)), "fünf vor vier")
        XCTAssertEqual(GermanTime.informal(t(12, 30)), "halb eins")
        XCTAssertEqual(GermanTime.informal(t(0, 15)), "Viertel nach zwölf")
        XCTAssertEqual(GermanTime.informal(t(12, 45)), "Viertel vor eins")
    }

    func testFormalPhrasings() {
        XCTAssertEqual(GermanTime.formal(t(15, 20)), "fünfzehn Uhr zwanzig")
        XCTAssertEqual(GermanTime.formal(t(1, 0)), "ein Uhr")
        XCTAssertEqual(GermanTime.formal(t(0, 5)), "null Uhr fünf")
        XCTAssertEqual(GermanTime.formal(t(21, 1)), "einundzwanzig Uhr eins")
    }

    func testCheckInformal() {
        XCTAssertEqual(GermanTime.checkInformal("halb vier", time: t(15, 30)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("Es ist halb vier.", time: t(3, 30)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("halb drei", time: t(15, 30)), .wrong)
        XCTAssertEqual(GermanTime.checkInformal("zehn vor halb vier", time: t(15, 20)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("zwanzig nach drei", time: t(15, 20)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("viertel nach drei", time: t(15, 15)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("fuenf nach halb vier", time: t(15, 35)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("dreiviertel vier", time: t(15, 45)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("drei Uhr", time: t(15, 0)), .correct)
        XCTAssertEqual(GermanTime.checkInformal("fünfzehn Uhr zwanzig", time: t(15, 20)), .wrong)
        XCTAssertEqual(GermanTime.checkInformal("3:20", time: t(15, 20)), .wrong)
        XCTAssertEqual(GermanTime.checkInformal("Firtel nach drei", time: t(15, 15)), .almost)
    }

    func testCheckFormal() {
        XCTAssertEqual(GermanTime.checkFormal("fünfzehn Uhr zwanzig", time: t(15, 20)), .correct)
        XCTAssertEqual(GermanTime.checkFormal("Es ist fuenfzehn uhr zwanzig", time: t(15, 20)), .correct)
        XCTAssertEqual(GermanTime.checkFormal("drei Uhr zwanzig", time: t(15, 20)), .wrong)
        XCTAssertEqual(GermanTime.checkFormal("ein Uhr", time: t(1, 0)), .correct)
        XCTAssertEqual(GermanTime.checkFormal("zwanzig nach drei", time: t(15, 20)), .wrong)
    }

    func testCheckDigits() {
        XCTAssertEqual(GermanTime.checkDigits("7:45", time: t(7, 45), clockFace: true), .correct)
        XCTAssertEqual(GermanTime.checkDigits("19.45", time: t(7, 45), clockFace: true), .correct)
        XCTAssertEqual(GermanTime.checkDigits("19:45", time: t(7, 45), clockFace: false), .wrong)
        XCTAssertEqual(GermanTime.checkDigits("8:45", time: t(7, 45), clockFace: true), .wrong)
        XCTAssertEqual(GermanTime.checkDigits("745", time: t(7, 45), clockFace: true), .wrong)
    }

    func testCheckSpoken() {
        XCTAssertEqual(GermanTime.checkSpoken(["Es ist halb 4"], time: t(15, 30)), .correct)
        XCTAssertEqual(GermanTime.checkSpoken(["15:30 Uhr"], time: t(15, 30)), .correct)
        XCTAssertEqual(GermanTime.checkSpoken(["15 Uhr 30"], time: t(15, 30)), .correct)
        XCTAssertEqual(GermanTime.checkSpoken(["halb drei"], time: t(15, 30)), .wrong)
    }

    func testConfusableIncludesHalbTrap() {
        var rng = SystemRandomNumberGenerator()
        let options = TimeQuiz.confusable(with: t(15, 30), level: .halfHours, using: &rng)
        XCTAssertTrue(options.contains { $0.sameOnClockFace(as: t(16, 30)) })
        XCTAssertFalse(options.contains { $0.sameOnClockFace(as: t(15, 30)) })
        let quarter = TimeQuiz.confusable(with: t(15, 15), level: .quarters, using: &rng)
        XCTAssertTrue(quarter.contains { $0.sameOnClockFace(as: t(14, 45)) })
    }

    func testQuizOptionsAreDistinct() {
        var rng = SystemRandomNumberGenerator()
        for level in TimeLevel.allCases {
            for kind in [TimeExerciseKind.readClock, .listenChoice] {
                for _ in 0..<50 {
                    let exercise = TimeQuiz.make(kind: kind, level: level, stats: TimeStats(), using: &rng)
                    XCTAssertEqual(exercise.options.count, 4)
                    XCTAssertEqual(Set(exercise.options).count, 4)
                    XCTAssertTrue(exercise.options.contains(exercise.answer))
                }
            }
        }
    }

    func testStatsRecord() {
        var stats = TimeStats()
        stats.record(false, time: t(15, 30), level: .halfHours, kind: .readClock)
        XCTAssertEqual(stats.mistakes(in: .halfHours), [15 * 60 + 30])
        stats.record(true, time: t(15, 30), level: .halfHours, kind: .readClock)
        XCTAssertEqual(stats.mistakes(in: .halfHours), [])
        XCTAssertEqual(stats.progress(.halfHours, .readClock), 1.0 / 20)
    }
}
