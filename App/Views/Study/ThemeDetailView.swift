import LearnCore
import SwiftData
import SwiftUI

/// One theme of the path: progress per area and a session to train each one.
struct ThemeDetailView: View {
    let theme: String

    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var activeSession: StudySession?

    private var themeWords: [Word] {
        words.filter { $0.category == theme }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let themeWords = self.themeWords
        let progress = PathPlanner.themeProgress(themeWords.map(\.pathWord)).first

        return List {
            Section {
                ForEach(StudyArea.allCases, id: \.self) { area in
                    if let mastery = progress?.mastery[area] {
                        areaRow(area, mastery: mastery, words: themeWords.filter { $0.isApplicable(to: area) },
                                hasStar: progress?.hasStar(area) ?? false)
                    }
                }
            } footer: {
                Text("La stella si accende quando padroneggi l'80% delle parole: due risposte giuste di fila. Le parole nuove partono dalla scelta multipla, poi si scrivono e infine si pronunciano.")
            }

            Section("Parole") {
                ForEach(themeWords) { word in
                    WordRow(word: word)
                }
            }
        }
        .navigationTitle(theme)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeSession) { session in
            SessionView(session: session)
        }
    }

    private func areaRow(_ area: StudyArea, mastery: Double, words: [Word], hasStar: Bool) -> some View {
        let due = words.filter { !$0.srs(for: area).isNew && $0.isDue(in: area) }.count
        let new = words.filter { $0.srs(for: area).isNew }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(area.title, systemImage: area.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(Int((mastery * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: hasStar ? "star.fill" : "star")
                    .foregroundStyle(hasStar ? area.color : Color.secondary)
            }
            ProgressView(value: mastery)
                .tint(area.color)
            HStack {
                Text("\(due) da ripassare · \(new) nuove")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Allena") { start(area, words: words) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    /// Due reviews first, then new words, then the ones closest to being due.
    private func start(_ area: StudyArea, words: [Word]) {
        let candidates = words.map { $0.candidate(for: area) }
        Task { @MainActor in
            let allowSpeaking = speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            let ids = SessionPlanner.select(candidates, now: .now, limit: sessionSize, includeNotDue: true)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(items: ids.map { StudyItem(wordID: $0, area: area) }, allWords: self.words,
                                         kindPolicy: .adaptive, allowSpeaking: allowSpeaking, context: context)
        }
    }
}
