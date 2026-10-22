import Foundation
import LearnCore

/// Today's lesson: fixed for the day, so it can be resumed where it was left.
struct DailyLesson: Codable {
    var day: String
    var items: [LessonItem]
    /// Indices of the items already answered.
    var done: Set<Int> = []
    /// The coach's message, when the lesson comes from the coach.
    var message: String?
    var focus: [String]
    var fromCoach: Bool

    var remaining: [Int] { items.indices.filter { !done.contains($0) } }
    var isComplete: Bool { !items.isEmpty && remaining.isEmpty }
    var minutes: Int { LessonPlanner.estimatedMinutes(items) }
}

/// Keeps today's lesson and the learner's feedback on difficulty.
@MainActor
final class LessonStore: ObservableObject {
    static let shared = LessonStore()

    private static let lessonKey = "dailyLesson"
    private static let difficultyKey = "lessonDifficulty"

    @Published private(set) var lesson: DailyLesson?

    /// -1 easier, 0, +1 harder: from "troppo difficile / giusta / troppo facile".
    var difficulty: Int { UserDefaults.standard.integer(forKey: Self.difficultyKey) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.lessonKey),
           let stored = try? JSONDecoder().decode(DailyLesson.self, from: data) {
            lesson = stored
        }
    }

    /// Today's lesson, or nil when the stored one is from another day.
    var today: DailyLesson? {
        lesson?.day == ActivityStats.dayKey(.now) ? lesson : nil
    }

    func replace(with lesson: DailyLesson) {
        self.lesson = lesson
        save()
    }

    func markDone(_ index: Int) {
        guard lesson?.day == ActivityStats.dayKey(.now) else { return }
        lesson?.done.insert(index)
        save()
    }

    /// "Troppo facile" makes the next lessons a bit harder, "troppo difficile" easier.
    func recordFeedback(_ change: Int) {
        let next = max(-1, min(1, difficulty + change))
        UserDefaults.standard.set(next, forKey: Self.difficultyKey)
    }

    private func save() {
        if let lesson, let data = try? JSONEncoder().encode(lesson) {
            UserDefaults.standard.set(data, forKey: Self.lessonKey)
        }
    }
}

/// Builds lessons from the learner's data: locally, or from the coach's plan.
@MainActor
enum DailyLessonBuilder {
    static let defaultMinutes = 10

    /// Every question the learner could get today, with what the planner needs to know.
    static func candidates(words: [Word], phrases: [Phrase], verbs: [Verb], errors: [ErrorRecord]) -> [LessonCandidate] {
        let week = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        var errorCount: [String: Int] = [:]
        for error in errors where error.date >= week {
            guard let id = error.itemID else { continue }
            let family = error.exercise.split(separator: ".").first.map(String.init) ?? ""
            errorCount["\(id.uuidString)|\(family)", default: 0] += 1
        }

        var result: [LessonCandidate] = []
        for word in words {
            for area in StudyArea.allCases where word.isApplicable(to: area) {
                let state = word.srs(for: area)
                let mastery = area.kinds.map { PathPlanner.progress(level: word.kindStreak(for: area, kind: $0)) }
                    .reduce(0, +) / Double(area.kinds.count)
                result.append(LessonCandidate(
                    item: LessonItem(domain: .word, id: word.id, area: area, reason: .practice),
                    theme: word.category, isDue: state.isDue(at: .now), isNew: state.isNew,
                    recentErrors: errorCount["\(word.id.uuidString)|\(area.rawValue)"] ?? 0, mastery: mastery
                ))
            }
        }
        for phrase in phrases {
            result.append(LessonCandidate(
                item: LessonItem(domain: .phrase, id: phrase.id, reason: .practice),
                theme: phrase.category, isDue: phrase.isDue, isNew: phrase.srs.isNew,
                recentErrors: errorCount["\(phrase.id.uuidString)|phrase"] ?? 0,
                mastery: PhraseExercises.mastery([phrase.progressInput])
            ))
        }
        for verb in verbs {
            result.append(LessonCandidate(
                item: LessonItem(domain: .verb, id: verb.id, reason: .practice),
                theme: verb.group.label, isDue: verb.isDue, isNew: verb.srs.isNew,
                recentErrors: errorCount["\(verb.id.uuidString)|verb"] ?? 0,
                mastery: VerbExercises.mastery([verb.kindStreaks])
            ))
        }
        return result
    }

    /// The local lesson: mistakes, two focus themes rotating by day, due reviews, a few new items, numbers.
    static func local(words: [Word], phrases: [Phrase], verbs: [Verb]) -> DailyLesson {
        let activity = ActivityStore.shared
        let candidates = candidates(words: words, phrases: phrases, verbs: verbs, errors: activity.stats.errors)
        let goal = activity.goalMinutes > 0 ? activity.goalMinutes : defaultMinutes

        var scores: [String: (errors: Int, mastery: [Double])] = [:]
        for candidate in candidates {
            guard let theme = candidate.theme else { continue }
            scores[theme, default: (0, [])].errors += candidate.recentErrors
            scores[theme, default: (0, [])].mastery.append(candidate.mastery)
        }
        let themes = scores.map { name, score in
            ThemeScore(name: name, recentErrors: score.errors,
                       mastery: score.mastery.reduce(0, +) / Double(max(score.mastery.count, 1)))
        }
        let dayIndex = Int(Date().timeIntervalSince1970 / 86_400)
        let focus = LessonPlanner.focusThemes(themes, dayIndex: dayIndex)

        var rng = SystemRandomNumberGenerator()
        let items = LessonPlanner.compose(
            candidates: candidates,
            budgetSeconds: goal * 60,
            focusThemes: focus,
            numberLevel: UserDefaults.standard.object(forKey: SettingsKey.numbersLevel) as? Int ?? NumberLevel.upTo20.rawValue,
            difficulty: LessonStore.shared.difficulty,
            using: &rng
        )
        return DailyLesson(day: ActivityStats.dayKey(.now), items: items, focus: focus, fromCoach: false)
    }

    /// What the coach gets: groups with their mastery, number levels and the last mistakes.
    static func summary(words: [Word], phrases: [Phrase], verbs: [Verb], request: String) -> CoachSummary {
        let activity = ActivityStore.shared
        func percent(_ value: Double) -> Int { Int((value * 100).rounded()) }

        let wordThemes = PathPlanner.themeProgress(words.map(\.pathWord)).map { progress in
            CoachSummary.Group(name: progress.theme, items: progress.wordCount,
                               mastery: Dictionary(uniqueKeysWithValues: progress.mastery.map { ($0.key.rawValue, percent($0.value)) }))
        }
        let phraseGroups = phrases.categories.map { category in
            let items = phrases.filter { $0.category == category }
            return CoachSummary.Group(name: category, items: items.count,
                                      mastery: ["all": percent(PhraseExercises.mastery(items.map(\.progressInput)))])
        }
        let verbGroups = verbs.groups.map { group in
            let streaks = verbs.filter { $0.group == group }.map(\.kindStreaks)
            return CoachSummary.Group(name: group.label, items: streaks.count, mastery: [
                "translation": percent(VerbExercises.mastery(streaks, kinds: VerbExerciseKind.translationKinds)),
                "conjugation": percent(VerbExercises.mastery(streaks, kinds: VerbExerciseKind.conjugationKinds)),
            ])
        }
        let numbers = NumberStatsStore.shared.stats
        let numberLevels = Dictionary(uniqueKeysWithValues: NumberLevel.allCases.map {
            (String($0.rawValue), percent(numbers.progress($0)))
        })
        return CoachSummary(
            goalMinutes: activity.goalMinutes > 0 ? activity.goalMinutes : defaultMinutes,
            request: request,
            wordThemes: wordThemes,
            phraseCategories: phraseGroups,
            verbGroups: verbGroups,
            numberLevels: numberLevels,
            recentMistakes: activity.stats.errors.suffix(25).map(CoachSummary.Mistake.init)
        )
    }

    static func fromCoach(_ plan: CoachPlan, words: [Word], phrases: [Phrase], verbs: [Verb]) -> DailyLesson {
        let candidates = candidates(words: words, phrases: phrases, verbs: verbs, errors: ActivityStore.shared.stats.errors)
        var rng = SystemRandomNumberGenerator()
        let items = CoachResolver.resolve(plan, candidates: candidates, using: &rng)
        var seen = Set<String>()
        let focus = plan.blocks.flatMap(\.groups).filter { seen.insert($0).inserted }
        return DailyLesson(day: ActivityStats.dayKey(.now), items: items, message: plan.message,
                           focus: focus, fromCoach: true)
    }

    /// Session steps for the lesson's remaining items, with forced kinds and where each step comes from.
    static func steps(for lesson: DailyLesson, allowSpeaking: Bool)
        -> (steps: [SessionStep], overrides: [SessionStep: String], indexByStep: [SessionStep: Int]) {
        var steps: [SessionStep] = []
        var overrides: [SessionStep: String] = [:]
        var indexByStep: [SessionStep: Int] = [:]
        var rng = SystemRandomNumberGenerator()
        let numberKinds = NumberExerciseKind.allCases.filter { allowSpeaking || $0 != .speak }

        for index in lesson.remaining {
            let item = lesson.items[index]
            let step: SessionStep
            switch item.domain {
            case .word:
                guard let id = item.id, let area = item.area else { continue }
                step = .word(StudyItem(wordID: id, area: area))
            case .phrase:
                guard let id = item.id else { continue }
                step = .phrase(id)
            case .verb:
                guard let id = item.id else { continue }
                step = .verb(id)
            case .number:
                let level = NumberLevel(rawValue: item.numberLevel ?? 1) ?? .upTo20
                let forced = item.kind.flatMap(NumberExerciseKind.init(rawValue:))
                let kind = forced.flatMap { allowSpeaking || $0 != .speak ? $0 : nil }
                    ?? numberKinds.randomElement(using: &rng) ?? .listenChoice
                step = .number(NumberQuiz.make(kind: kind, level: level, stats: NumberStatsStore.shared.stats, using: &rng))
            }
            guard indexByStep[step] == nil else { continue }
            steps.append(step)
            indexByStep[step] = index
            if let kind = item.kind, item.domain != .number {
                overrides[step] = kind
            }
        }
        return (steps, overrides, indexByStep)
    }
}
