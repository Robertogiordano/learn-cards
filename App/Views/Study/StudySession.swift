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

/// One question of a session: a word in an area, a number, or a phrase.
enum SessionStep: Hashable {
    case word(StudyItem)
    case number(NumberExercise)
    case phrase(UUID)
    case verb(UUID)
    /// A compound game over one compound, or a match round over several.
    case compound(CompoundStep)
}

/// How verb questions pick their kind of exercise.
enum VerbPolicy {
    case adaptive
    case mixed
    case fixed(VerbExerciseKind)
}

/// A verb question ready to show.
struct VerbQuestion: Identifiable {
    let id = UUID()
    let kind: VerbExerciseKind
    let entry: VerbEntry
    /// The person asked (or, for whichPerson, the person whose form is shown).
    let person: Person
    /// Options for chooseForm.
    let options: [String]

    var form: String { entry.form(for: person) }
}

/// How phrase questions pick their kind of exercise.
enum PhrasePolicy {
    /// From reordering to producing as the phrase is learned.
    case adaptive
    /// Any applicable kind at random.
    case mixed
    case fixed(PhraseExerciseKind)
}

/// A phrase question ready to show.
struct PhraseQuestion: Identifiable {
    let id = UUID()
    let kind: PhraseExerciseKind
    let entry: PhraseEntry
    /// Shuffled words (reorder only).
    let tiles: [String]
    /// Sentence with a blank and the hidden word (cloze only).
    let cloze: (shown: String, answer: String)?
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
    @Published private(set) var phraseQuestion: PhraseQuestion?
    @Published private(set) var verbQuestion: VerbQuestion?
    /// The compound question being asked; it handles its own answers and feedback.
    @Published private(set) var compoundRunner: CompoundRunner?
    @Published private(set) var feedback: AnswerFeedback?
    @Published private(set) var isFinished = false
    @Published private(set) var results: [Verdict: Int] = [:]
    /// True on the first question of the bonus part, to announce it.
    @Published private(set) var isBonusStart = false
    @Published private(set) var isInBonus = false

    let total: Int
    /// Existing themes, offered when editing a word from the session.
    let themes: [String]
    /// Existing phrase categories, offered when editing a phrase.
    let phraseCategories: [String]

    private let kindPolicy: KindPolicy
    private let allowSpeaking: Bool
    private let context: ModelContext
    private let wordsByID: [UUID: Word]
    private let pool: [VocabEntry]
    private let phrasesByID: [UUID: Phrase]
    private let phrasePolicy: PhrasePolicy
    /// State before grading the current phrase on its first attempt.
    private var phraseSnapshot: (srs: SRSState, streak: Int, kindStreak: Int)?
    private let verbsByID: [UUID: Verb]
    private let verbPolicy: VerbPolicy
    private var verbSnapshot: (srs: SRSState, streak: Int, kindStreak: Int)?
    private let bonusSteps: Set<SessionStep>
    private let starsBefore: Set<EarnedStar>
    private var queue: [SessionStep]
    private var currentStep: SessionStep?
    private var hasShownBonus = false
    private var graded: Set<SessionStep> = []
    /// Times each step came back after a mistake in this session.
    private var repeats: [SessionStep: Int] = [:]
    /// A mistake comes back at most this many times, then the next session takes it up again.
    private static let maxRepeats = 2
    /// Questions in between before a missed one comes back.
    private static let repeatGap = 3
    /// The current number question was graded on this attempt (so "I was right" can redo it).
    private var numberWasGraded = false
    /// State before the last first-attempt grading, so "I was right" can redo it.
    private var snapshot: (item: StudyItem, kind: ExerciseKind, srs: SRSState, streak: Int, kindStreak: Int,
                           timesCorrect: Int, timesWrong: Int)?
    private var shownAt = Date()
    private var rng = SystemRandomNumberGenerator()
    /// Kinds of exercise chosen by a lesson, as raw values, per step.
    private let kindOverrides: [SessionStep: String]
    /// When the current feedback appeared: reading it counts as active time too.
    private var feedbackShownAt: Date?
    /// The mistake logged for the current question, taken back by "I was right".
    private var loggedMistake: ErrorRecord?

    /// Answer time beyond this is a pause, not study.
    private static let maximumAnswerSeconds: TimeInterval = 60
    private static let maximumFeedbackSeconds: TimeInterval = 20

    /// Called once per question, on its first answer (lesson progress).
    var onStepGraded: ((SessionStep) -> Void)?
    /// A daily lesson: the summary asks how it went.
    var isLesson = false

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
        allPhrases: [Phrase] = [],
        allVerbs: [Verb] = [],
        kindPolicy: KindPolicy,
        phrasePolicy: PhrasePolicy = .adaptive,
        verbPolicy: VerbPolicy = .adaptive,
        kindOverrides: [SessionStep: String] = [:],
        allowSpeaking: Bool,
        context: ModelContext
    ) {
        self.kindOverrides = kindOverrides
        let wordsByID = Dictionary(allWords.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let phrasesByID = Dictionary(allPhrases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.wordsByID = wordsByID
        let verbsByID = Dictionary(allVerbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.phrasesByID = phrasesByID
        self.phrasePolicy = phrasePolicy
        self.verbsByID = verbsByID
        self.verbPolicy = verbPolicy
        phraseCategories = allPhrases.categories
        pool = allWords.map(\.entry)
        themes = allWords.categories
        let valid = steps.filter { step in
            switch step {
            case .word(let item): return wordsByID[item.wordID] != nil
            case .phrase(let id): return phrasesByID[id] != nil
            case .verb(let id): return verbsByID[id] != nil
            case .compound(let step): return step.ids.contains { wordsByID[$0]?.isCompound == true }
            case .number: return true
            }
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
        afterSubmit(first: !graded.contains(currentStep), verdict: verdict) {
            ErrorRecord(date: .now, domain: .word, itemID: word.id,
                        exercise: "\(current.area.rawValue).\(exercise.kind.rawValue)",
                        prompt: exercise.prompt, given: given, expected: exercise.expectedAnswer, theme: word.category)
        }

        // Only the first attempt counts; repeats after a mistake are practice.
        if !graded.contains(currentStep) {
            snapshot = (current, exercise.kind, word.srs(for: current.area), word.streak(for: current.area),
                        word.kindStreak(for: current.area, kind: exercise.kind), word.timesCorrect, word.timesWrong)
            record(verdict, for: word, area: current.area, kind: exercise.kind)
            graded.insert(currentStep)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            requeueMissed(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given, recheck: recheck)
    }

    func submitNumber(_ verdict: Verdict, given: String) {
        guard let numberExercise, let currentStep, feedback == nil else { return }
        afterSubmit(first: !graded.contains(currentStep), verdict: verdict) {
            ErrorRecord(date: .now, domain: .number, itemID: nil,
                        exercise: "number.\(numberExercise.kind.rawValue)",
                        prompt: numberExercise.kind.isListening ? "🔊 \(numberExercise.digits)" : numberExercise.digits,
                        given: given, expected: "\(numberExercise.digits) (\(numberExercise.words))", theme: nil)
        }
        if !graded.contains(currentStep) {
            NumberStatsStore.shared.record(verdict == .correct, number: numberExercise.number,
                                           level: numberExercise.level, kind: numberExercise.kind)
            graded.insert(currentStep)
            numberWasGraded = true
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            requeueMissed(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given)
    }

    func submitPhrase(_ verdict: Verdict, given: String) {
        guard let phraseQuestion, let currentStep, feedback == nil,
              let phrase = phrasesByID[phraseQuestion.entry.id] else { return }
        afterSubmit(first: !graded.contains(currentStep), verdict: verdict) {
            let entry = phraseQuestion.entry
            return ErrorRecord(date: .now, domain: .phrase, itemID: entry.id,
                               exercise: "phrase.\(phraseQuestion.kind.rawValue)",
                               prompt: phraseQuestion.kind == .questionFromAnswer ? (entry.response ?? entry.english) : entry.english,
                               given: given,
                               expected: phraseQuestion.kind == .cloze ? (phraseQuestion.cloze?.answer ?? entry.german) : entry.german,
                               theme: entry.category)
        }
        if !graded.contains(currentStep) {
            phraseSnapshot = (phrase.srs, phrase.streak, phrase.kindStreaks[phraseQuestion.kind] ?? 0)
            recordPhrase(verdict, phrase: phrase, kind: phraseQuestion.kind)
            graded.insert(currentStep)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            requeueMissed(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given)
    }

    func submitVerb(_ verdict: Verdict, given: String) {
        guard let verbQuestion, let currentStep, feedback == nil,
              let verb = verbsByID[verbQuestion.entry.id] else { return }
        afterSubmit(first: !graded.contains(currentStep), verdict: verdict) {
            let entry = verbQuestion.entry
            let expected: String
            switch verbQuestion.kind {
            case .translateEnglish: expected = entry.english
            case .translateChoice, .translateGerman, .translateSpeak: expected = entry.infinitive
            case .fullTable: expected = entry.forms.joined(separator: ", ")
            case .whichPerson: expected = entry.persons(with: verbQuestion.form).map(\.label).joined(separator: " / ")
            default: expected = "\(verbQuestion.person.pronoun) \(verbQuestion.form)"
            }
            let prompt = verbQuestion.kind.isTranslation
                ? (verbQuestion.kind == .translateEnglish ? entry.infinitive : entry.english)
                : "\(verbQuestion.person.label) · \(entry.infinitive)"
            return ErrorRecord(date: .now, domain: .verb, itemID: entry.id, exercise: "verb.\(verbQuestion.kind.rawValue)",
                               prompt: prompt, given: given, expected: expected, theme: entry.group.label)
        }
        if !graded.contains(currentStep) {
            verbSnapshot = (verb.srs, verb.streak, verb.kindStreaks[verbQuestion.kind] ?? 0)
            recordVerb(verdict, verb: verb, kind: verbQuestion.kind)
            graded.insert(currentStep)
            results[verdict, default: 0] += 1
        }
        if verdict == .wrong {
            requeueMissed(currentStep)
        }
        feedback = AnswerFeedback(verdict: verdict, given: given)
    }

    /// Saves edits made from the feedback panel of a verb.
    func updateVerb(_ entry: VerbEntry) {
        guard let verb = verbsByID[entry.id] else { return }
        verb.update(from: entry)
        try? context.save()
    }

    /// Saves edits made from the feedback panel of a phrase.
    func updatePhrase(_ entry: PhraseEntry) {
        guard let phrase = phrasesByID[entry.id] else { return }
        phrase.update(from: entry)
        try? context.save()
    }

    /// The runner already saved progress, mistakes and time: count the question here.
    private func compoundAnswered(_ step: SessionStep, verdict: Verdict) {
        if graded.insert(step).inserted {
            results[verdict, default: 0] += 1
            onStepGraded?(step)
        }
        if verdict == .wrong {
            requeueMissed(step)
        }
    }

    private func compoundOverridden(_ step: SessionStep, previous: Verdict) {
        if previous == .wrong {
            cancelRequeue(step)
        }
        results[previous, default: 0] -= 1
        results[.correct, default: 0] += 1
    }

    /// A missed step comes back a few questions later, at most `maxRepeats` times.
    private func requeueMissed(_ step: SessionStep) {
        guard repeats[step, default: 0] < Self.maxRepeats else { return }
        repeats[step, default: 0] += 1
        queue.insert(step, at: min(Self.repeatGap, queue.count))
    }

    /// Takes back `requeueMissed` when a wrong verdict turns out to be right.
    private func cancelRequeue(_ step: SessionStep) {
        guard let index = queue.firstIndex(of: step) else { return }
        queue.remove(at: index)
        repeats[step, default: 1] -= 1
    }

    /// The learner says the answer was right (synonym, recognizer mistake, ...).
    func overrideAsCorrect() {
        guard let feedback, feedback.verdict != .correct else { return }
        if let loggedMistake {
            ActivityStore.shared.removeLastError(itemID: loggedMistake.itemID, exercise: loggedMistake.exercise)
            self.loggedMistake = nil
        }
        if let verbQuestion, let currentStep, let verb = verbsByID[verbQuestion.entry.id] {
            if feedback.verdict == .wrong {
                cancelRequeue(currentStep)
            }
            if let verbSnapshot {
                verb.srs = verbSnapshot.srs
                verb.streak = verbSnapshot.streak
                var streaks = verb.kindStreaks
                streaks[verbQuestion.kind] = verbSnapshot.kindStreak
                verb.kindStreaks = streaks
                recordVerb(.correct, verb: verb, kind: verbQuestion.kind)
                results[feedback.verdict, default: 0] -= 1
                results[.correct, default: 0] += 1
            }
            self.feedback?.verdict = .correct
        } else if let phraseQuestion, let currentStep, let phrase = phrasesByID[phraseQuestion.entry.id] {
            if feedback.verdict == .wrong {
                cancelRequeue(currentStep)
            }
            if let phraseSnapshot {
                phrase.srs = phraseSnapshot.srs
                phrase.streak = phraseSnapshot.streak
                var streaks = phrase.kindStreaks
                streaks[phraseQuestion.kind] = phraseSnapshot.kindStreak
                phrase.kindStreaks = streaks
                recordPhrase(.correct, phrase: phrase, kind: phraseQuestion.kind)
                results[feedback.verdict, default: 0] -= 1
                results[.correct, default: 0] += 1
            }
            self.feedback?.verdict = .correct
        } else if let numberExercise, let currentStep {
            if feedback.verdict == .wrong {
                cancelRequeue(currentStep)
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

        // Only wrong answers come back later in the session.
        if feedback.verdict == .wrong {
            cancelRequeue(currentStep)
        }
        if verdict == .wrong {
            requeueMissed(currentStep)
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
        compoundRunner?.close()
        compoundRunner = nil
        if let feedbackShownAt {
            ActivityStore.shared.addActive(seconds: min(Date().timeIntervalSince(feedbackShownAt), Self.maximumFeedbackSeconds))
            self.feedbackShownAt = nil
        }
        loggedMistake = nil
        feedback = nil
        snapshot = nil
        phraseSnapshot = nil
        verbSnapshot = nil
        numberWasGraded = false
        verbQuestion = nil
        guard !queue.isEmpty else {
            exercise = nil
            numberExercise = nil
            phraseQuestion = nil
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
            phraseQuestion = nil
            exercise = ExerciseBuilder.make(area: item.area, kind: forcedWordKind(step, area: item.area) ?? kind(for: item, word: word),
                                            entry: word.entry, pool: pool, using: &rng)
        case .number(let question):
            exercise = nil
            phraseQuestion = nil
            numberExercise = question
        case .phrase(let id):
            guard let phrase = phrasesByID[id] else {
                advance()
                return
            }
            exercise = nil
            numberExercise = nil
            phraseQuestion = makePhraseQuestion(for: phrase, forced: kindOverrides[step].flatMap(PhraseExerciseKind.init(rawValue:)))
        case .verb(let id):
            guard let verb = verbsByID[id] else {
                advance()
                return
            }
            exercise = nil
            numberExercise = nil
            phraseQuestion = nil
            verbQuestion = makeVerbQuestion(for: verb, forced: kindOverrides[step].flatMap(VerbExerciseKind.init(rawValue:)))
        case .compound(let compoundStep):
            guard let runner = CompoundRunner.make(compoundStep, wordsByID: wordsByID, allWords: Array(wordsByID.values),
                                                   context: context, recordsProgress: !graded.contains(step)) else {
                advance()
                return
            }
            exercise = nil
            numberExercise = nil
            phraseQuestion = nil
            runner.onAnswered = { [weak self] verdict in self?.compoundAnswered(step, verdict: verdict) }
            runner.onOverride = { [weak self] previous in self?.compoundOverridden(step, previous: previous) }
            compoundRunner = runner
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

    /// Active time, mistakes and lesson progress, the same for every kind of question.
    private func afterSubmit(first: Bool, verdict: Verdict, mistake: () -> ErrorRecord) {
        let now = Date()
        ActivityStore.shared.addActive(seconds: min(now.timeIntervalSince(shownAt), Self.maximumAnswerSeconds))
        feedbackShownAt = now
        guard first, let currentStep else { return }
        if verdict != .correct {
            let record = mistake()
            ActivityStore.shared.log(record)
            loggedMistake = record
        }
        onStepGraded?(currentStep)
    }

    /// A lesson's kind for a word, when it exists for the area and can be done now.
    private func forcedWordKind(_ step: SessionStep, area: StudyArea) -> ExerciseKind? {
        guard let raw = kindOverrides[step], let kind = ExerciseKind(rawValue: raw),
              area.kinds.contains(kind), allowSpeaking || kind != .speakGerman else { return nil }
        return kind
    }

    private func makePhraseQuestion(for phrase: Phrase, forced: PhraseExerciseKind? = nil) -> PhraseQuestion {
        let entry = phrase.entry
        let applicable = PhraseExerciseKind.allCases.filter {
            $0.isApplicable(to: entry) && (allowSpeaking || $0 != .speak)
        }
        let kind: PhraseExerciseKind
        let policy: PhrasePolicy = forced.map { forced in
            forced.isApplicable(to: entry) && (allowSpeaking || forced != .speak) ? .fixed(forced) : phrasePolicy
        } ?? phrasePolicy
        switch policy {
        case .adaptive:
            kind = PhraseExercises.kind(level: phrase.streak, entry: entry, allowSpeaking: allowSpeaking, using: &rng)
        case .mixed:
            kind = applicable.randomElement(using: &rng) ?? .translate
        case .fixed(let chosen):
            kind = chosen.isApplicable(to: entry) ? chosen : .translate
        }
        return PhraseQuestion(
            kind: kind,
            entry: entry,
            tiles: kind == .reorder ? PhraseExercises.shuffledTiles(for: entry.german, using: &rng) : [],
            cloze: kind == .cloze ? PhraseExercises.cloze(for: entry.german) : nil
        )
    }

    private func makeVerbQuestion(for verb: Verb, forced: VerbExerciseKind? = nil) -> VerbQuestion {
        let entry = verb.entry
        let kinds = VerbExerciseKind.allCases.filter { allowSpeaking || !$0.isSpeaking }
        var kind: VerbExerciseKind
        let policy: VerbPolicy = forced.map { allowSpeaking || !$0.isSpeaking ? .fixed($0) : verbPolicy } ?? verbPolicy
        switch policy {
        case .adaptive:
            kind = VerbExercises.kind(level: verb.streak, allowSpeaking: allowSpeaking, using: &rng)
        case .mixed:
            kind = kinds.randomElement(using: &rng) ?? .typeForm
        case .fixed(let chosen):
            kind = chosen
        }
        let person = Person.allCases.randomElement(using: &rng) ?? .ich
        var options: [String] = []
        switch kind {
        case .chooseForm:
            options = VerbExercises.options(for: entry, person: person, using: &rng)
        case .translateChoice:
            // Distractors come from all the session's verbs; with too few, type instead.
            let pool = verbsByID.values.map(\.entry)
            if let choices = VerbExercises.translationOptions(for: entry, pool: pool, using: &rng) {
                options = choices
            } else {
                kind = .translateGerman
            }
        default:
            break
        }
        return VerbQuestion(kind: kind, entry: entry, person: person, options: options)
    }

    private func recordVerb(_ verdict: Verdict, verb: Verb, kind: VerbExerciseKind) {
        let now = Date()
        if verb.srs.isDue(at: now) {
            let recognition = kind == .chooseForm || kind == .whichPerson || kind == .translateChoice
            let grade = ReviewGrade.from(verdict: verdict, kind: recognition ? .multipleChoice : .typeGerman,
                                         responseTime: now.timeIntervalSince(shownAt))
            verb.srs = SRS.review(verb.srs, grade: grade, now: now)
        }
        var streaks = verb.kindStreaks
        switch verdict {
        case .correct:
            verb.streak += 1
            streaks[kind, default: 0] += 1
        case .almost:
            break
        case .wrong:
            verb.streak = 0
            streaks[kind] = 0
        }
        verb.kindStreaks = streaks
        try? context.save()
    }

    private func recordPhrase(_ verdict: Verdict, phrase: Phrase, kind: PhraseExerciseKind) {
        let now = Date()
        if phrase.srs.isDue(at: now) {
            // Reordering is recognition, like multiple choice; the rest is production.
            let grade = ReviewGrade.from(verdict: verdict, kind: kind == .reorder ? .multipleChoice : .typeGerman,
                                         responseTime: now.timeIntervalSince(shownAt))
            phrase.srs = SRS.review(phrase.srs, grade: grade, now: now)
        }
        var streaks = phrase.kindStreaks
        switch verdict {
        case .correct:
            phrase.streak += 1
            streaks[kind, default: 0] += 1
        case .almost:
            break
        case .wrong:
            phrase.streak = 0
            streaks[kind] = 0
        }
        phrase.kindStreaks = streaks
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
