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
                Text("La stella si accende quando padroneggi l'80% delle parole: due risposte giuste di fila. Con \"Automatico\" le parole nuove partono dalla scelta multipla, poi si scrivono e infine si pronunciano; dal menu Allena puoi anche scegliere tu il tipo di esercizio.")
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
                Menu {
                    Button {
                        start(area, words: words, policy: .adaptive)
                    } label: {
                        Label("Automatico (percorso)", systemImage: "wand.and.stars")
                    }
                    Divider()
                    ForEach(StudyMode.available(in: area)) { mode in
                        Button {
                            start(area, words: words, policy: .fixed(mode.kind))
                        } label: {
                            Label(mode.title(in: area), systemImage: mode.systemImage)
                        }
                    }
                } label: {
                    Label("Allena", systemImage: "chevron.down")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
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
