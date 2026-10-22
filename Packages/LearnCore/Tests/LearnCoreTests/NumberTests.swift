import XCTest
@testable import LearnCore

final class NumberTests: XCTestCase {
    func testSpelling() {
        let cases: [Int: String] = [
            0: "null", 1: "eins", 7: "sieben", 12: "zwölf", 16: "sechzehn", 17: "siebzehn",
            21: "einundzwanzig", 30: "dreißig", 47: "siebenundvierzig", 70: "siebzig", 99: "neunundneunzig",
            100: "einhundert", 101: "einhunderteins", 111: "einhundertelf", 365: "dreihundertfünfundsechzig",
            1000: "eintausend", 1001: "eintausendeins", 2024: "zweitausendvierundzwanzig",
            21_000: "einundzwanzigtausend", 101_000: "einhunderteintausend",
            999_999: "neunhundertneunundneunzigtausendneunhundertneunundneunzig",
            1_000_000: "eine Million",
        ]
        for (number, words) in cases {
            XCTAssertEqual(GermanNumbers.spell(number), words, "\(number)")
        }
    }

    func testParseRoundTripsEverySpelling() {
        for number in Array(0...1200) + [21_000, 101_000, 345_678, 999_999, 1_000_000] {
            XCTAssertEqual(GermanNumbers.parse(GermanNumbers.spell(number)), number, "\(number)")
        }
    }

    func testParseVariants() {
        XCTAssertEqual(GermanNumbers.parse("hundert"), 100)
        XCTAssertEqual(GermanNumbers.parse("tausend"), 1000)
        XCTAssertEqual(GermanNumbers.parse("sieben und vierzig"), 47)
        XCTAssertEqual(GermanNumbers.parse("Dreissig"), 30)
        XCTAssertEqual(GermanNumbers.parse("47"), 47)
        XCTAssertEqual(GermanNumbers.parse("1.000"), 1000)
        XCTAssertEqual(GermanNumbers.parse("25 300"), 25_300)
        XCTAssertNil(GermanNumbers.parse("Tisch"))
        XCTAssertNil(GermanNumbers.parse("einsundzwanzig"))
        XCTAssertNil(GermanNumbers.parse("2000000"))
        XCTAssertNil(GermanNumbers.parse(""))
    }

    func testDigitsDisplay() {
        XCTAssertEqual(GermanNumbers.digits(0), "0")
        XCTAssertEqual(GermanNumbers.digits(999), "999")
        XCTAssertEqual(GermanNumbers.digits(1000), "1.000")
        XCTAssertEqual(GermanNumbers.digits(25_300), "25.300")
        XCTAssertEqual(GermanNumbers.digits(1_000_000), "1.000.000")
    }

    func testChecks() {
        XCTAssertEqual(NumberQuiz.checkDigits("47", number: 47), .correct)
        XCTAssertEqual(NumberQuiz.checkDigits("1.000", number: 1000), .correct)
        XCTAssertEqual(NumberQuiz.checkDigits("74", number: 47), .wrong)
        XCTAssertEqual(NumberQuiz.checkDigits("vierzig", number: 40), .wrong)

        XCTAssertEqual(NumberQuiz.checkWords("siebenundvierzig", number: 47), .correct)
        XCTAssertEqual(NumberQuiz.checkWords("hundert", number: 100), .correct)
        XCTAssertEqual(NumberQuiz.checkWords("dreissig", number: 30), .correct)
        XCTAssertEqual(NumberQuiz.checkWords("siebenundvirzig", number: 47), .almost)
        XCTAssertEqual(NumberQuiz.checkWords("vierundsiebzig", number: 47), .wrong)
        XCTAssertEqual(NumberQuiz.checkWords("47", number: 47), .wrong)

        XCTAssertEqual(NumberQuiz.checkSpoken(["siebzig", "17"], number: 17), .correct)
        XCTAssertEqual(NumberQuiz.checkSpoken(["siebzig"], number: 17), .wrong)
    }

    func testDistractorsAreTheConfusingOnes() {
        var rng = SeededGenerator(state: 5)
        XCTAssertEqual(NumberQuiz.distractors(for: 21, level: .upTo100, using: &rng).first, 12)
        XCTAssertTrue(NumberQuiz.distractors(for: 13, level: .upTo20, using: &rng).prefix(2).contains(30))
        XCTAssertTrue(NumberQuiz.distractors(for: 30, level: .upTo100, using: &rng).contains(13))
        for number in [0, 1, 20, 100, 1000, 1_000_000] {
            let options = NumberQuiz.distractors(for: number, level: .upToMillion, using: &rng)
            XCTAssertGreaterThanOrEqual(options.count, 3)
            XCTAssertFalse(options.contains(number))
            XCTAssertTrue(options.allSatisfy { (0...GermanNumbers.maximum).contains($0) })
        }
    }

    func testExercisesStayInTheirLevel() {
        var rng = SeededGenerator(state: 11)
        for level in NumberLevel.allCases {
            for _ in 0..<200 {
                let exercise = NumberQuiz.make(kind: .listenChoice, level: level, stats: NumberStats(), using: &rng)
                XCTAssertTrue(level.range.contains(exercise.number), "\(exercise.number) in \(level)")
                XCTAssertEqual(exercise.options.count, 4)
                XCTAssertNotNil(exercise.correctIndex)
            }
        }
    }

    func testStatsProgressAndMistakes() {
        var stats = NumberStats()
        XCTAssertEqual(stats.progress(.upTo100, .writeWords), 0)
        stats.record(true, number: 47, level: .upTo100, kind: .writeWords)
        XCTAssertEqual(stats.progress(.upTo100, .writeWords), 1.0 / 20)
        stats.record(false, number: 74, level: .upTo100, kind: .writeWords)
        XCTAssertEqual(stats.mistakes(in: .upTo100), [74])

        stats.replaceLast(with: true, number: 74, level: .upTo100, kind: .writeWords)
        XCTAssertEqual(stats.progress(.upTo100, .writeWords), 2.0 / 20)
        XCTAssertEqual(stats.mistakes(in: .upTo100), [])

        for _ in 0..<30 { stats.record(true, number: 50, level: .upTo100, kind: .speak) }
        XCTAssertEqual(stats.progress(.upTo100, .speak), 1)
        XCTAssertEqual(stats.progress(.upTo100), (2.0 / 20 + 1) / 4, accuracy: 0.0001)
    }
}
