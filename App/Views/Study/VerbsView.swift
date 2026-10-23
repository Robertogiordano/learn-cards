import LearnCore
import SwiftData
import SwiftUI

extension VerbExerciseKind {
    var systemImage: String {
        switch self {
        case .chooseForm: return "square.grid.2x2"
        case .typeForm: return "keyboard"
        case .fullTable: return "tablecells"
        case .whichPerson: return "person.2"
        case .speak: return "mic"
        case .translateChoice: return "square.grid.2x2.fill"
        case .translateGerman: return "character.bubble"
        case .translateEnglish: return "character.cursor.ibeam"
        case .translateSpeak: return "waveform"
        }
    }
}

extension Color {
    static let verbs = Color.mint
}

/// Row of the verb section on the path.
struct VerbsRow: View {
    @Query private var verbs: [Verb]

    var body: some View {
        HStack(spacing: 12) {
            Text("🔤")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verbs")
                    .font(.headline)
                Text(verbs.isEmpty ? "Add verbs from the Add tab" : "\(verbs.count) verbs · present")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !verbs.isEmpty {
                ProgressRing(value: VerbExercises.mastery(verbs.map(\.kindStreaks)), color: .verbs)
                    .frame(width: 38, height: 38)
            }
        }
    }
}

/// Present-tense practice: pick a group (or all), then a kind of exercise.
struct VerbsView: View {
    @Environment(\.modelContext) private var context
    @Query private var verbs: [Verb]
    @Query private var words: [Word]
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var group: VerbGroup?
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?

    private static let sessionLength = 10
    /// New verbs per session when there are reviews too: a few at a time stick better.
    private static let newPerSession = 4

    private var scoped: [Verb] {
        group.map { selected in verbs.filter { $0.group == selected } } ?? verbs
    }

    var body: some View {
        let scoped = self.scoped
        let streaks = scoped.map(\.kindStreaks)
        let kinds = VerbExercises.kindMastery(streaks)
        let due = scoped.filter { !$0.srs.isNew && $0.isDue }.count
        let new = scoped.filter { $0.srs.isNew }.count

        return List {
            if verbs.isEmpty {
                ContentUnavailableView(
                    "No verbs yet",
                    systemImage: "text.word.spacing",
                    description: Text("In the Add tab choose “Verbs” and take a photo of a page with verbs or conjugation tables.")
                )
            } else {
                Section {
                    groupChips
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group?.label ?? "All verbs")
                                .font(.title3.bold())
                            Text("\(scoped.count) verbs · \(due) to review · \(new) new")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressRing(value: VerbExercises.mastery(streaks), color: .verbs)
                            .frame(width: 54, height: 54)
                    }
                    .padding(.vertical, 4)

                    Button {
                        start(.adaptive, wantsSpeaking: speakingInMixed)
                    } label: {
                        Label("Train automatically", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.verbs)
                    .controlSize(.large)

                    ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .verbs) {
                        start(.mixed, wantsSpeaking: speakingInMixed)
                    }
                } footer: {
                    Text("Each exercise has its own percentage: one right answer is worth half a verb, two in a row the whole verb. “Automatic” starts from the meaning (choose the verb) and works up to the full table and speaking.")
                }

                tileSection("Translation", kinds: VerbExerciseKind.translationKinds, mastery: kinds, streaks: streaks)
                tileSection("Present tense conjugation", kinds: VerbExerciseKind.conjugationKinds, mastery: kinds, streaks: streaks)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Verbs")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeSession) { session in
            SessionView(session: session)
        }
        .alert("Heads up", isPresented: Binding(isPresent: $alertMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func tileSection(_ title: String, kinds: [VerbExerciseKind], mastery: [VerbExerciseKind: Double],
                             streaks: [[VerbExerciseKind: Int]]) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(kinds, id: \.self) { kind in
                    ExerciseTile(title: kind.title, systemImage: kind.systemImage,
                                 value: mastery[kind] ?? 0, color: .verbs) {
                        start(.fixed(kind), wantsSpeaking: kind.isSpeaking)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((VerbExercises.mastery(streaks, kinds: kinds) * 100).rounded()))%")
                    .monospacedDigit()
            }
        }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", value: VerbExercises.mastery(verbs.map(\.kindStreaks)), selected: group == nil) {
                    group = nil
                }
                ForEach(verbs.groups, id: \.self) { item in
                    let streaks = verbs.filter { $0.group == item }.map(\.kindStreaks)
                    chip(title: item.label, value: VerbExercises.mastery(streaks), selected: group == item) {
                        group = item
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
            .background(Capsule().fill(selected ? Color.verbs : Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    /// Due verbs first, then a few new ones, then the weakest in the chosen exercise, rotating.
    private func start(_ policy: VerbPolicy, wantsSpeaking: Bool) {
        let kind: VerbExerciseKind?
        if case .fixed(let chosen) = policy { kind = chosen } else { kind = nil }
        let candidates = scoped.map { $0.candidate(for: kind) }
        Task { @MainActor in
            let allowSpeaking = wantsSpeaking ? await SpeechRecognizer.requestPermissions() : false
            if case .fixed(let kind) = policy, kind.isSpeaking, !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: Self.sessionLength, includeNotDue: true,
                                             newLimit: Self.newPerSession)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(steps: ids.map { .verb($0) }, allWords: words, allVerbs: verbs,
                                         kindPolicy: .adaptive, verbPolicy: policy,
                                         allowSpeaking: allowSpeaking, context: context)
        }
    }
}
