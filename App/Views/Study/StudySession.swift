import Foundation
import LearnCore
import SwiftData

struct AnswerFeedback {
    var verdict: Verdict
    var given: String
    var overridden = false
}

/// Drives one study session: queue, grading, spaced-repetition updates.
@MainActor
final class StudySession: ObservableObject, Identifiable {
    @Published private(set) var exercise: Exercise?
    @Published private(set) var feedback: AnswerFeedback?
    @Published private(set) var isFinished = false
    @Published private(set) var results: [Verdict: Int] = [:]

    let level: StudyLevel
    let total: Int

    private let mode: ExerciseKind?
    private let allowSpeaking: Bool
    private let context: ModelContext
    private let wordsByID: [UUID: Word]
    private let pool: [VocabEntry]
    private var queue: [UUID]
    private var graded: Set<UUID> = []
    /// State before the last first-attempt grading, so "I was right" can redo it.
    private var snapshot: (wordID: UUID, srs: SRSState, timesCorrect: Int, timesWrong: Int)?
    private var shownAt = Date()
    private var rng = SystemRandomNumberGenerator()

    var completed: Int { graded.count }

    init(wordIDs: [UUID], allWords: [Word], level: StudyLevel, mode: ExerciseKind?, allowSpeaking: Bool, context: ModelContext) {
        let wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.wordsByID = wordsByID
        pool = allWords.map(\.entry)
        queue = wordIDs.filter { wordsByID[$0] != nil }
        total = queue.count
        self.level = level
        self.mode = mode
        self.allowSpeaking = allowSpeaking
        self.context = context
        advance()
    }

    func submit(_ verdict: Verdict, given: String) {
        guard let exercise, feedback == nil, let word = wordsByID[exercise.entry.id] else { return }

        // Only the first attempt counts; repeats after a mistake are practice.
        if !graded.contains(word.id) {
            snapshot = (word.id, word.srs, word.timesCorrect, word.timesWrong)
            record(verdict, for: word, kind: exercise.kind)
            graded.insert(word.id)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            queue.append(word.id)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given)
    }

    /// The learner says the answer was right (synonym, recognizer mistake, ...).
    func overrideAsCorrect() {
        guard let exercise, let current = feedback, current.verdict != .correct,
              let word = wordsByID[exercise.entry.id] else { return }

        if current.verdict == .wrong, let index = queue.lastIndex(of: word.id) {
            queue.remove(at: index)
        }
        if let snapshot, snapshot.wordID == word.id {
            word.srs = snapshot.srs
            word.timesCorrect = snapshot.timesCorrect
            word.timesWrong = snapshot.timesWrong
            record(.correct, for: word, kind: exercise.kind)
            results[current.verdict, default: 0] -= 1
            results[.correct, default: 0] += 1
            self.snapshot = nil
        }
        feedback = AnswerFeedback(verdict: .correct, given: current.given, overridden: true)
    }

    func advance() {
        feedback = nil
        snapshot = nil
        guard !queue.isEmpty else {
            exercise = nil
            isFinished = true
            return
        }
        let id = queue.removeFirst()
        guard let word = wordsByID[id] else {
            advance()
            return
        }
        exercise = ExerciseBuilder.make(kind: mode ?? randomKind(), entry: word.entry, pool: pool, level: level, using: &rng)
        shownAt = Date()
    }

    private func record(_ verdict: Verdict, for word: Word, kind: ExerciseKind) {
        let now = Date()
        // Extra practice on words that are not due yet must not push their schedule around.
        if word.srs.isDue(at: now) {
            let grade = ReviewGrade.from(verdict: verdict, kind: kind, responseTime: now.timeIntervalSince(shownAt))
            word.srs = SRS.review(word.srs, grade: grade, now: now)
        }
        if verdict == .wrong {
            word.timesWrong += 1
        } else {
            word.timesCorrect += 1
        }
        try? context.save()
    }

    private func randomKind() -> ExerciseKind {
        let kinds = ExerciseKind.allCases.filter { allowSpeaking || $0 != .speakGerman }
        return kinds.randomElement(using: &rng) ?? .multipleChoice
    }
}
