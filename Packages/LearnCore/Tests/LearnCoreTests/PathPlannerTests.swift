import XCTest
@testable import LearnCore

final class PathPlannerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func state(reps: Int, due: TimeInterval = 86_400, lapses: Int = 0) -> SRSState {
        SRSState(ease: 2.5, intervalDays: 1, repetitions: reps, lapses: lapses,
                 dueDate: now.addingTimeInterval(due), lastReviewed: now.addingTimeInterval(-86_400))
    }

    private func noun(_ theme: String, created: TimeInterval = 0, translation: SRSState? = nil,
                      article: SRSState? = nil, plural: SRSState? = nil) -> PathWord {
        let fresh = SRSState.new(now: now.addingTimeInterval(created))
        return PathWord(
            id: UUID(),
            category: theme,
            createdAt: now.addingTimeInterval(created),
            schedules: [.translation: translation ?? fresh, .article: article ?? fresh, .plural: plural ?? fresh]
        )
    }

    private func verb(_ theme: String, translation: SRSState) -> PathWord {
        PathWord(id: UUID(), category: theme, createdAt: now, schedules: [.translation: translation])
    }

    /// The same streak for every kind of exercise of an area.
    private func everyKind(_ area: StudyArea, _ level: Int) -> [ExerciseKind: Int] {
        Dictionary(uniqueKeysWithValues: area.kinds.map { ($0, level) })
    }

    func testProgressStarsAndNewBadge() throws {
        let mastered = state(reps: 2)
        var words: [PathWord] = (0..<4).map { _ in
            var word = noun("Cibo", translation: mastered, article: mastered, plural: state(reps: 1))
            word.kindStreaks = [.translation: everyKind(.translation, 2), .article: everyKind(.article, 2),
                                .plural: everyKind(.plural, 1)]
            return word
        }
        var verbWord = verb("Cibo", translation: mastered)
        verbWord.kindStreaks = [.translation: everyKind(.translation, 2)]
        words.append(verbWord)

        var cibo = try XCTUnwrap(PathPlanner.themeProgress(words).first)
        XCTAssertEqual(cibo.wordCount, 5)
        XCTAssertEqual(cibo.newCount, 0)
        XCTAssertTrue(cibo.hasStar(.translation))
        XCTAssertTrue(cibo.hasStar(.article))
        XCTAssertFalse(cibo.hasStar(.plural))
        XCTAssertEqual(cibo.mastery[.article], 1)

        // A new page adds a word: progress dips, nothing resets.
        words.append(noun("Cibo", created: 10))
        cibo = try XCTUnwrap(PathPlanner.themeProgress(words).first)
        XCTAssertEqual(cibo.newCount, 1)
        XCTAssertEqual(cibo.mastery[.article] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertTrue(cibo.hasStar(.article))
    }

    func testProgressIsPerKindAndAreaIsTheAverage() throws {
        var word = noun("Cibo")
        let theme = { try XCTUnwrap(PathPlanner.themeProgress([word]).first) }
        XCTAssertEqual(try theme().mastery[.translation], 0)
        XCTAssertEqual(try theme().kindMastery[.translation]?.count, 4)
        XCTAssertEqual(try theme().kindMastery[.article]?.count, 3)

        // One right multiple choice: that kind is half way, the area a quarter of that.
        word.kindStreaks[.translation] = [.multipleChoice: 1]
        XCTAssertEqual(try theme().kindMastery[.translation]?[.multipleChoice], 0.5)
        XCTAssertEqual(try theme().kindMastery[.translation]?[.typeGerman], 0)
        XCTAssertEqual(try theme().mastery[.translation] ?? -1, 0.125, accuracy: 0.0001)

        word.kindStreaks[.translation] = everyKind(.translation, 3)
        XCTAssertEqual(try theme().mastery[.translation], 1)
        XCTAssertTrue(try theme().hasStar(.translation))

        // A mistake in one kind starts that kind over and pulls the area below the star.
        word.kindStreaks[.translation]?[.speakGerman] = 0
        XCTAssertEqual(try theme().mastery[.translation] ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertFalse(try theme().hasStar(.translation))
    }

    func testAreaWithoutApplicableWordsHasNoMastery() throws {
        let progress = try XCTUnwrap(PathPlanner.themeProgress([verb("Azioni", translation: state(reps: 2))]).first)
        XCTAssertNil(progress.mastery[.article])
        XCTAssertNotNil(progress.mastery[.translation])
    }

    func testThemesWithNewWordsComeFirst() {
        let words = [
            noun("Animali", translation: state(reps: 2)),
            noun(VocabEntry.defaultCategory, translation: state(reps: 2)),
            noun("Casa", translation: state(reps: 2)),
            noun("Viaggi"),
        ]
        XCTAssertEqual(PathPlanner.themeProgress(words).map(\.theme), ["Viaggi", "Animali", "Casa", VocabEntry.defaultCategory])
    }

    func testFocusIsNewestImportThenWeakestTheme() {
        let older = noun("Casa", created: -100)
        let newer = noun("Cibo", created: 100)
        XCTAssertEqual(PathPlanner.focusTheme([older, newer, noun("Lavoro", translation: state(reps: 2))]), "Cibo")

        var strong = noun("Casa", translation: state(reps: 3), article: state(reps: 3), plural: state(reps: 3))
        strong.kindStreaks = [.translation: everyKind(.translation, 2), .article: everyKind(.article, 2),
                              .plural: everyKind(.plural, 2)]
        let weak = noun("Cibo", translation: state(reps: 1), article: state(reps: 0), plural: state(reps: 0))
        XCTAssertEqual(PathPlanner.focusTheme([strong, weak]), "Cibo")
        XCTAssertNil(PathPlanner.focusTheme([]))
    }

    func testLessonIntroducesGrammarAfterTranslation() {
        let known = noun("Cibo", created: 1, translation: state(reps: 1))
        let unknown = noun("Cibo", created: 2)
        let lesson = PathPlanner.lesson([known, unknown], now: now, newLimit: 10)
        XCTAssertEqual(Set(lesson), [
            StudyItem(wordID: known.id, area: .article),
            StudyItem(wordID: known.id, area: .plural),
            StudyItem(wordID: unknown.id, area: .translation),
        ])
    }

    func testLessonPutsDueReviewsFirstAndCapsNewItems() {
        let due = noun("Cibo", created: 1, translation: state(reps: 2, due: -60))
        let fresh = (2...6).map { noun("Cibo", created: TimeInterval($0)) }
        let lesson = PathPlanner.lesson([due] + fresh, now: now, newLimit: 3)
        XCTAssertEqual(lesson.first, StudyItem(wordID: due.id, area: .translation))
        XCTAssertEqual(lesson.count, 1 + 3)
    }

    func testBonusUsesOnlySeenItemsWithDueFirst() {
        let overdue = noun("Casa", translation: state(reps: 2, due: -3_600))
        let missed = noun("Cibo", translation: state(reps: 1, lapses: 4))
        let fine = noun("Lavoro", translation: state(reps: 3, due: 864_000))
        let unseen = noun("Viaggi")
        let words = [overdue, missed, fine, unseen]
        var rng = SeededGenerator(state: 3)

        let two = PathPlanner.bonus(words, now: now, limit: 2, using: &rng)
        XCTAssertEqual(Set(two), [StudyItem(wordID: overdue.id, area: .translation), StudyItem(wordID: missed.id, area: .translation)])

        let all = PathPlanner.bonus(words, now: now, limit: 50, excluding: [StudyItem(wordID: fine.id, area: .translation)], using: &rng)
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.contains { $0.wordID == unseen.id })
    }

    func testKindFollowsTheStage() {
        var rng = SeededGenerator(state: 9)
        XCTAssertEqual(PathPlanner.kind(level: 0, area: .translation, allowSpeaking: true, using: &rng), .multipleChoice)
        for _ in 0..<20 {
            let second = PathPlanner.kind(level: 1, area: .article, allowSpeaking: true, using: &rng)
            XCTAssertEqual(second, .typeGerman)
            let later = PathPlanner.kind(level: 4, area: .plural, allowSpeaking: false, using: &rng)
            XCTAssertNotEqual(later, .speakGerman)
            XCTAssertNotEqual(later, .typeEnglish)
        }
    }
}
