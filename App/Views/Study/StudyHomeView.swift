import LearnCore
import SwiftData
import SwiftUI

struct StudyHomeView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.level) private var levelRaw = StudyLevel.translation.rawValue
    @AppStorage(SettingsKey.studyMode) private var modeRaw = StudyMode.mixed.rawValue
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?

    private var level: StudyLevel { StudyLevel(rawValue: levelRaw) ?? .translation }
    private var mode: StudyMode { StudyMode(rawValue: modeRaw) ?? .mixed }
    private var dueCount: Int { words.filter(\.isDue).count }

    var body: some View {
        NavigationStack {
            Group {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Ancora nessuna parola",
                        systemImage: "camera",
                        description: Text("Fotografa una pagina di esercizi dalla scheda Aggiungi per iniziare.")
                    )
                } else {
                    form
                }
            }
            .navigationTitle("Studia")
            .fullScreenCover(item: $activeSession) { session in
                SessionView(session: session)
            }
            .alert("Attenzione", isPresented: Binding(isPresent: $alertMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack {
                    stat(value: dueCount, label: "da ripassare")
                    Divider()
                    stat(value: words.count, label: "parole")
                }
                .padding(.vertical, 8)
            }

            Section {
                Picker("Livello", selection: $levelRaw) {
                    ForEach(StudyLevel.allCases, id: \.self) { level in
                        Text(level.shortTitle).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Livello")
            } footer: {
                Text(level.explanation)
            }

            Section("Esercizio") {
                Picker("Esercizio", selection: $modeRaw) {
                    ForEach(StudyMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section {
                Button {
                    start(extra: false)
                } label: {
                    Label(dueCount == 0 ? "Niente da ripassare oggi" : "Inizia ripasso (\(min(dueCount, sessionSize)))",
                          systemImage: "play.fill")
                }
                .disabled(dueCount == 0)

                Button {
                    start(extra: true)
                } label: {
                    Label("Allenamento extra", systemImage: "dumbbell")
                }
            } footer: {
                Text("L'allenamento extra aggiunge le parole che scadono più presto; il loro calendario di ripasso non cambia.")
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
        let level = self.level
        Task { @MainActor in
            var allowSpeaking = false
            if mode == .speakGerman || (mode == .mixed && speakingInMixed) {
                allowSpeaking = await SpeechRecognizer.requestPermissions()
                if mode == .speakGerman && !allowSpeaking {
                    alertMessage = "Per gli esercizi di pronuncia consenti microfono e riconoscimento vocale in Impostazioni > LearnCards."
                    return
                }
            }
            let ids = SessionPlanner.select(words.map(\.candidate), now: .now, limit: sessionSize, includeNotDue: extra)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(
                wordIDs: ids,
                allWords: words,
                level: level,
                mode: mode.kind,
                allowSpeaking: allowSpeaking,
                context: context
            )
        }
    }
}
