import LearnCore
import SwiftData
import SwiftUI

/// Builds number questions for sessions.
enum NumberSteps {
    /// `kind` nil mixes the kinds; speaking only when allowed.
    @MainActor
    static func make(count: Int, level: NumberLevel, kind: NumberExerciseKind?, allowSpeaking: Bool) -> [SessionStep] {
        var rng = SystemRandomNumberGenerator()
        let kinds = NumberExerciseKind.allCases.filter { allowSpeaking || $0 != .speak }
        let stats = NumberStatsStore.shared.stats
        return (0..<count).map { _ in
            let chosen = kind ?? kinds.randomElement(using: &rng) ?? .listenChoice
            return .number(NumberQuiz.make(kind: chosen, level: level, stats: stats, using: &rng))
        }
    }
}

extension NumberExerciseKind {
    var systemImage: String {
        switch self {
        case .listenChoice: return "ear"
        case .listenDigits: return "number"
        case .writeWords: return "character.cursor.ibeam"
        case .speak: return "mic"
        }
    }

    var color: Color { .teal }
}

/// Row of the number section on the path.
struct NumbersRow: View {
    @ObservedObject private var store = NumberStatsStore.shared
    @AppStorage(SettingsKey.numbersLevel) private var levelRaw = NumberLevel.upTo20.rawValue

    private var level: NumberLevel { NumberLevel(rawValue: levelRaw) ?? .upTo20 }

    var body: some View {
        HStack(spacing: 12) {
            Text("🔢")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Numbers")
                    .font(.headline)
                Text("Level \(level.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProgressRing(value: store.stats.progress(level), color: .teal)
                .frame(width: 38, height: 38)
        }
    }
}

/// Number practice: pick a level, then a kind of exercise.
struct NumbersView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @ObservedObject private var store = NumberStatsStore.shared
    @AppStorage(SettingsKey.numbersLevel) private var levelRaw = NumberLevel.upTo20.rawValue
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?

    private static let sessionLength = 10

    private var level: NumberLevel { NumberLevel(rawValue: levelRaw) ?? .upTo20 }

    var body: some View {
        List {
            Section {
                Picker("Level", selection: $levelRaw) {
                    ForEach(NumberLevel.allCases, id: \.self) { level in
                        Text(level.shortTitle).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.title)
                            .font(.title2.bold().monospacedDigit())
                        Text(store.stats.mistakes(in: level).isEmpty
                             ? "No numbers to go over"
                             : "\(store.stats.mistakes(in: level).count) missed numbers to go over")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(value: store.stats.progress(level), color: .teal)
                        .frame(width: 54, height: 54)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Each exercise's percentage counts the right answers among the last 20; the level's is their average. Numbers you miss come back more often.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(NumberExerciseKind.allCases, id: \.self) { kind in
                        ExerciseTile(title: kind.title, systemImage: kind.systemImage,
                                     value: store.stats.progress(level, kind), color: kind.color) {
                            start(kind)
                        }
                    }
                    ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .teal) {
                        start(nil)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Numbers")
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

    private func start(_ kind: NumberExerciseKind?) {
        let level = self.level
        Task { @MainActor in
            let wantsSpeaking = kind == nil || kind == .speak
            let allowSpeaking = wantsSpeaking ? await SpeechRecognizer.requestPermissions() : false
            if kind == .speak && !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let steps = NumberSteps.make(count: Self.sessionLength, level: level, kind: kind, allowSpeaking: allowSpeaking)
            activeSession = StudySession(steps: steps, allWords: words, kindPolicy: .adaptive,
                                         allowSpeaking: allowSpeaking, context: context)
        }
    }
}

extension NumberLevel {
    /// For the segmented picker.
    var shortTitle: String {
        switch self {
        case .upTo20: return "0–20"
        case .upTo100: return "–100"
        case .upTo1000: return "–1.000"
        case .upToMillion: return "–1M"
        }
    }
}
