import LearnCore
import SwiftData
import SwiftUI

extension PhraseExerciseKind {
    var systemImage: String {
        switch self {
        case .reorder: return "square.stack.3d.forward.dottedline"
        case .translate: return "keyboard"
        case .questionFromAnswer: return "questionmark.bubble"
        case .cloze: return "text.insert"
        case .dictation: return "ear"
        case .speak: return "mic"
        }
    }
}

extension Color {
    static let phrases = Color.indigo
}

/// Row of the phrase section on the path.
struct PhrasesRow: View {
    @Query private var phrases: [Phrase]

    var body: some View {
        HStack(spacing: 12) {
            Text("💬")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Frasi")
                    .font(.headline)
                Text(phrases.isEmpty ? "Carica frasi dalla scheda Aggiungi"
                                     : "\(phrases.count) frasi · \(phrases.categories.count) categorie")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !phrases.isEmpty {
                ProgressRing(value: PhraseExercises.mastery(phrases.map(\.progressInput)), color: .phrases)
                    .frame(width: 38, height: 38)
            }
        }
    }
}

/// Phrase practice: pick a category (or all), then a kind of exercise.
struct PhrasesView: View {
    @Environment(\.modelContext) private var context
    @Query private var phrases: [Phrase]
    @Query private var words: [Word]
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var category: String?
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?

    private static let sessionLength = 10

    private var scoped: [Phrase] {
        category.map { selected in phrases.filter { $0.category == selected } } ?? phrases
    }

    var body: some View {
        let scoped = self.scoped
        let inputs = scoped.map(\.progressInput)
        let kinds = PhraseExercises.kindMastery(inputs)
        let due = scoped.filter { !$0.srs.isNew && $0.isDue }.count
        let new = scoped.filter { $0.srs.isNew }.count

        return List {
            if phrases.isEmpty {
                ContentUnavailableView(
                    "Ancora nessuna frase",
                    systemImage: "text.bubble",
                    description: Text("Nella scheda Aggiungi scegli «Frasi» e fotografa una pagina con frasi, modi di dire o esercizi.")
                )
            } else {
                Section {
                    categoryChips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category ?? "Tutte le frasi")
                                .font(.title3.bold())
                            Text("\(scoped.count) frasi · \(due) da ripassare · \(new) nuove")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressRing(value: PhraseExercises.mastery(inputs), color: .phrases)
                            .frame(width: 54, height: 54)
                    }
                    .padding(.vertical, 4)

                    Button {
                        start(.adaptive, wantsSpeaking: speakingInMixed)
                    } label: {
                        Label("Allena in automatico", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.phrases)
                    .controlSize(.large)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(PhraseExerciseKind.allCases, id: \.self) { kind in
                            if let value = kinds[kind] {
                                ExerciseTile(title: kind.title, systemImage: kind.systemImage, value: value, color: .phrases) {
                                    start(.fixed(kind), wantsSpeaking: kind == .speak)
                                }
                            }
                        }
                        ExerciseTile(title: "Misto", systemImage: "shuffle", value: nil, color: .phrases) {
                            start(.mixed, wantsSpeaking: speakingInMixed)
                        }
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text("Ogni esercizio ha la sua percentuale: una risposta giusta vale metà frase, due di fila la frase intera. «Automatico» parte dal ricomporre la frase e arriva a scriverla e dirla.")
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Frasi")
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

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tutte", value: PhraseExercises.mastery(phrases.map(\.progressInput)), selected: category == nil) {
                    category = nil
                }
                ForEach(phrases.categories, id: \.self) { name in
                    let items = phrases.filter { $0.category == name }.map(\.progressInput)
                    chip(title: name, value: PhraseExercises.mastery(items), selected: category == name) {
                        category = name
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func chip(title: String, value: Double, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("\(Int((value * 100).rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(Capsule().fill(selected ? Color.phrases : Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    /// Due phrases first, then new ones, then the closest to being due.
    private func start(_ policy: PhrasePolicy, wantsSpeaking: Bool) {
        let candidates = scoped.map(\.candidate)
        Task { @MainActor in
            let allowSpeaking = wantsSpeaking ? await SpeechRecognizer.requestPermissions() : false
            if case .fixed(.speak) = policy, !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: Self.sessionLength, includeNotDue: true)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(steps: ids.map { .phrase($0) }, allWords: words, allPhrases: phrases,
                                         kindPolicy: .adaptive, phrasePolicy: policy,
                                         allowSpeaking: allowSpeaking, context: context)
        }
    }
}
