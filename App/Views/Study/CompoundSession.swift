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

/// Drives one session of the compound words games: queue, grading, progress, time and mistakes.
@MainActor
final class CompoundSession: ObservableObject, Identifiable {
    @Published private(set) var question: CompoundQuestion?
    @Published private(set) var feedback: CompoundFeedback?
    @Published private(set) var isFinished = false
    @Published private(set) var results: [Verdict: Int] = [:]
    /// First parts already connected in the current match round.
    @Published private(set) var matched: Set<String> = []

    let total: Int
    var completed: Int { graded.count }

    private let context: ModelContext
    private let wordsByID: [UUID: Word]
    private let compounds: [VocabEntry]
    /// Other words, as distractors.
    private let nouns: [String]
    private var queue: [CompoundStep]
    private var currentStep: CompoundStep?
    private var graded: Set<CompoundStep> = []
    private var repeats: [CompoundStep: Int] = [:]
    /// Compounds already graded in the current match round (first attempt only).
    private var roundGraded: Set<UUID> = []
    private var roundMistakes = 0
    private var shownAt = Date()
    private var feedbackShownAt: Date?
    private var rng = SystemRandomNumberGenerator()

    private static let maxRepeats = 2
    private static let repeatGap = 3
    private static let maximumAnswerSeconds: TimeInterval = 60
    private static let maximumFeedbackSeconds: TimeInterval = 20

    init(steps: [CompoundStep], allWords: [Word], context: ModelContext) {
        self.context = context
        wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        compounds = allWords.filter(\.isCompound).map(\.entry)
        nouns = allWords.filter { !$0.isCompound && $0.partOfSpeech == .noun }.map(\.german)
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
        var rounds: [CompoundStep] = []
        var remaining = toMatch.map(\.entry)
        while let round = CompoundGame.matchRound(remaining, using: &rng) {
            let ids = round.compounds.map(\.id)
            rounds.append(CompoundStep(kind: .matchPairs, ids: ids))
            remaining.removeAll { ids.contains($0.id) }
        }
        let leftovers = remaining.map { CompoundStep(kind: .completeWord, ids: [$0.id]) }

        var steps = single + leftovers
        for round in rounds {
            steps.insert(round, at: Int.random(in: 0...steps.count, using: &rng))
        }
        return steps
    }

    /// 0 until matching or completing is mastered, 1 until building is, then 2.
    static func adaptiveLevel(of word: Word) -> Int {
        let streaks = word.compoundStreaks
        let recognised = max(streaks[.matchPairs] ?? 0, streaks[.completeWord] ?? 0) >= PathPlanner.masteryRepetitions
        guard recognised else { return 0 }
        return (streaks[.buildFromMeaning] ?? 0) >= PathPlanner.masteryRepetitions ? 2 : 1
    }

    // MARK: - Answers

    /// Connects two tiles of the match round; returns whether they make a compound.
    @discardableResult
    func matchPair(left: String, right: String) -> Bool {
        guard case .match(let round)? = question, feedback == nil else { return false }
        if let entry = round.compound(left: left, right: right) {
            matched.insert(left)
            if roundGraded.insert(entry.id).inserted {
                record(.correct, id: entry.id, kind: .matchPairs)
            }
            if matched.count == round.compounds.count {
                finishMatchRound(round)
            }
            return true
        }
        roundMistakes += 1
        if let intended = round.compound(left: left), roundGraded.insert(intended.id).inserted {
            record(.wrong, id: intended.id, kind: .matchPairs)
            logMistake(intended, kind: .matchPairs, given: "\(left) + \(right)")
        }
        return false
    }

    func choose(_ option: String) {
        guard case .complete(let question)? = question else { return }
        let verdict: Verdict = PhraseChecker.key(option) == PhraseChecker.key(question.answer) ? .correct : .wrong
        grade(verdict, entry: question.entry, kind: .completeWord, given: option)
    }

    func build(_ chosen: [String]) {
        guard case .build(let question)? = question else { return }
        grade(CompoundGame.checkBuild(chosen, entry: question.entry), entry: question.entry, kind: .buildFromMeaning,
              given: chosen.joined(separator: " + "))
    }

    func type(_ text: String) {
        guard case .type(let entry)? = question else { return }
        grade(CompoundGame.checkTyped(text, entry: entry), entry: entry, kind: .typeCompound, given: text)
    }

    /// The learner says the answer was right (a synonym, a typo the checker did not forgive).
    func overrideAsCorrect() {
        guard var feedback, feedback.verdict != .correct, let step = currentStep, let id = step.ids.first,
              step.kind != .matchPairs else { return }
        if feedback.verdict == .wrong, let index = queue.firstIndex(of: step) {
            queue.remove(at: index)
            repeats[step, default: 1] -= 1
        }
        if let word = wordsByID[id] {
            var streaks = word.compoundStreaks
            streaks[step.kind, default: 0] += 1
            word.compoundStreaks = streaks
            try? context.save()
        }
        results[feedback.verdict, default: 0] -= 1
        results[.correct, default: 0] += 1
        feedback.verdict = .correct
        self.feedback = feedback
    }

    func advance() {
        if let feedbackShownAt {
            ActivityStore.shared.addActive(seconds: min(Date().timeIntervalSince(feedbackShownAt), Self.maximumFeedbackSeconds))
        }
        feedback = nil
        feedbackShownAt = nil
        matched = []
        roundGraded = []
        roundMistakes = 0
        while !queue.isEmpty {
            let step = queue.removeFirst()
            guard let next = makeQuestion(for: step) else { continue }
            currentStep = step
            question = next
            shownAt = Date()
            return
        }
        currentStep = nil
        question = nil
        isFinished = true
    }

    // MARK: - Private

    private func makeQuestion(for step: CompoundStep) -> CompoundQuestion? {
        let entries = step.ids.compactMap { wordsByID[$0] }.filter(\.isCompound).map(\.entry)
        guard let entry = entries.first else { return nil }
        switch step.kind {
        case .matchPairs:
            return CompoundGame.matchRound(entries, using: &rng).map(CompoundQuestion.match)
        case .completeWord:
            return .complete(CompoundGame.complete(entry, compounds: compounds, words: nouns, using: &rng))
        case .buildFromMeaning:
            return .build(CompoundGame.build(entry, compounds: compounds, words: nouns, using: &rng))
        case .typeCompound:
            return .type(entry)
        }
    }

    private func grade(_ verdict: Verdict, entry: VocabEntry, kind: CompoundExerciseKind, given: String) {
        guard let step = currentStep, feedback == nil else { return }
        addAnswerTime()
        if !graded.contains(step) {
            graded.insert(step)
            results[verdict, default: 0] += 1
            record(verdict, id: entry.id, kind: kind)
        }
        if verdict != .correct {
            logMistake(entry, kind: kind, given: given)
        }
        if verdict == .wrong {
            requeue(step)
        }
        show(CompoundFeedback(verdict: verdict, given: given, solution: [Self.solution(entry)]))
    }

    private func finishMatchRound(_ round: CompoundMatchRound) {
        guard let step = currentStep else { return }
        addAnswerTime()
        let verdict: Verdict = roundMistakes == 0 ? .correct : .wrong
        if !graded.contains(step) {
            graded.insert(step)
            results[verdict, default: 0] += 1
        }
        show(CompoundFeedback(verdict: verdict, given: "", solution: round.compounds.map(Self.solution)))
    }

    private func show(_ feedback: CompoundFeedback) {
        self.feedback = feedback
        feedbackShownAt = Date()
    }

    private func record(_ verdict: Verdict, id: UUID, kind: CompoundExerciseKind) {
        guard let word = wordsByID[id] else { return }
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

    private func requeue(_ step: CompoundStep) {
        guard repeats[step, default: 0] < Self.maxRepeats else { return }
        repeats[step, default: 0] += 1
        queue.insert(step, at: min(Self.repeatGap, queue.count))
    }

    private func addAnswerTime() {
        ActivityStore.shared.addActive(seconds: min(Date().timeIntervalSince(shownAt), Self.maximumAnswerSeconds))
    }

    private func logMistake(_ entry: VocabEntry, kind: CompoundExerciseKind, given: String) {
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
