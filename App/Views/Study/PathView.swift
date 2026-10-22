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
    @ObservedObject private var lessons = LessonStore.shared

    /// Number questions mixed into every bonus.
    private static let bonusNumbers = 3
    /// Phrases already seen, mixed into every bonus.
    private static let bonusPhrases = 2
    /// Verbs already seen, mixed into every bonus.
    private static let bonusVerbs = 2

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Ancora nessuna parola",
                        systemImage: "camera",
                        description: Text("Fotografa una pagina di esercizi dalla scheda Aggiungi per iniziare il percorso.")
                    )
                } else {
                    path
                }
            }
            .navigationTitle("Studia")
            .fullScreenCover(item: $activeSession) { session in
                SessionView(session: session)
            }
            .sheet(isPresented: $isAskingCoach) {
                CoachSheet { lesson in
                    lessons.replace(with: lesson)
                    startLesson()
                }
            }
            .onAppear(perform: prepareTodaysLesson)
        }
    }

    private var path: some View {
        let pathWords = words.map(\.pathWord)
        let now = Date()
        let lesson = PathPlanner.lesson(pathWords, now: now, newLimit: lessonNewWords)
        let lessonBonus = PathPlanner.bonus(pathWords, now: now, limit: bonusSize, excluding: Set(lesson)).count
            + Self.bonusNumbers + bonusPhraseIDs().count + bonusVerbIDs().count
        let bonusOnly = PathPlanner.bonus(pathWords, now: now, limit: bonusSize).count + Self.bonusNumbers
            + bonusPhraseIDs().count + bonusVerbIDs().count
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
                    Label("Bonus · ripasso misto (\(bonusOnly))", systemImage: "gift")
                }
                .disabled(bonusOnly == 0)

                NavigationLink {
                    FreePracticeView()
                } label: {
                    Label("Allenamento libero: scegli area, temi ed esercizio", systemImage: "slider.horizontal.3")
                }
            } footer: {
                Text("Il bonus mescola tutto quello che hai già visto, in tutti i temi e gli esercizi: prima le parole da ripassare, poi quelle che sbagli più spesso.")
            }

            Section("Numeri, frasi e verbi") {
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
            }

            Section("Temi") {
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
            let plan = DailyLessonBuilder.steps(for: lesson, allowSpeaking: allowSpeaking)
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

    /// Bonus words with a few number questions, at the level being trained, spread among them.
    private func bonusSteps(_ items: [StudyItem], allowSpeaking: Bool) -> [SessionStep] {
        let level = NumberLevel(rawValue: numbersLevelRaw) ?? .upTo20
        var steps = items.map { SessionStep.word($0) }
        let extras = NumberSteps.make(count: Self.bonusNumbers, level: level, kind: nil, allowSpeaking: allowSpeaking)
            + bonusPhraseIDs().map { SessionStep.phrase($0) }
            + bonusVerbIDs().map { SessionStep.verb($0) }
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
        if lessonCount == 0 && bonusCount == 0 { return "Tutto ripassato per oggi 🎉" }
        var parts: [String] = []
        if let theme, lessonCount > 0 { parts.append("\(theme) · \(lessonCount) domande") }
        if bonusCount > 0 { parts.append("+ \(bonusCount) di bonus") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("Continua il percorso")
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
                        Text("+\(progress.newCount) nuove")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                    }
                }
                Text(progress.wordCount == 1 ? "1 parola" : "\(progress.wordCount) parole")
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
                        .accessibilityLabel("\(area.title): \(progress.hasStar(area) ? "completata" : "da completare")")
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
