import LearnCore
import SwiftData
import SwiftUI

extension CompoundExerciseKind {
    var systemImage: String {
        switch self {
        case .matchPairs: return "link"
        case .completeWord: return "puzzlepiece"
        case .buildFromMeaning: return "square.stack.3d.up"
        case .typeCompound: return "keyboard"
        }
    }
}

extension Color {
    static let compounds = Color.indigo
}

/// Row of the compound words section on the path.
struct CompoundsRow: View {
    @Query private var words: [Word]

    var body: some View {
        let compounds = words.filter(\.isCompound)
        return HStack(spacing: 12) {
            Text("🧩")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Compound words")
                    .font(.headline)
                Text(compounds.isEmpty ? "Küche + Tür → die Küchentür"
                     : compounds.count == 1 ? "1 compound" : "\(compounds.count) compounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !compounds.isEmpty {
                ProgressRing(value: CompoundGame.mastery(compounds.map(\.compoundStreaks)), color: .compounds)
                    .frame(width: 38, height: 38)
            }
        }
    }
}

/// Games to join words into compounds, each with its percentage.
struct CompoundsView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @State private var activeSession: CompoundSession?

    private static let sessionLength = 8
    /// Match rounds use up to five compounds each: three rounds per session.
    private static let matchSessionLength = 15

    private var compounds: [Word] {
        words.filter(\.isCompound).sorted { $0.german.localizedCaseInsensitiveCompare($1.german) == .orderedAscending }
    }

    var body: some View {
        let compounds = self.compounds
        let streaks = compounds.map(\.compoundStreaks)
        let mastery = CompoundGame.kindMastery(streaks)
        let vocabularyKeys = Set(words.map { PhraseChecker.key($0.german) })

        return List {
            if compounds.isEmpty {
                ContentUnavailableView(
                    "No compound words yet",
                    systemImage: "puzzlepiece",
                    description: Text("Take a photo of an exercise that joins words (Küche + Tür…) from the Add tab, or give a noun its parts in Vocabulary.")
                )
            } else {
                Section {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Compound words")
                                .font(.title3.bold())
                            Text(compounds.count == 1 ? "1 compound" : "\(compounds.count) compounds")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ProgressRing(value: CompoundGame.mastery(streaks), color: .compounds)
                            .frame(width: 54, height: 54)
                    }
                    .padding(.vertical, 4)

                    Button {
                        start(.adaptive)
                    } label: {
                        Label("Train automatically", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.compounds)
                    .controlSize(.large)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(CompoundExerciseKind.allCases, id: \.self) { kind in
                            ExerciseTile(title: kind.title, systemImage: kind.systemImage,
                                         value: mastery[kind] ?? 0, color: .compounds) {
                                start(.fixed(kind))
                            }
                            .disabled(kind == .matchPairs && compounds.count < CompoundGame.minimumPairs)
                        }
                        ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .compounds) {
                            start(.mixed)
                        }
                    }
                    .padding(.vertical, 6)
                } footer: {
                    Text(compounds.count < CompoundGame.minimumPairs
                         ? "Matching pairs needs at least \(CompoundGame.minimumPairs) compounds with different parts."
                         : "Each game has its own percentage: one right answer is worth half a compound, two in a row the whole one. “Automatic” goes from matching and completing to building and typing.")
                }

                Section("Compounds") {
                    ForEach(compounds) { word in
                        HStack(spacing: 12) {
                            Text(word.emoji)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.entry.withArticle)
                                    .font(.headline)
                                HStack(spacing: 4) {
                                    ForEach(Array(word.compoundParts.enumerated()), id: \.offset) { index, part in
                                        if index > 0 { Text("+").foregroundStyle(.secondary) }
                                        Text(part)
                                        if vocabularyKeys.contains(PhraseChecker.key(part)) {
                                            Image(systemName: "link")
                                                .font(.caption2)
                                                .foregroundStyle(Color.compounds)
                                                .accessibilityLabel("in your vocabulary")
                                        }
                                    }
                                }
                                .font(.subheadline)
                                Text(word.english.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Compound words")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeSession) { session in
            CompoundSessionView(session: session)
        }
    }

    /// The weakest compounds in the chosen game first, rotating among equals.
    private func start(_ policy: CompoundPolicy) {
        let kind: CompoundExerciseKind?
        if case .fixed(let chosen) = policy { kind = chosen } else { kind = nil }
        let candidates = compounds.map { word in
            StudyCandidate(id: word.id, srs: word.srs(for: .translation), createdAt: word.createdAt,
                           level: kind.map { word.compoundStreaks[$0] ?? 0 } ?? CompoundSession.adaptiveLevel(of: word))
        }
        let limit = kind == .matchPairs ? Self.matchSessionLength : Self.sessionLength
        let ids = SessionPlanner.select(candidates, now: .now, limit: limit, includeNotDue: true)
        let byID = Dictionary(compounds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let steps = CompoundSession.steps(for: ids.compactMap { byID[$0] }, policy: policy)
        guard !steps.isEmpty else { return }
        activeSession = CompoundSession(steps: steps, allWords: words, context: context)
    }
}
