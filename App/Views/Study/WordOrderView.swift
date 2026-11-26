import LearnCore
import SwiftData
import SwiftUI

extension Color {
    static let wordOrder = Color.cyan
}

extension WordOrderPattern {
    var systemImage: String {
        switch self {
        case .statement: return "text.alignleft"
        case .wQuestion: return "questionmark.bubble"
        case .yesNoQuestion: return "questionmark.circle"
        }
    }

    var example: String {
        switch self {
        case .statement: return "Ich stehe um 8 Uhr auf."
        case .wQuestion: return "Wann stehst du auf?"
        case .yesNoQuestion: return "Stehst du morgen auf?"
        }
    }
}

/// Row of the sentence-building section on the path.
struct WordOrderRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("🧱")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Build sentences")
                    .font(.headline)
                Text("steht · auf · Pedro · um 8 Uhr → Pedro steht um 8 Uhr auf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// "Sätze bilden": put the pieces in order, with sentences built from the learner's verbs and nouns.
struct WordOrderView: View {
    @Query private var words: [Word]
    @Query private var verbs: [Verb]
    @State private var round: WordOrderRound?

    private static let sessionLength = 10

    private var nounCount: Int { words.filter { YesNoQuiz.canUse(noun: $0.entry) }.count }
    private var verbCount: Int { verbs.filter { WordOrderQuiz.canUse(verb: $0.entry) }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    ExampleLine(text: "Pedro **steht** um 8 Uhr **auf**.")
                    ExampleLine(text: "Am Wochenende **frühstücke** ich um 9 Uhr.")
                    ExampleLine(text: "Wann **gehen** Tom und Anna heute **aus**?")
                    ExampleLine(text: "**Rufst** du Roman morgen **an**?")
                }
                .padding(.vertical, 4)
            } header: {
                Text("The rule")
            } footer: {
                Text("In a statement the verb is always second; in a W-question it follows the question word; in a yes/no question it comes first. A separable prefix goes to the end.")
            }

            Section {
                if nounCount + verbCount == 0 {
                    Text("Add verbs with their present tense, or nouns with their article, to get sentences here.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(WordOrderPattern.allCases, id: \.self) { pattern in
                            ExerciseTile(title: pattern.title, systemImage: pattern.systemImage, value: nil,
                                         color: .wordOrder, caption: pattern.example) {
                                start(pattern)
                            }
                        }
                        ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .wordOrder,
                                     caption: "all three") {
                            start(nil)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Sentences use your words: \(verbCount) verbs and \(nounCount) nouns.")
            }
        }
        .navigationTitle("Build sentences")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $round) { round in
            WordOrderSessionView(round: round)
        }
    }

    private func start(_ pattern: WordOrderPattern?) {
        var rng = SystemRandomNumberGenerator()
        let exercises = WordOrderQuiz.make(count: Self.sessionLength, pattern: pattern, nouns: words.map(\.entry),
                                           verbs: verbs.map(\.entry), using: &rng)
        guard !exercises.isEmpty else { return }
        round = WordOrderRound(exercises: exercises)
    }
}

private struct ExampleLine: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.subheadline)
    }
}

struct WordOrderRound: Identifiable {
    let id = UUID()
    let exercises: [WordOrderExercise]
}

/// One round of sentences, one at a time, with the score at the end.
private struct WordOrderSessionView: View {
    let round: WordOrderRound
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var verdict: Verdict?
    @State private var given = ""
    @State private var correctCount = 0
    /// One tutor conversation per exercise, kept for the session only.
    @State private var chats: [Int: [GrammarChatMessage]] = [:]
    @State private var showsChat = false

    private var isFinished: Bool { index >= round.exercises.count }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    finished
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            exercise(round.exercises[index])
                                .padding()
                        }
                        .scrollToFeedback(when: verdict != nil, proxy: proxy)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !isFinished {
                        ProgressView(value: Double(index), total: Double(round.exercises.count))
                            .tint(.wordOrder)
                            .frame(width: 160)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !isFinished {
                        Button {
                            showsChat = true
                        } label: {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                        }
                        .accessibilityLabel("Ask the tutor")
                    }
                }
            }
            .sheet(isPresented: $showsChat) {
                if !isFinished {
                    NavigationStack {
                        TutorChatView(chat: tutorChat(for: index), isSheet: true)
                    }
                }
            }
        }
    }

    /// The tutor for the exercise on screen: it knows the pieces and, once checked, the attempt.
    private func tutorChat(for index: Int) -> TutorChat {
        let exercise = round.exercises[index]
        let attempt = verdict.map { WordOrderChatPrompt.Attempt(sentence: given, isRight: $0 == .correct) }
        return TutorChat(
            intro: "Ask anything about this sentence, in Italian or English. Before you check, the tutor gives hints, not the solution.",
            suggestions: WordOrderChatPrompt.suggestions(for: exercise, attempt: attempt),
            messages: chats[index] ?? [],
            allowsPhotos: false,
            clearMessage: "The questions and answers about this sentence are removed.",
            append: { message in chats[index, default: []].append(message) },
            clear: { chats[index] = nil },
            answer: { key, history in
                try await OpenRouterClient(apiKey: key, model: OpenRouterModels.grammarModel())
                    .tutorChat(system: WordOrderChatPrompt.system(for: exercise, attempt: attempt), history: history)
            }
        )
    }

    private func exercise(_ exercise: WordOrderExercise) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text("Put the pieces in order")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(exercise.emoji)
                    .font(.system(size: 44))
                Label(exercise.pattern.title, systemImage: exercise.pattern.systemImage)
                    .font(.headline)
                    .foregroundStyle(Color.wordOrder)
                EnglishLine(text: exercise.english)
                Text(exercise.punctuation == "?" ? "Ends with a question mark" : "Ends with a full stop")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))

            ReorderView(tiles: exercise.tiles, isAnswered: verdict != nil) { chosen in
                given = exercise.sentence(from: chosen)
                let result = exercise.check(chosen)
                verdict = result
                if result == .correct { correctCount += 1 }
            }

            if let verdict {
                WordOrderFeedbackPanel(exercise: exercise, verdict: verdict, given: given) {
                    self.verdict = nil
                    given = ""
                    index += 1
                }
                .id(FeedbackAnchor.id)
            }
        }
        .id(index)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Text(correctCount == round.exercises.count ? "🎉" : "💪")
                .font(.system(size: 64))
            Text("\(correctCount) / \(round.exercises.count) right")
                .font(.title.bold())
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WordOrderFeedbackPanel: View {
    let exercise: WordOrderExercise
    let verdict: Verdict
    let given: String
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

    private var isRight: Bool { verdict == .correct }
    private var color: Color { isRight ? .green : .red }
    /// When right, the learner's own order; otherwise the solution and its alternatives.
    private var solutions: [String] {
        isRight ? [given] : [exercise.answer] + exercise.accepted.filter { $0 != exercise.answer }
    }

    var body: some View {
        VStack(spacing: 12) {
            Label(isRight ? "Right!" : "Wrong", systemImage: isRight ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(color)

            if !isRight {
                Text("You built: \(given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ForEach(Array(solutions.enumerated()), id: \.offset) { offset, sentence in
                HStack {
                    if offset > 0 {
                        Text("also:")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(sentence)
                        .font(offset == 0 ? .title3.weight(.semibold) : .body)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                    Button {
                        Speaker.shared.speak(sentence)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            // Every accepted order means the same, so one translation covers them all.
            EnglishLine(text: exercise.english)

            Text(exercise.rule)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if autoSpeak { Speaker.shared.speak(solutions[0]) }
        }
    }
}
