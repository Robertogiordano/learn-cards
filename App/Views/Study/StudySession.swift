import Foundation
import LearnCore
import SwiftData

/// Re-evaluates the answer already given against a corrected word.
typealias AnswerRecheck = (VocabEntry) -> Verdict

struct AnswerFeedback {
    var verdict: Verdict
    var given: String
    var overridden = false
    /// Set after the learner fixed the word's gender from the feedback panel.
    var correctedArticle: Article?
    var recheck: AnswerRecheck?
}

/// How the session picks the kind of exercise for each question.
enum KindPolicy {
    /// Free practice: one kind, or a random one of the area's kinds when nil.
    case fixed(ExerciseKind?)
    /// Path: from multiple choice to typing to speaking as the word is learned.
    case adaptive
}

/// One question of a session: a word in an area, or a number.
enum SessionStep: Hashable {
    case word(StudyItem)
    case number(NumberExercise)
}

/// A star (theme + area) gained during a session.
struct EarnedStar: Hashable {
    let theme: String
    let area: StudyArea
}

/// Drives one study session over (word, area) items and number questions:
/// queue, grading, spaced-repetition and progress updates.
@MainActor
final class StudySession: ObservableObject, Identifiable {
    @Published private(set) var exercise: Exercise?
    @Published private(set) var numberExercise: NumberExercise?
    @Published private(set) var feedback: AnswerFeedback?
    @Published private(set) var isFinished = false
    @Published private(set) var results: [Verdict: Int] = [:]
    /// True on the first question of the bonus part, to announce it.
    @Published private(set) var isBonusStart = false
    @Published private(set) var isInBonus = false

    let total: Int
    /// Existing themes, offered when editing a word from the session.
    let themes: [String]

    private let kindPolicy: KindPolicy
    private let allowSpeaking: Bool
    private let context: ModelContext
    private let wordsByID: [UUID: Word]
    private let pool: [VocabEntry]
    private let bonusSteps: Set<SessionStep>
    private let starsBefore: Set<EarnedStar>
    private var queue: [SessionStep]
    private var currentStep: SessionStep?
    private var hasShownBonus = false
    private var graded: Set<SessionStep> = []
    /// The current number question was graded on this attempt (so "I was right" can redo it).
    private var numberWasGraded = false
    /// State before the last first-attempt grading, so "I was right" can redo it.
    private var snapshot: (item: StudyItem, kind: ExerciseKind, srs: SRSState, streak: Int, kindStreak: Int,
                           timesCorrect: Int, timesWrong: Int)?
    private var shownAt = Date()
    private var rng = SystemRandomNumberGenerator()

    var completed: Int { graded.count }

    /// The word question being asked, if the current step is one.
    private var current: StudyItem? {
        if case .word(let item)? = currentStep { return item }
        return nil
    }

    /// `allWords` is the whole vocabulary, used for multiple-choice distractors and stars.
    /// Steps from index `bonusFrom` on form the bonus part.
    init(
        steps: [SessionStep],
        bonusFrom: Int? = nil,
        allWords: [Word],
        kindPolicy: KindPolicy,
        allowSpeaking: Bool,
        context: ModelContext
    ) {
        let wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.wordsByID = wordsByID
        pool = allWords.map(\.entry)
        themes = allWords.categories
        let valid = steps.filter { step in
            if case .word(let item) = step { return wordsByID[item.wordID] != nil }
            return true
        }
        queue = valid
        total = valid.count
        bonusSteps = bonusFrom.map { Set(steps.dropFirst($0)) } ?? []
        starsBefore = Self.stars(of: allWords)
        self.kindPolicy = kindPolicy
        self.allowSpeaking = allowSpeaking
        self.context = context
        advance()
    }

    convenience init(
        items: [StudyItem],
        bonusFrom: Int? = nil,
        allWords: [Word],
        kindPolicy: KindPolicy,
        allowSpeaking: Bool,
        context: ModelContext
    ) {
        self.init(steps: items.map { .word($0) }, bonusFrom: bonusFrom, allWords: allWords,
                  kindPolicy: kindPolicy, allowSpeaking: allowSpeaking, context: context)
    }

    /// Stars lit by this session, for the summary.
    var earnedStars: [EarnedStar] {
        Self.stars(of: Array(wordsByID.values))
            .subtracting(starsBefore)
            .sorted { ($0.theme, $0.area.rawValue) < ($1.theme, $1.area.rawValue) }
    }

    func submit(_ verdict: Verdict, given: String, recheck: AnswerRecheck? = nil) {
        guard let exercise, let currentStep, let current, feedback == nil,
              let word = wordsByID[current.wordID] else { return }

        // Only the first attempt counts; repeats after a mistake are practice.
        if !graded.contains(currentStep) {
            snapshot = (current, exercise.kind, word.srs(for: current.area), word.streak(for: current.area),
                        word.kindStreak(for: current.area, kind: exercise.kind), word.timesCorrect, word.timesWrong)
            record(verdict, for: word, area: current.area, kind: exercise.kind)
            graded.insert(currentStep)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            queue.append(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given, recheck: recheck)
    }

    func submitNumber(_ verdict: Verdict, given: String) {
        guard let numberExercise, let currentStep, feedback == nil else { return }
        if !graded.contains(currentStep) {
            NumberStatsStore.shared.record(verdict == .correct, number: numberExercise.number,
                                           level: numberExercise.level, kind: numberExercise.kind)
            graded.insert(currentStep)
            numberWasGraded = true
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            queue.append(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given)
    }

    /// The learner says the answer was right (synonym, recognizer mistake, ...).
    func overrideAsCorrect() {
        guard let feedback, feedback.verdict != .correct else { return }
        if let numberExercise, let currentStep {
            if feedback.verdict == .wrong, let index = queue.lastIndex(of: currentStep) {
                queue.remove(at: index)
            }
            if numberWasGraded {
                NumberStatsStore.shared.replaceLast(with: true, number: numberExercise.number,
                                                    level: numberExercise.level, kind: numberExercise.kind)
                results[feedback.verdict, default: 0] -= 1
                results[.correct, default: 0] += 1
            }
            self.feedback?.verdict = .correct
        } else {
            regrade(to: .correct)
        }
        self.feedback?.overridden = true
    }

    /// The extraction got the gender wrong: fix the word, then grade the answer again against it.
    func correctArticle(to article: Article) {
        guard let exercise, let answer = feedback, let word = wordsByID[exercise.entry.id],
              word.article != article else { return }
        var entry = word.entry
        entry.article = article
        word.update(from: entry)
        try? context.save()

        self.exercise = exercise.withEntry(entry)
        regrade(to: answer.recheck?(entry) ?? answer.verdict)
        feedback?.correctedArticle = article
    }

    /// Saves edits made from the feedback panel; they apply from the next question.
    func updateWord(_ entry: VocabEntry) {
        guard let word = wordsByID[entry.id] else { return }
        word.update(from: entry)
        try? context.save()
    }

    /// Replaces the current verdict, redoing the spaced-repetition update from the snapshot.
    private func regrade(to verdict: Verdict) {
        guard let exercise, let currentStep, let current, let feedback, let word = wordsByID[current.wordID],
              verdict != feedback.verdict else { return }

        // Only wrong answers sit at the back of the queue.
        if feedback.verdict == .wrong, let index = queue.lastIndex(of: currentStep) {
            queue.remove(at: index)
        }
        if verdict == .wrong {
            queue.append(currentStep)
        }
        if let snapshot, snapshot.item == current {
            word.setSRS(snapshot.srs, for: current.area)
            word.setStreak(snapshot.streak, for: current.area)
            word.setKindStreak(snapshot.kindStreak, for: current.area, kind: snapshot.kind)
            word.timesCorrect = snapshot.timesCorrect
            word.timesWrong = snapshot.timesWrong
            record(verdict, for: word, area: current.area, kind: exercise.kind)
            results[feedback.verdict, default: 0] -= 1
            results[verdict, default: 0] += 1
        }
        self.feedback?.verdict = verdict
    }

    func advance() {
        feedback = nil
        snapshot = nil
        numberWasGraded = false
        guard !queue.isEmpty else {
            exercise = nil
            numberExercise = nil
            currentStep = nil
            isFinished = true
            return
        }
        let step = queue.removeFirst()
        switch step {
        case .word(let item):
            guard let word = wordsByID[item.wordID] else {
                advance()
                return
            }
            numberExercise = nil
            exercise = ExerciseBuilder.make(area: item.area, kind: kind(for: item, word: word),
                                            entry: word.entry, pool: pool, using: &rng)
        case .number(let question):
            exercise = nil
            numberExercise = question
        }
        currentStep = step
        isInBonus = bonusSteps.contains(step)
        isBonusStart = isInBonus && !hasShownBonus
        if isInBonus { hasShownBonus = true }
        shownAt = Date()
    }

    private func record(_ verdict: Verdict, for word: Word, area: StudyArea, kind: ExerciseKind) {
        let now = Date()
        // Extra practice on words that are not due yet must not push their schedule around.
        let state = word.srs(for: area)
        if state.isDue(at: now) {
            let grade = ReviewGrade.from(verdict: verdict, kind: kind, responseTime: now.timeIntervalSince(shownAt))
            word.setSRS(SRS.review(state, grade: grade, now: now), for: area)
        }
        // Every graded answer moves the path's progress, due or not;
        // "almost" neither advances nor resets it.
        // The kind of exercise has its own streak too: it fills that kind's percentage.
        switch verdict {
        case .correct:
            word.setStreak(word.streak(for: area) + 1, for: area)
            word.setKindStreak(word.kindStreak(for: area, kind: kind) + 1, for: area, kind: kind)
        case .almost:
            break
        case .wrong:
            word.setStreak(0, for: area)
            word.setKindStreak(0, for: area, kind: kind)
        }
        if verdict == .wrong {
            word.timesWrong += 1
        } else {
            word.timesCorrect += 1
        }
        try? context.save()
    }

    private func kind(for item: StudyItem, word: Word) -> ExerciseKind {
        switch kindPolicy {
        case .fixed(let kind?):
            return kind
        case .fixed(nil):
            let kinds = item.area.kinds.filter { allowSpeaking || $0 != .speakGerman }
            return kinds.randomElement(using: &rng) ?? .multipleChoice
        case .adaptive:
            return PathPlanner.kind(level: word.streak(for: item.area), area: item.area,
                                    allowSpeaking: allowSpeaking, using: &rng)
        }
    }

    private static func stars(of words: [Word]) -> Set<EarnedStar> {
        var stars = Set<EarnedStar>()
        for progress in PathPlanner.themeProgress(words.map(\.pathWord)) {
            for area in StudyArea.allCases where progress.hasStar(area) {
                stars.insert(EarnedStar(theme: progress.theme, area: area))
            }
        }
        return stars
    }
}
