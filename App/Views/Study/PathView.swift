import LearnCore
import SwiftData
import SwiftUI

/// The Study tab: "continue" lesson + bonus, the theme map with stars, free practice.
struct PathView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.lessonNewWords) private var lessonNewWords = 8
    @AppStorage(SettingsKey.bonusSize) private var bonusSize = 15
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var activeSession: StudySession?

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
        }
    }

    private var path: some View {
        let pathWords = words.map(\.pathWord)
        let now = Date()
        let lesson = PathPlanner.lesson(pathWords, now: now, newLimit: lessonNewWords)
        let lessonBonus = PathPlanner.bonus(pathWords, now: now, limit: bonusSize, excluding: Set(lesson)).count
        let bonusOnly = PathPlanner.bonus(pathWords, now: now, limit: bonusSize).count
        let focus = PathPlanner.focusTheme(pathWords)
        let emojis = Dictionary(words.map { ($0.category, $0.emoji) }, uniquingKeysWith: { first, _ in first })

        return List {
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

    private func startContinue() {
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let pathWords = words.map(\.pathWord)
            let lesson = PathPlanner.lesson(pathWords, now: .now, newLimit: lessonNewWords)
            let bonus = PathPlanner.bonus(pathWords, now: .now, limit: bonusSize, excluding: Set(lesson))
            guard !(lesson + bonus).isEmpty else { return }
            activeSession = StudySession(items: lesson + bonus, bonusFrom: lesson.count, allWords: words,
                                         kindPolicy: .adaptive, allowSpeaking: allowSpeaking, context: context)
        }
    }

    private func startBonus() {
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let bonus = PathPlanner.bonus(words.map(\.pathWord), now: .now, limit: bonusSize)
            guard !bonus.isEmpty else { return }
            activeSession = StudySession(items: bonus, bonusFrom: 0, allWords: words,
                                         kindPolicy: .adaptive, allowSpeaking: allowSpeaking, context: context)
        }
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
