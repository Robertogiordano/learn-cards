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
    @State private var alertMessage: String?
    @State private var expandedAreas: Set<StudyArea> = []

    private var themeWords: [Word] {
        words.filter { $0.category == theme }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let themeWords = self.themeWords
        let progress = PathPlanner.themeProgress(themeWords.map(\.pathWord)).first

        return List {
            Section {
                ForEach(StudyArea.allCases, id: \.self) { area in
                    if let progress, progress.mastery[area] != nil {
                        areaRow(area, progress: progress, words: themeWords.filter { $0.isApplicable(to: area) })
                    }
                }
            } footer: {
                Text("Ogni tipo di esercizio ha la sua percentuale: una risposta giusta vale metà parola, due di fila la parola intera, un errore la fa ripartire. La percentuale dell'area è la media dei suoi esercizi e la stella si accende all’80%. “Automatico” sceglie l'esercizio in base a quanto conosci ogni parola.")
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
        .alert("Attenzione", isPresented: Binding(isPresent: $alertMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func areaRow(_ area: StudyArea, progress: ThemeProgress, words: [Word]) -> some View {
        let mastery = progress.mastery[area] ?? 0
        let hasStar = progress.hasStar(area)
        let due = words.filter { !$0.srs(for: area).isNew && $0.isDue(in: area) }.count
        let new = words.filter { $0.srs(for: area).isNew }.count
        let isExpanded = expandedAreas.contains(area)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(area.title, systemImage: area.systemImage)
                    .font(.headline)
                Spacer()
                Text(percent(mastery))
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
                Button {
                    withAnimation {
                        if isExpanded { expandedAreas.remove(area) } else { expandedAreas.insert(area) }
                    }
                } label: {
                    Label("Allena", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    optionRow(title: "Automatico (percorso)", systemImage: "wand.and.stars", value: nil, color: area.color) {
                        start(area, words: words, policy: .adaptive)
                    }
                    optionRow(title: StudyMode.mixed.title(in: area), systemImage: StudyMode.mixed.systemImage,
                              value: nil, color: area.color) {
                        start(area, words: words, policy: .fixed(nil))
                    }
                    ForEach(area.kinds, id: \.self) { kind in
                        let mode = StudyMode(rawValue: kind.rawValue) ?? .mixed
                        optionRow(title: mode.title(in: area), systemImage: mode.systemImage,
                                  value: progress.kindMastery[area]?[kind] ?? 0, color: area.color) {
                            start(area, words: words, policy: .fixed(kind))
                        }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)
    }

    /// One way to train an area; kinds of exercise show their own percentage.
    private func optionRow(title: String, systemImage: String, value: Double?, color: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .foregroundStyle(.primary)
                    Spacer()
                    if let value {
                        Text(percent(value))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(color)
                }
                if let value {
                    ProgressView(value: value)
                        .tint(color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Due reviews first, then new words, then the ones closest to being due.
    /// `policy` is automatic (by how well each word is known) or one chosen kind of exercise.
    private func start(_ area: StudyArea, words: [Word], policy: KindPolicy) {
        let candidates = words.map { $0.candidate(for: area) }
        let speakingOnly: Bool
        if case .fixed(.speakGerman?) = policy { speakingOnly = true } else { speakingOnly = false }
        Task { @MainActor in
            let allowSpeaking = speakingOnly || speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            if speakingOnly && !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: sessionSize, includeNotDue: true)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(items: ids.map { StudyItem(wordID: $0, area: area) }, allWords: self.words,
                                         kindPolicy: policy, allowSpeaking: allowSpeaking, context: context)
        }
    }
}
