import LearnCore
import SwiftData
import SwiftUI

extension VerbExerciseKind {
    var systemImage: String {
        switch base {
        case .chooseForm: return "square.grid.2x2"
        case .typeForm: return "keyboard"
        case .fullTable: return "tablecells"
        case .whichPerson: return "person.2"
        case .speak: return "mic"
        case .translateChoice: return "square.grid.2x2.fill"
        case .translateGerman: return "character.bubble"
        case .translateEnglish: return "character.cursor.ibeam"
        default: return "waveform"
        }
    }
}

extension Color {
    static let verbs = Color.mint
    /// Marks preterite games and tables.
    static let preterite = Color.indigo
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
                Text(verbs.isEmpty ? "Add verbs from the Add tab" : "\(verbs.count) verbs · present & preterite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !verbs.isEmpty {
                ProgressRing(value: VerbExercises.mastery(verbs.map(\.progress)), color: .verbs)
                    .frame(width: 38, height: 38)
            }
        }
    }
}

/// Present-tense practice: pick a group (or all), then a kind of exercise.
/// With a verb set, only the verbs of that set.
struct VerbsView: View {
    /// The verb set trained; nil for every verb.
    private let setID: UUID?

    @Environment(\.modelContext) private var context
    @Query private var allVerbs: [Verb]
    @ObservedObject private var setStore = VerbSetStore.shared
    @State private var isEditingSet = false
    @State private var isRenaming = false
    @State private var newName = ""
    @Query private var words: [Word]
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var group: VerbGroup?
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?
    @State private var preteriteProgress: Int?

    private static let sessionLength = 10
    /// New verbs per session when there are reviews too: a few at a time stick better.
    private static let newPerSession = 4

    init(setID: UUID? = nil) {
        self.setID = setID
    }

    private var verbSet: VerbSet? { setID.flatMap { setStore.set($0) } }

    /// The verbs trained here: the set's, or all of them.
    private var verbs: [Verb] {
        guard let setID else { return allVerbs }
        let ids = Set(setStore.set(setID)?.verbIDs ?? [])
        return allVerbs.filter { ids.contains($0.id) }
    }

    private var scoped: [Verb] {
        group.map { selected in verbs.filter { $0.section == selected } } ?? verbs
    }

    var body: some View {
        let scoped = self.scoped
        let streaks = scoped.map(\.progress)
        let kinds = VerbExercises.kindMastery(streaks)
        let withoutPreterite = scoped.filter { !$0.hasPreterite }
        let due = scoped.filter { !$0.srs.isNew && $0.isDue }.count
        let new = scoped.filter { $0.srs.isNew }.count

        return List {
            if verbs.isEmpty, setID != nil {
                ContentUnavailableView(
                    "No verbs in this set",
                    systemImage: "square.stack",
                    description: Text("Tap ✏️ to choose the verbs of this set.")
                )
            } else if verbs.isEmpty {
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
                    Text("Each exercise has its own percentage: one right answer is worth half a verb, two in a row the whole verb. “Automatic” starts from the meaning (choose the verb) and works up to the full table and speaking, in the present first and then in the preterite.")
                }

                tileSection("Translation", kinds: VerbExerciseKind.translationKinds, mastery: kinds, streaks: streaks)
                tileSection("Present · Präsens", kinds: VerbExerciseKind.conjugationKinds(.present),
                            mastery: kinds, streaks: streaks)
                tileSection("Preterite · Präteritum", kinds: VerbExerciseKind.conjugationKinds(.preterite),
                            mastery: kinds, streaks: streaks, color: .preterite,
                            footer: withoutPreterite.isEmpty ? nil : preteriteFooter(missing: withoutPreterite))

                if let verbSet {
                    setVerbsSection(verbSet, verbs: scoped)
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(verbSet?.name ?? "Verbs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let verbSet {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isEditingSet = true
                        } label: {
                            Label("Choose verbs", systemImage: "checklist")
                        }
                        Button {
                            newName = verbSet.name
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                    } label: {
                        Label("Edit set", systemImage: "pencil")
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingSet) {
            if let verbSet {
                VerbSetEditorView(title: verbSet.name, name: nil, selected: Set(verbSet.verbIDs)) { _, ids in
                    setStore.setVerbs(verbSet.id, to: ids)
                }
            }
        }
        .alert("Rename set", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let setID { setStore.rename(setID, to: newName.trimmed) }
            }
        }
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
                             streaks: [VerbProgress], color: Color = .verbs,
                             footer: AnyView? = nil) -> some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(kinds, id: \.self) { kind in
                    ExerciseTile(title: kind.title, systemImage: kind.systemImage,
                                 value: mastery[kind] ?? 0, color: color) {
                        start(.fixed(kind), wantsSpeaking: kind.isSpeaking)
                    }
                    // A preterite game with no verb to ask yet.
                    .disabled(mastery[kind] == nil)
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
        } footer: {
            if let footer { footer }
        }
    }

    /// Verbs saved before the preterite was asked for: one tap asks the model for it.
    private func preteriteFooter(missing: [Verb]) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 8) {
            Text(missing.count == 1
                 ? "1 verb has no preterite yet and skips these games."
                 : "\(missing.count) verbs have no preterite yet and skip these games.")
            if let done = preteriteProgress {
                ProgressView(value: Double(done), total: Double(max(missing.count, 1))) {
                    Text("Adding the preterite…")
                }
            } else {
                Button {
                    fillPreterite(missing)
                } label: {
                    Label("Add the preterite with AI", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.preterite)
                .textCase(nil)
            }
        })
    }

    private func fillPreterite(_ missing: [Verb]) {
        preteriteProgress = 0
        Task { @MainActor in
            defer { preteriteProgress = nil }
            do {
                let filled = try await VerbMaintenance.fillPreterite(missing, context: context) { done in
                    preteriteProgress = done
                }
                if filled < missing.count {
                    alertMessage = "Added the preterite to \(filled) of \(missing.count) verbs. Try again for the rest, or add it by hand from Vocabulary → Verbs."
                }
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    /// The verbs of the set, with their progress; swipe to take one out of the set.
    private func setVerbsSection(_ set: VerbSet, verbs: [Verb]) -> some View {
        Section {
            ForEach(verbs.sorted { $0.infinitive.localizedCompare($1.infinitive) == .orderedAscending }) { verb in
                HStack(spacing: 12) {
                    Text(verb.emoji)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verb.infinitive)
                            .font(.headline)
                        Text(verb.english)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int((VerbExercises.mastery([verb.progress]) * 100).rounded()))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        setStore.setVerbs(set.id, to: set.verbIDs.filter { $0 != verb.id })
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }
        } header: {
            HStack {
                Text("Verbs in this set")
                Spacer()
                Button("Choose") { isEditingSet = true }
                    .font(.caption)
                    .textCase(nil)
            }
        } footer: {
            Text("Swipe a verb left to take it out of the set; it stays in your vocabulary.")
        }
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", value: VerbExercises.mastery(verbs.map(\.progress)), selected: group == nil) {
                    group = nil
                }
                ForEach(verbs.groups, id: \.self) { item in
                    let streaks = verbs.filter { $0.section == item }.map(\.progress)
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
        // A preterite game only asks the verbs whose preterite is known.
        let candidates = scoped.filter { kind.map($0.entry.supports) ?? true }.map { $0.candidate(for: kind) }
        Task { @MainActor in
            let allowSpeaking = wantsSpeaking ? await SpeechRecognizer.requestPermissions() : false
            if case .fixed(let kind) = policy, kind.isSpeaking, !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: Self.sessionLength, includeNotDue: true,
                                             newLimit: Self.newPerSession)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(steps: ids.map { .verb($0) }, allWords: words, allVerbs: allVerbs,
                                         kindPolicy: .adaptive, verbPolicy: policy,
                                         allowSpeaking: allowSpeaking, context: context)
        }
    }
}
