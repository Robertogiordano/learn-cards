import XCTest
@testable import LearnCore

final class LessonTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    /// A Wednesday.
    let today = ISO8601DateFormatter().date(from: "2026-10-21T10:00:00Z")!

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    // MARK: - Activity

    func testSecondsPerDay() {
        var stats = ActivityStats()
        stats.add(seconds: 120, on: today, calendar: calendar)
        stats.add(seconds: 60, on: today, calendar: calendar)
        stats.add(seconds: 30, on: day(-1), calendar: calendar)
        XCTAssertEqual(stats.seconds(on: today, calendar: calendar), 180)
        let week = stats.lastDays(7, today: today, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.seconds, 180)
        XCTAssertEqual(week[5].seconds, 30)
    }

    func testStreakWithTodayPendingAndAWeeklyJoker() {
        var stats = ActivityStats()
        for offset in [-1, -2, -4, -5] {
            stats.add(seconds: 600, on: day(offset), calendar: calendar)
        }
        // Today not reached yet: the streak is still alive. Sunday (-3) uses its week's joker.
        XCTAssertEqual(stats.streak(goalMinutes: 10, today: today, calendar: calendar), 4)
        stats.add(seconds: 600, on: today, calendar: calendar)
        XCTAssertEqual(stats.streak(goalMinutes: 10, today: today, calendar: calendar), 5)
        XCTAssertEqual(stats.streak(goalMinutes: 15, today: today, calendar: calendar), 0)
        XCTAssertEqual(ActivityStats().streak(goalMinutes: 10, today: today, calendar: calendar), 0)
    }

    func testStreakBreaksOnTwoMissedDaysInAWeek() {
        var stats = ActivityStats()
        for offset in [-1, -5] {
            stats.add(seconds: 600, on: day(offset), calendar: calendar)
        }
        // Monday (-2) uses this week's joker, Sunday (-3) last week's; Saturday (-4) has none left.
        XCTAssertEqual(stats.streak(goalMinutes: 10, today: today, calendar: calendar), 1)
    }

    func testErrorLogIsBounded() {
        var stats = ActivityStats()
        for index in 0..<(ActivityStats.maximumErrors + 5) {
            stats.log(ErrorRecord(date: today, domain: .word, itemID: nil, exercise: "x", prompt: "\(index)",
                                  given: "", expected: "", theme: nil))
        }
        XCTAssertEqual(stats.errors.count, ActivityStats.maximumErrors)
        XCTAssertEqual(stats.errors.first?.prompt, "5")
    }

    // MARK: - Planner

    private func candidate(_ theme: String, due: Bool = false, new: Bool = false, errors: Int = 0,
                           domain: LessonItem.Domain = .word) -> LessonCandidate {
        LessonCandidate(item: LessonItem(domain: domain, id: UUID(), area: domain == .word ? .translation : nil, reason: .practice),
                        theme: theme, isDue: due, isNew: new, recentErrors: errors, mastery: 0.5)
    }

    func testFocusThemesRotate() {
        let themes = [
            ThemeScore(name: "Cibo", recentErrors: 5, mastery: 0.5),
            ThemeScore(name: "Casa", recentErrors: 0, mastery: 0.1),
            ThemeScore(name: "Lavoro", recentErrors: 2, mastery: 0.9),
            ThemeScore(name: "Viaggi", recentErrors: 0, mastery: 0.8),
            ThemeScore(name: "Sport", recentErrors: 0, mastery: 0.95),
        ]
        XCTAssertEqual(LessonPlanner.focusThemes(themes, dayIndex: 0), ["Cibo", "Lavoro"])
        XCTAssertEqual(LessonPlanner.focusThemes(themes, dayIndex: 1), ["Lavoro", "Casa"])
        XCTAssertEqual(LessonPlanner.focusThemes(themes, dayIndex: 3), ["Viaggi", "Cibo"])
        XCTAssertEqual(LessonPlanner.focusThemes([], dayIndex: 3), [])
    }

    func testComposeFitsTheBudgetAndPutsMistakesFirst() {
        var candidates = (0..<30).map { _ in candidate("Casa", due: true) }
        candidates += (0..<10).map { _ in candidate("Cibo", errors: 2) }
        candidates += (0..<10).map { _ in candidate("Viaggi", new: true) }
        var rng = SeededGenerator(state: 9)
        let lesson = LessonPlanner.compose(candidates: candidates, budgetSeconds: 300, focusThemes: ["Viaggi"],
                                           numberLevel: 2, using: &rng)
        let seconds = lesson.map(\.estimatedSeconds).reduce(0, +)
        XCTAssertLessThanOrEqual(seconds, 300 + 25)
        XCTAssertGreaterThanOrEqual(seconds, 240)
        XCTAssertTrue(lesson.contains { $0.reason == .error })
        XCTAssertTrue(lesson.contains { $0.domain == .number && $0.numberLevel == 2 })
        XCTAssertEqual(Set(lesson.compactMap(\.id)).count, lesson.compactMap(\.id).count)
        XCTAssertGreaterThan(LessonPlanner.estimatedMinutes(lesson), 3)
    }

    // MARK: - Coach

    func testCoachPlanResolvesOnlyExistingMaterial() throws {
        let content = """
        Here is the plan: {"message": "Oggi lavoriamo sui verbi.", "blocks": [
          {"type": "verbs", "groups": ["Cambio vocalico"], "areas": [], "focus": "errors", "exercise": "typeForm", "count": 3, "level": null},
          {"type": "words", "groups": ["Cibo"], "areas": ["article"], "focus": "all", "exercise": "typeEnglish", "count": 50, "level": null},
          {"type": "numbers", "groups": [], "areas": [], "focus": "all", "exercise": "listenChoice", "count": 2, "level": 9},
          {"type": "songs", "groups": [], "areas": [], "focus": "all", "exercise": "auto", "count": 3, "level": null}
        ]}
        """
        let plan = try CoachPrompt.parse(content)
        XCTAssertEqual(plan.message, "Oggi lavoriamo sui verbi.")

        let verbWithErrors = LessonCandidate(item: LessonItem(domain: .verb, id: UUID(), reason: .practice),
                                             theme: "Cambio vocalico", isDue: false, isNew: false, recentErrors: 2, mastery: 0.3)
        let verbOtherGroup = LessonCandidate(item: LessonItem(domain: .verb, id: UUID(), reason: .practice),
                                             theme: "Regolari", isDue: false, isNew: false, recentErrors: 4, mastery: 0.3)
        let articles = (0..<30).map { _ in
            LessonCandidate(item: LessonItem(domain: .word, id: UUID(), area: .article, reason: .practice),
                            theme: "Cibo", isDue: true, isNew: false, recentErrors: 0, mastery: 0.5)
        }
        var rng = SeededGenerator(state: 2)
        let items = CoachResolver.resolve(plan, candidates: [verbWithErrors, verbOtherGroup] + articles, using: &rng)

        let verbs = items.filter { $0.domain == .verb }
        XCTAssertEqual(verbs.map(\.id), [verbWithErrors.item.id])
        XCTAssertEqual(verbs.first?.kind, "typeForm")
        let words = items.filter { $0.domain == .word }
        XCTAssertEqual(words.count, CoachResolver.maximumPerBlock)
        // typeEnglish does not exist for articles: automatic instead.
        XCTAssertTrue(words.allSatisfy { $0.kind == nil })
        let numbers = items.filter { $0.domain == .number }
        XCTAssertEqual(numbers.count, 2)
        XCTAssertTrue(numbers.allSatisfy { $0.numberLevel == 4 && $0.kind == "listenChoice" })
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CoachPrompt.responseSchema))
    }

    func testBackupKeepsActivity() throws {
        var activity = ActivityStats()
        activity.add(seconds: 300, on: today, calendar: calendar)
        let decoded = try BackupCodec.decode(BackupCodec.encode(Backup(exportedAt: today, words: [], activity: activity)))
        XCTAssertEqual(decoded.activity?.secondsByDay, activity.secondsByDay)
    }
}
