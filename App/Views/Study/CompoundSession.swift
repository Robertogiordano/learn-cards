import Foundation
import LearnCore
import SwiftData

/// How compound questions pick their game.
enum CompoundPolicy {
    /// From matching and completing to building and typing as the compound is learned.
    case adaptive
    /// Any game at random.
    case mixed
    case fixed(CompoundExerciseKind)
}

/// One question: a game over one compound, or a match round over several.
struct CompoundStep: Hashable {
    let kind: CompoundExerciseKind
    let ids: [UUID]
}

/// A compound question ready to show.
enum CompoundQuestion: Identifiable {
    case match(CompoundMatchRound)
    case complete(CompoundCompleteQuestion)
    case build(CompoundBuildQuestion)
    case type(VocabEntry)

    var id: String {
        switch self {
        case .match(let round): return "match-" + round.compounds.map(\.id.uuidString).joined()
        case .complete(let question): return "complete-\(question.entry.id)"
        case .build(let question): return "build-\(question.entry.id)"
        case .type(let entry): return "type-\(entry.id)"
        }
    }
}

struct CompoundFeedback {
    var verdict: Verdict
    var given: String
    /// "Küche + Tür → die Küchentür", one line per compound.
    var solution: [String]
}

/// One compound question, wherever it is asked (its own section, the bonus, a lesson):
/// answers, feedback, progress on the words, mistakes and active time.
@MainActor
final class CompoundRunner: ObservableObject {
    let question: CompoundQuestion
    @Published private(set) var feedback: CompoundFeedback?
    /// First parts already connected in a match round.
    @Published private(set) var matched: Set<String> = []

    /// Called once, when the question is answered, with its verdict.
    var onAnswered: ((Verdict) -> Void)?
    /// Called when "I was right" turns the verdict into correct, with the previous verdict.
    var onOverride: ((Verdict) -> Void)?

    private let kind: CompoundExerciseKind
    private let wordsByID: [UUID: Word]
    private let context: ModelContext
    /// Only the first attempt at a question moves the percentages.
    private let recordsProgress: Bool
    /// Compounds already graded in a match round.
    private var roundGraded: Set<UUID> = []
    private var roundMistakes = 0
    private var shownAt = Date()
    private var feedbackShownAt: Date?

    private static let maximumAnswerSeconds: TimeInterval = 60
    private static let maximumFeedbackSeconds: TimeInterval = 20

    init(question: CompoundQuestion, kind: CompoundExerciseKind, wordsByID: [UUID: Word], context: ModelContext,
         recordsProgress: Bool) {
        self.question = question
        self.kind = kind
        self.wordsByID = wordsByID
        self.context = context
        self.recordsProgress = recordsProgress
    }

    /// Builds the question of a step; nil when its words are gone or no longer compounds.
    static func make(_ step: CompoundStep, wordsByID: [UUID: Word], allWords: [Word], context: ModelContext,
                     recordsProgress: Bool) -> CompoundRunner? {
        var rng = SystemRandomNumberGenerator()
        let entries = step.ids.compactMap { wordsByID[$0] }.filter(\.isCompound).map(\.entry)
        guard let entry = entries.first else { return nil }
        let compounds = allWords.filter(\.isCompound).map(\.entry)
        let nouns = allWords.filter { !$0.isCompound && $0.partOfSpeech == .noun }.map(\.german)
        let question: CompoundQuestion
        switch step.kind {
        case .matchPairs:
            guard let round = CompoundGame.matchRound(entries, using: &rng) else { return nil }
            question = .match(round)
        case .completeWord:
            question = .complete(CompoundGame.complete(entry, compounds: compounds, words: nouns, using: &rng))
        case .buildFromMeaning:
            question = .build(CompoundGame.build(entry, compounds: compounds, words: nouns, using: &rng))
        case .typeCompound:
            question = .type(entry)
        }
        return CompoundRunner(question: question, kind: step.kind, wordsByID: wordsByID, context: context,
                              recordsProgress: recordsProgress)
    }

    // MARK: - Answers

    /// Connects two tiles of the match round; returns whether they make a compound.
    @discardableResult
    func matchPair(left: String, right: String) -> Bool {
        guard case .match(let round) = question, feedback == nil else { return false }
        if let entry = round.compound(left: left, right: right) {
            matched.insert(left)
            if roundGraded.insert(entry.id).inserted {
                record(.correct, id: entry.id)
            }
            if matched.count == round.compounds.count {
                answer(roundMistakes == 0 ? .correct : .wrong, given: "", solution: round.compounds)
            }
            return true
        }
        roundMistakes += 1
        if let intended = round.compound(left: left), roundGraded.insert(intended.id).inserted {
            record(.wrong, id: intended.id)
            logMistake(intended, given: "\(left) + \(right)")
        }
        return false
    }

    func choose(_ option: String) {
        guard case .complete(let question) = question else { return }
        let verdict: Verdict = PhraseChecker.key(option) == PhraseChecker.key(question.answer) ? .correct : .wrong
        grade(verdict, entry: question.entry, given: option)
    }

    func build(_ chosen: [String]) {
        guard case .build(let question) = question else { return }
        grade(CompoundGame.checkBuild(chosen, entry: question.entry), entry: question.entry,
              given: chosen.joined(separator: " + "))
    }

    func type(_ text: String) {
        guard case .type(let entry) = question else { return }
        grade(CompoundGame.checkTyped(text, entry: entry), entry: entry, given: text)
    }

    var canOverride: Bool {
        if case .match = question { return false }
        return (feedback?.verdict ?? .correct) != .correct
    }

    /// The learner says the answer was right (a synonym, a typo the checker did not forgive).
    func overrideAsCorrect() {
        guard canOverride, var feedback else { return }
        let previous = feedback.verdict
        if recordsProgress, let id = singleID, let word = wordsByID[id] {
            var streaks = word.compoundStreaks
            streaks[kind, default: 0] += 1
            word.compoundStreaks = streaks
            if previous == .wrong {
                word.timesWrong = max(0, word.timesWrong - 1)
                word.timesCorrect += 1
            }
            try? context.save()
        }
        feedback.verdict = .correct
        self.feedback = feedback
        onOverride?(previous)
    }

    /// Before moving on: reading the feedback counts as study time too.
    func close() {
        if let feedbackShownAt {
            ActivityStore.shared.addActive(seconds: min(Date().timeIntervalSince(feedbackShownAt), Self.maximumFeedbackSeconds))
            self.feedbackShownAt = nil
        }
    }

    // MARK: - Private

    private var singleID: UUID? {
        switch question {
        case .match: return nil
        case .complete(let question): return question.entry.id
        case .build(let question): return question.entry.id
        case .type(let entry): return entry.id
        }
    }

    private func grade(_ verdict: Verdict, entry: VocabEntry, given: String) {
        guard feedback == nil else { return }
        record(verdict, id: entry.id)
        if verdict != .correct {
            logMistake(entry, given: given)
        }
        answer(verdict, given: given, solution: [entry])
    }

    private func answer(_ verdict: Verdict, given: String, solution: [VocabEntry]) {
        let now = Date()
        ActivityStore.shared.addActive(seconds: min(now.timeIntervalSince(shownAt), Self.maximumAnswerSeconds))
        feedbackShownAt = now
        feedback = CompoundFeedback(verdict: verdict, given: given, solution: solution.map(Self.solution))
        onAnswered?(verdict)
    }

    private func record(_ verdict: Verdict, id: UUID) {
        guard recordsProgress, let word = wordsByID[id] else { return }
        var streaks = word.compoundStreaks
        switch verdict {
        case .correct:
            streaks[kind, default: 0] += 1
            word.timesCorrect += 1
        case .almost:
            break
        case .wrong:
            streaks[kind] = 0
            word.timesWrong += 1
        }
        word.compoundStreaks = streaks
        try? context.save()
    }

    private func logMistake(_ entry: VocabEntry, given: String) {
        ActivityStore.shared.log(ErrorRecord(date: .now, domain: .word, itemID: entry.id,
                                             exercise: "compound.\(kind.rawValue)",
                                             prompt: kind == .buildFromMeaning ? entry.englishDisplay : entry.partsDisplay,
                                             given: given, expected: entry.withArticle,
                                             theme: VocabEntry.compoundCategory))
    }

    static func solution(_ entry: VocabEntry) -> String {
        "\(entry.partsDisplay) → \(entry.withArticle)"
    }
}

/// A session of the compound words section: queue, retries and results; each question runs in a `CompoundRunner`.
@MainActor
final class CompoundSession: ObservableObject, Identifiable {
    @Published private(set) var runner: CompoundRunner?
    @Published private(set) var isFinished = false
    @Published private(set) var results: [Verdict: Int] = [:]

    let total: Int
    var completed: Int { graded.count }

    private let context: ModelContext
    private let allWords: [Word]
    private let wordsByID: [UUID: Word]
    private var queue: [CompoundStep]
    private var graded: Set<CompoundStep> = []
    private var repeats: [CompoundStep: Int] = [:]

    private static let maxRepeats = 2
    private static let repeatGap = 3

    init(steps: [CompoundStep], allWords: [Word], context: ModelContext) {
        self.context = context
        self.allWords = allWords
        wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        queue = steps
        total = steps.count
        advance()
    }

    /// Questions for the chosen compounds; match rounds take several compounds at once.
    static func steps(for words: [Word], policy: CompoundPolicy) -> [CompoundStep] {
        var rng = SystemRandomNumberGenerator()
        let canMatch = words.count >= CompoundGame.minimumPairs
        var single: [CompoundStep] = []
        var toMatch: [Word] = []
        for word in words {
            let kind: CompoundExerciseKind
            switch policy {
            case .fixed(let chosen):
                kind = chosen
            case .mixed:
                let kinds = CompoundExerciseKind.allCases.filter { canMatch || $0 != .matchPairs }
                kind = kinds.randomElement(using: &rng) ?? .completeWord
            case .adaptive:
                kind = CompoundGame.kind(level: adaptiveLevel(of: word), canMatch: canMatch, using: &rng)
            }
            if kind == .matchPairs {
                toMatch.append(word)
            } else {
                single.append(CompoundStep(kind: kind, ids: [word.id]))
            }
        }

        // Group the compounds to match into rounds; those that do not fit play "complete".
        let (rounds, leftovers) = matchRounds(toMatch)
        var steps = single + leftovers.map { CompoundStep(kind: .completeWord, ids: [$0.id]) }
        for round in rounds {
            steps.insert(round, at: Int.random(in: 0...steps.count, using: &rng))
        }
        return steps
    }

    /// Match rounds out of these compounds, and the ones that fit no round.
    static func matchRounds(_ words: [Word]) -> (rounds: [CompoundStep], leftovers: [Word]) {
        var rng = SystemRandomNumberGenerator()
        var rounds: [CompoundStep] = []
        var remaining = words
        while let round = CompoundGame.matchRound(remaining.map(\.entry), using: &rng) {
            let ids = round.compounds.map(\.id)
            rounds.append(CompoundStep(kind: .matchPairs, ids: ids))
            remaining.removeAll { ids.contains($0.id) }
        }
        return (rounds, remaining)
    }

    /// 0 until matching or completing is mastered, 1 until building is, then 2.
    static func adaptiveLevel(of word: Word) -> Int {
        let streaks = word.compoundStreaks
        let recognised = max(streaks[.matchPairs] ?? 0, streaks[.completeWord] ?? 0) >= PathPlanner.masteryRepetitions
        guard recognised else { return 0 }
        return (streaks[.buildFromMeaning] ?? 0) >= PathPlanner.masteryRepetitions ? 2 : 1
    }

    func advance() {
        runner?.close()
        while !queue.isEmpty {
            let step = queue.removeFirst()
            guard let next = CompoundRunner.make(step, wordsByID: wordsByID, allWords: allWords, context: context,
                                                 recordsProgress: !graded.contains(step)) else { continue }
            next.onAnswered = { [weak self] verdict in self?.answered(step, verdict: verdict) }
            next.onOverride = { [weak self] previous in self?.overridden(step, previous: previous) }
            runner = next
            return
        }
        runner = nil
        isFinished = true
    }

    private func answered(_ step: CompoundStep, verdict: Verdict) {
        if graded.insert(step).inserted {
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong, repeats[step, default: 0] < Self.maxRepeats {
            repeats[step, default: 0] += 1
            queue.insert(step, at: min(Self.repeatGap, queue.count))
        }
    }

    private func overridden(_ step: CompoundStep, previous: Verdict) {
        if previous == .wrong, let index = queue.firstIndex(of: step) {
            queue.remove(at: index)
            repeats[step, default: 1] -= 1
        }
        results[previous, default: 0] -= 1
        results[.correct, default: 0] += 1
    }
}
