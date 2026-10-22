import LearnCore
import SwiftData
import SwiftUI

/// Free practice: pick area, themes and kind of exercise by hand.
struct FreePracticeView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.area) private var areaRaw = StudyArea.translation.rawValue
    @AppStorage(SettingsKey.studyMode) private var modeRaw = StudyMode.mixed.rawValue
    @AppStorage(SettingsKey.excludedThemes) private var excludedThemesRaw = "[]"
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?

    private var area: StudyArea { StudyArea(rawValue: areaRaw) ?? .translation }

    private var mode: StudyMode {
        let mode = StudyMode(rawValue: modeRaw) ?? .mixed
        return StudyMode.available(in: area).contains(mode) ? mode : .mixed
    }

    private var excludedThemes: Set<String> { ThemeSelection.decode(excludedThemesRaw) }

    /// Words of the selected themes that take part in the selected area.
    private var studyWords: [Word] {
        let excluded = excludedThemes
        return words.filter { !excluded.contains($0.category) && $0.isApplicable(to: area) }
    }

    private var dueCount: Int { studyWords.filter { $0.isDue(in: area) }.count }

    private var themesSummary: String {
        let all = words.categories
        let selected = all.filter { !excludedThemes.contains($0) }
        if selected.count == all.count { return "Tutti" }
        if selected.isEmpty { return "Nessuno" }
        return selected.count == 1 ? selected[0] : "\(selected.count) di \(all.count)"
    }

    var body: some View {
        form
            .navigationTitle("Allenamento libero")
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

    private var form: some View {
        Form {
            Section {
                HStack {
                    stat(value: dueCount, label: "da ripassare")
                    Divider()
                    stat(value: studyWords.count, label: "parole")
                }
                .padding(.vertical, 8)
            }

            Section {
                Picker("Area", selection: $areaRaw) {
                    ForEach(StudyArea.allCases, id: \.self) { area in
                        Text(area.title).tag(area.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Cosa alleni")
            } footer: {
                Text(area.explanation)
            }

            Section("Temi") {
                NavigationLink {
                    ThemePickerView(themes: words.categories, excludedRaw: $excludedThemesRaw)
                } label: {
                    LabeledContent("Temi", value: themesSummary)
                }
            }

            Section("Esercizio") {
                Picker("Esercizio", selection: $modeRaw) {
                    ForEach(StudyMode.available(in: area)) { mode in
                        Label(mode.title(in: area), systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Button {
                    start(extra: false)
                } label: {
                    Label(dueCount == 0 ? "Niente da ripassare" : "Inizia ripasso (\(min(dueCount, sessionSize)))",
                          systemImage: "play.fill")
                }
                .disabled(dueCount == 0)

                Button {
                    start(extra: true)
                } label: {
                    Label("Allenamento extra", systemImage: "dumbbell")
                }
                .disabled(studyWords.isEmpty)
            } footer: {
                if studyWords.isEmpty {
                    Text(area == .translation
                         ? "Nessuna parola nei temi selezionati."
                         : "Nessun sostantivo adatto a questo esercizio nei temi selezionati.")
                } else {
                    Text("L'allenamento extra aggiunge le parole che scadono più presto; il loro calendario di ripasso non cambia.")
                }
            }
        }
        .onChange(of: areaRaw) { _, _ in
            // "Scrivi in inglese" exists only for translation.
            if !StudyMode.available(in: area).contains(where: { $0.rawValue == modeRaw }) {
                modeRaw = StudyMode.mixed.rawValue
            }
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack {
            Text("\(value)")
                .font(.largeTitle.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func start(extra: Bool) {
        let mode = self.mode
        let area = self.area
        let candidates = studyWords.map { $0.candidate(for: area, kind: mode.kind) }
        Task { @MainActor in
            var allowSpeaking = false
            if mode == .speakGerman || (mode == .mixed && speakingInMixed) {
                allowSpeaking = await SpeechRecognizer.requestPermissions()
                if mode == .speakGerman && !allowSpeaking {
                    alertMessage = SpeechRecognizer.permissionDeniedMessage
                    return
                }
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: sessionSize, includeNotDue: extra)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(
                items: ids.map { StudyItem(wordID: $0, area: area) },
                allWords: words,
                kindPolicy: .fixed(mode.kind),
                allowSpeaking: allowSpeaking,
                context: context
            )
        }
    }
}

/// Multi-select of the themes to study.
struct ThemePickerView: View {
    let themes: [String]
    @Binding var excludedRaw: String

    private var excluded: Set<String> { ThemeSelection.decode(excludedRaw) }

    var body: some View {
        List {
            Section {
                Button("Seleziona tutti") { excludedRaw = ThemeSelection.encode([]) }
                Button("Deseleziona tutti") { excludedRaw = ThemeSelection.encode(Set(themes)) }
            }
            Section {
                ForEach(themes, id: \.self) { theme in
                    Button {
                        toggle(theme)
                    } label: {
                        HStack {
                            Text(theme)
                                .foregroundStyle(.primary)
                            Spacer()
                            if !excluded.contains(theme) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Temi")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ theme: String) {
        var excluded = self.excluded
        if excluded.contains(theme) {
            excluded.remove(theme)
        } else {
            excluded.insert(theme)
        }
        excludedRaw = ThemeSelection.encode(excluded)
    }
}
