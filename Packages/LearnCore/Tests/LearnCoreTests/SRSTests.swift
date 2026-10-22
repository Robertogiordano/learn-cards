import XCTest
@testable import LearnCore

final class SRSTests: XCTestCase {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    let now = ISO8601DateFormatter().date(from: "2026-03-10T18:30:00Z")!

    private func days(from state: SRSState) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: state.dueDate).day!
    }

    func testNewWordGoodProgression() {
        var state = SRSState.new(now: now)
        XCTAssertTrue(state.isNew)
        XCTAssertTrue(state.isDue(at: now))

        state = SRS.review(state, grade: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.repetitions, 1)
        XCTAssertEqual(days(from: state), 1)
        XCTAssertFalse(state.isNew)

        state = SRS.review(state, grade: .good, now: now, calendar: calendar)
        XCTAssertEqual(days(from: state), 3)

        state = SRS.review(state, grade: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.intervalDays, 7.5, accuracy: 0.001)
        XCTAssertEqual(days(from: state), 8)
    }

    func testAgainResetsAndLowersEase() {
        var state = SRSState.new(now: now)
        state = SRS.review(state, grade: .good, now: now, calendar: calendar)
        state = SRS.review(state, grade: .good, now: now, calendar: calendar)
        state = SRS.review(state, grade: .again, now: now, calendar: calendar)
        XCTAssertEqual(state.repetitions, 0)
        XCTAssertEqual(state.lapses, 1)
        XCTAssertEqual(state.ease, 2.3, accuracy: 0.001)
        XCTAssertEqual(days(from: state), 1)
    }

    func testEaseHasFloor() {
        var state = SRSState.new(now: now)
        for _ in 0..<20 {
            state = SRS.review(state, grade: .again, now: now, calendar: calendar)
        }
        XCTAssertEqual(state.ease, SRS.minimumEase, accuracy: 0.001)
    }

    func testEasyGrowsFaster() {
        let good = SRS.review(.new(now: now), grade: .good, now: now, calendar: calendar)
        let easy = SRS.review(.new(now: now), grade: .easy, now: now, calendar: calendar)
        XCTAssertGreaterThan(easy.dueDate, good.dueDate)
        XCTAssertGreaterThan(easy.ease, good.ease)
    }

    func testDueAtStartOfDay() {
        let state = SRS.review(.new(now: now), grade: .good, now: now, calendar: calendar)
        XCTAssertEqual(state.dueDate, calendar.startOfDay(for: state.dueDate))
    }

    func testGradeMapping() {
        XCTAssertEqual(ReviewGrade.from(verdict: .wrong, kind: .typeGerman, responseTime: 1), .again)
        XCTAssertEqual(ReviewGrade.from(verdict: .almost, kind: .typeGerman, responseTime: 1), .hard)
        XCTAssertEqual(ReviewGrade.from(verdict: .correct, kind: .typeGerman, responseTime: 3), .easy)
        XCTAssertEqual(ReviewGrade.from(verdict: .correct, kind: .typeGerman, responseTime: 20), .good)
        XCTAssertEqual(ReviewGrade.from(verdict: .correct, kind: .multipleChoice, responseTime: 1), .good)
    }

    func testSessionPlannerOrder() {
        let old = now.addingTimeInterval(-86_400 * 3)
        let reviewed = StudyCandidate(
            id: UUID(),
            srs: SRSState(ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0, dueDate: now.addingTimeInterval(-60), lastReviewed: old),
            createdAt: old
        )
        let overdue = StudyCandidate(
            id: UUID(),
            srs: SRSState(ease: 2.5, intervalDays: 1, repetitions: 1, lapses: 0, dueDate: old, lastReviewed: old),
            createdAt: old
        )
        let fresh = StudyCandidate(id: UUID(), srs: .new(now: old), createdAt: old)
        let future = StudyCandidate(
            id: UUID(),
            srs: SRSState(ease: 2.5, intervalDays: 5, repetitions: 2, lapses: 0, dueDate: now.addingTimeInterval(86_400), lastReviewed: old),
            createdAt: old
        )
        let all = [fresh, future, reviewed, overdue]

        XCTAssertEqual(SessionPlanner.select(all, now: now, limit: 10), [overdue.id, reviewed.id, fresh.id])
        XCTAssertEqual(SessionPlanner.select(all, now: now, limit: 2), [overdue.id, reviewed.id])
        XCTAssertEqual(SessionPlanner.select(all, now: now, limit: 10, includeNotDue: true), [overdue.id, reviewed.id, fresh.id, future.id])
        XCTAssertEqual(SessionPlanner.dueCount(all, now: now), 3)
    }
}
