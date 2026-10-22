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

/// A star (theme + area) gained during a session.
struct EarnedStar: Hashable {
    let theme: String
    let area: StudyArea
}

/// Drives one study session over (word, area) items: queue, grading, spaced-repetition updates.
@MainActor
final class StudySession: ObservableObject, Identifiable {
    @Published private(set) var exercise: Exercise?
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
    private let bonusItems: Set<StudyItem>
    private let starsBefore: Set<EarnedStar>
    private var queue: [StudyItem]
    private var current: StudyItem?
    private var hasShownBonus = false
    private var graded: Set<StudyItem> = []
    /// State before the last first-attempt grading, so "I was right" can redo it.
    private var snapshot: (item: StudyItem, kind: ExerciseKind, srs: SRSState, streak: Int, kindStreak: Int,
                           timesCorrect: Int, timesWrong: Int)?
    private var shownAt = Date()
    private var rng = SystemRandomNumberGenerator()

    var completed: Int { graded.count }

    /// `allWords` is the whole vocabulary, used for multiple-choice distractors and stars.
    /// Items from index `bonusFrom` on form the bonus part.
    init(
        items: [StudyItem],
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
        let valid = items.filter { wordsByID[$0.wordID] != nil }
        queue = valid
        total = valid.count
        bonusItems = bonusFrom.map { Set(items.dropFirst($0)) } ?? []
        starsBefore = Self.stars(of: allWords)
        self.kindPolicy = kindPolicy
        self.allowSpeaking = allowSpeaking
        self.context = context
        advance()
    }

    /// Stars lit by this session, for the summary.
    var earnedStars: [EarnedStar] {
        Self.stars(of: Array(wordsByID.values))
            .subtracting(starsBefore)
            .sorted { ($0.theme, $0.area.rawValue) < ($1.theme, $1.area.rawValue) }
    }

    func submit(_ verdict: Verdict, given: String, recheck: AnswerRecheck? = nil) {
        guard let exercise, let current, feedback == nil, let word = wordsByID[current.wordID] else { return }

        // Only the first attempt counts; repeats after a mistake are practice.
        if !graded.contains(current) {
            snapshot = (current, exercise.kind, word.srs(for: current.area), word.streak(for: current.area),
                        word.kindStreak(for: current.area, kind: exercise.kind), word.timesCorrect, word.timesWrong)
            record(verdict, for: word, area: current.area, kind: exercise.kind)
            graded.insert(current)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            queue.append(current)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given, recheck: recheck)
    }

    /// The learner says the answer was right (synonym, recognizer mistake, ...).
    func overrideAsCorrect() {
        guard let feedback, feedback.verdict != .correct else { return }
        regrade(to: .correct)
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
        guard let exercise, let current, let feedback, let word = wordsByID[current.wordID],
              verdict != feedback.verdict else { return }

        // Only wrong answers sit at the back of the queue.
        if feedback.verdict == .wrong, let index = queue.lastIndex(of: current) {
            queue.remove(at: index)
        }
        if verdict == .wrong {
            queue.append(current)
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
        guard !queue.isEmpty else {
            exercise = nil
            current = nil
            isFinished = true
            return
        }
        let item = queue.removeFirst()
        guard let word = wordsByID[item.wordID] else {
            advance()
            return
        }
        current = item
        isInBonus = bonusItems.contains(item)
        isBonusStart = isInBonus && !hasShownBonus
        if isInBonus { hasShownBonus = true }
        exercise = ExerciseBuilder.make(area: item.area, kind: kind(for: item, word: word),
                                        entry: word.entry, pool: pool, using: &rng)
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
