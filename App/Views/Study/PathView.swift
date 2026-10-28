import LearnCore
import SwiftData
import SwiftUI

/// The Study tab: "continue" lesson + bonus, the theme map with stars, free practice.
struct PathView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @Query private var phrases: [Phrase]
    @Query private var verbs: [Verb]
    @AppStorage(SettingsKey.lessonNewWords) private var lessonNewWords = 8
    @AppStorage(SettingsKey.bonusSize) private var bonusSize = 15
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @AppStorage(SettingsKey.numbersLevel) private var numbersLevelRaw = NumberLevel.upTo20.rawValue
    @State private var activeSession: StudySession?
    @State private var isAskingCoach = false
    /// Set by the coach: the lesson starts once its sheet has finished closing.
    @State private var startLessonAfterCoach = false
    @ObservedObject private var lessons = LessonStore.shared

    /// Number questions mixed into every bonus.
    private static let bonusNumbers = 3
    /// Phrases already seen, mixed into every bonus.
    private static let bonusPhrases = 2
    /// Verbs already seen, mixed into every bonus.
    private static let bonusVerbs = 2
    /// Compounds in a bonus match round, or single compound questions when they cannot be matched.
    private static let bonusCompoundPairs = 5
    private static let bonusCompounds = 2

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "No words yet",
                        systemImage: "camera",
                        description: Text("Take a photo of an exercise page from the Add tab to start your path.")
                    )
                } else {
                    path
                }
            }
            .navigationTitle("Study")
            .fullScreenCover(item: $activeSession) { session in
                SessionView(session: session)
            }
            // Presenting the session while the coach sheet is still closing leaves it
            // without a background: start it from onDismiss instead.
            .sheet(isPresented: $isAskingCoach, onDismiss: {
                if startLessonAfterCoach {
                    startLessonAfterCoach = false
                    startLesson()
                }
            }) {
                CoachSheet { lesson in
                    lessons.replace(with: lesson)
                    startLessonAfterCoach = true
                }
            }
            .onAppear(perform: prepareTodaysLesson)
        }
    }

    private var path: some View {
        let pathWords = words.map(\.pathWord)
        let now = Date()
        let lesson = PathPlanner.lesson(pathWords, now: now, newLimit: lessonNewWords)
        let extras = Self.bonusNumbers + bonusPhraseIDs().count + bonusVerbIDs().count + bonusCompoundSteps().count
        let lessonBonus = PathPlanner.bonus(pathWords, now: now, limit: bonusSize, excluding: Set(lesson)).count + extras
        let bonusOnly = PathPlanner.bonus(pathWords, now: now, limit: bonusSize).count + extras
        let focus = PathPlanner.focusTheme(pathWords)
        let emojis = Dictionary(words.map { ($0.category, $0.emoji) }, uniquingKeysWith: { first, _ in first })

        return List {
            Section {
                TodayCard(onStartLesson: startLesson, onAskCoach: { isAskingCoach = true })
            }

            Section {
                Button(action: startContinue) {
                    ContinueCard(theme: lesson.isEmpty ? nil : focus, lessonCount: lesson.count, bonusCount: lessonBonus)
                }
                .buttonStyle(.plain)
                .disabled(lesson.isEmpty && lessonBonus == 0)

                Button(action: startBonus) {
                    Label("Bonus · mixed review (\(bonusOnly))", systemImage: "gift")
                }
                .disabled(bonusOnly == 0)

                NavigationLink {
                    FreePracticeView()
                } label: {
                    Label("Free practice: choose area, themes and exercise", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("The bonus mixes everything you have already seen, across all themes and exercises: words due for review first, then the ones you miss most.")
            }

            Section("More practice") {
                NavigationLink {
                    NumbersView()
                } label: {
                    NumbersRow()
                }
                NavigationLink {
                    PhrasesView()
                } label: {
                    PhrasesRow()
                }
                NavigationLink {
                    VerbsView()
                } label: {
                    VerbsRow()
                }
                NavigationLink {
                    CompoundsView()
                } label: {
                    CompoundsRow()
                }
            }

            Section("Word sets") {
                NavigationLink {
                    WordSetsView()
                } label: {
                    WordSetsRow()
                }
            }

            Section("Themes") {
                ForEach(PathPlanner.themeProgress(pathWords)) { progress in
                    NavigationLink {
                        ThemeDetailView(theme: progress.theme)
                    } label: {
                        ThemeRow(progress: progress, emoji: emojis[progress.theme] ?? "📝")
                    }
                }
            }
        }
    }

    /// The local lesson is prepared once a day, the first time the tab is shown.
    private func prepareTodaysLesson() {
        guard lessons.today == nil, !words.isEmpty || !phrases.isEmpty || !verbs.isEmpty else { return }
        lessons.replace(with: DailyLessonBuilder.local(words: words, phrases: phrases, verbs: verbs))
    }

    /// Starts (or resumes) today's lesson; a finished lesson can be done again.
    private func startLesson() {
        prepareTodaysLesson()
        guard var lesson = lessons.today else { return }
        if lesson.isComplete {
            lesson.done = []
            lessons.replace(with: lesson)
        }
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let levels = Dictionary(words.filter(\.isCompound).map { ($0.id, CompoundSession.adaptiveLevel(of: $0)) },
                                    uniquingKeysWith: { first, _ in first })
            let plan = DailyLessonBuilder.steps(for: lesson, allowSpeaking: allowSpeaking, compoundLevels: levels)
            guard !plan.steps.isEmpty else { return }
            let session = StudySession(steps: plan.steps, allWords: words, allPhrases: phrases, allVerbs: verbs,
                                       kindPolicy: .adaptive, kindOverrides: plan.overrides,
                                       allowSpeaking: allowSpeaking, context: context)
            session.isLesson = true
            session.onStepGraded = { step in
                if let index = plan.indexByStep[step] { lessons.markDone(index) }
            }
            activeSession = session
        }
    }

    private func startContinue() {
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let pathWords = words.map(\.pathWord)
            let lesson = PathPlanner.lesson(pathWords, now: .now, newLimit: lessonNewWords)
            let bonus = PathPlanner.bonus(pathWords, now: .now, limit: bonusSize, excluding: Set(lesson))
            let steps = lesson.map { SessionStep.word($0) } + bonusSteps(bonus, allowSpeaking: allowSpeaking)
            activeSession = StudySession(steps: steps, bonusFrom: lesson.count, allWords: words, allPhrases: phrases,
                                         allVerbs: verbs, kindPolicy: .adaptive, allowSpeaking: allowSpeaking,
                                         context: context)
        }
    }

    private func startBonus() {
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let bonus = PathPlanner.bonus(words.map(\.pathWord), now: .now, limit: bonusSize)
            activeSession = StudySession(steps: bonusSteps(bonus, allowSpeaking: allowSpeaking), bonusFrom: 0,
                                         allWords: words, allPhrases: phrases, allVerbs: verbs, kindPolicy: .adaptive,
                                         allowSpeaking: allowSpeaking, context: context)
        }
    }

    /// Phrases already seen for the bonus: the due ones first, then the most missed.
    private func bonusPhraseIDs() -> [UUID] {
        let seen = phrases.filter { !$0.srs.isNew }
        let ranked = seen.sorted { lhs, rhs in
            if lhs.isDue != rhs.isDue { return lhs.isDue }
            if lhs.lapses != rhs.lapses { return lhs.lapses > rhs.lapses }
            return lhs.dueDate < rhs.dueDate
        }
        return ranked.prefix(Self.bonusPhrases).map(\.id)
    }

    /// Verbs already seen for the bonus: the due ones first, then the most missed.
    private func bonusVerbIDs() -> [UUID] {
        let seen = verbs.filter { !$0.srs.isNew }
        let ranked = seen.sorted { lhs, rhs in
            if lhs.isDue != rhs.isDue { return lhs.isDue }
            if lhs.lapses != rhs.lapses { return lhs.lapses > rhs.lapses }
            return lhs.dueDate < rhs.dueDate
        }
        return ranked.prefix(Self.bonusVerbs).map(\.id)
    }

    /// Compounds already seen for the bonus, weakest first: one match round when five can be
    /// matched together, otherwise up to two single questions.
    private func bonusCompoundSteps() -> [SessionStep] {
        let seen = words.filter { $0.isCompound && (!$0.compoundStreaks.isEmpty || !$0.srs(for: .translation).isNew) }
            .sorted { CompoundGame.mastery([$0.compoundStreaks]) < CompoundGame.mastery([$1.compoundStreaks]) }
        if let round = CompoundSession.matchRounds(Array(seen.prefix(Self.bonusCompoundPairs))).rounds.first {
            return [.compound(round)]
        }
        var rng = SystemRandomNumberGenerator()
        return seen.prefix(Self.bonusCompounds).map { word in
            var kind = CompoundGame.kind(level: CompoundSession.adaptiveLevel(of: word), canMatch: false, using: &rng)
            if kind == .matchPairs { kind = .completeWord }
            return .compound(CompoundStep(kind: kind, ids: [word.id]))
        }
    }

    /// Bonus words with a few number questions, at the level being trained, spread among them.
    private func bonusSteps(_ items: [StudyItem], allowSpeaking: Bool) -> [SessionStep] {
        let level = NumberLevel(rawValue: numbersLevelRaw) ?? .upTo20
        var steps = items.map { SessionStep.word($0) }
        let extras = NumberSteps.make(count: Self.bonusNumbers, level: level, kind: nil, allowSpeaking: allowSpeaking)
            + bonusPhraseIDs().map { SessionStep.phrase($0) }
            + bonusVerbIDs().map { SessionStep.verb($0) }
            + bonusCompoundSteps()
        for extra in extras {
            steps.insert(extra, at: Int.random(in: 0...steps.count))
        }
        return steps
    }
}

private struct ContinueCard: View {
    let theme: String?
    let lessonCount: Int
    let bonusCount: Int

    private var subtitle: String {
        if lessonCount == 0 && bonusCount == 0 { return "All reviewed for today 🎉" }
        var parts: [String] = []
        if let theme, lessonCount > 0 { parts.append("\(theme) · \(lessonCount) questions") }
        if bonusCount > 0 { parts.append("+ \(bonusCount) bonus") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Continue your path")
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

struct ThemeRow: View {
    let progress: ThemeProgress
    let emoji: String

    var body: some View {
        HStack(spacing: 12) {
            Text(emoji)
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(progress.theme)
                        .font(.headline)
                    if progress.newCount > 0 {
                        Text("+\(progress.newCount) new")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                Text(progress.wordCount == 1 ? "1 word" : "\(progress.wordCount) words")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StarsView(progress: progress)
        }
    }
}

/// One star per area (translation, article, plural) the theme has words for.
struct StarsView: View {
    let progress: ThemeProgress

    var body: some View {
        HStack(spacing: 3) {
            ForEach(StudyArea.allCases, id: \.self) { area in
                if progress.mastery[area] != nil {
                    Image(systemName: progress.hasStar(area) ? "star.fill" : "star")
                        .foregroundStyle(progress.hasStar(area) ? area.color : Color.secondary)
                        .accessibilityLabel("\(area.title): \(progress.hasStar(area) ? "complete" : "to complete")")
                }
            }
        }
        .font(.subheadline)
    }
}

extension StudyArea {
    var color: Color {
        switch self {
        case .translation: return .orange
        case .article: return .blue
        case .plural: return .purple
        }
    }

    var systemImage: String {
        switch self {
        case .translation: return "character.bubble"
        case .article: return "textformat"
        case .plural: return "square.stack.3d.up"
        }
    }
}
