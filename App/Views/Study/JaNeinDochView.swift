import LearnCore
import SwiftData
import SwiftUI

extension Color {
    static let jaNeinDoch = Color.mint
}

/// How the answer is given in the ja/nein/doch exercise.
enum YesNoMode: String, CaseIterable, Identifiable {
    /// Pick the right sentence among four.
    case choose
    /// Write the whole sentence, as on the worksheet.
    case write

    var id: String { rawValue }

    var title: String {
        switch self {
        case .choose: return "Choose the answer"
        case .write: return "Write the answer"
        }
    }

    var systemImage: String {
        switch self {
        case .choose: return "list.bullet.circle"
        case .write: return "keyboard"
        }
    }

    var caption: String {
        switch self {
        case .choose: return "pick one of four"
        case .write: return "the whole sentence"
        }
    }
}

/// Row of the ja/nein/doch section on the path.
struct JaNeinDochRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("🙋")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ja · Nein · Doch")
                    .font(.headline)
                Text("keinen Drucker? (+) → Doch, …")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Answering yes/no questions (positive and negated) built from the learner's own nouns and verbs.
struct JaNeinDochView: View {
    @Query private var words: [Word]
    @Query private var verbs: [Verb]
    @State private var round: YesNoRound?

    private static let sessionLength = 10

    private var nounCount: Int { words.filter { YesNoQuiz.canUse(noun: $0.entry) }.count }
    private var verbCount: Int { verbs.filter { YesNoQuiz.canUse(verb: $0.entry) }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    RuleLine(sign: "+", question: "Hast du einen Drucker?", answer: "Ja, ich habe einen Drucker.")
                    RuleLine(sign: "−", question: "Hast du einen Drucker?", answer: "Nein, ich habe keinen Drucker.")
                    RuleLine(sign: "+", question: "Hast du keinen Drucker?", answer: "Doch, ich habe einen Drucker.")
                    RuleLine(sign: "−", question: "Hast du keinen Drucker?", answer: "Nein, ich habe keinen Drucker.")
                }
                .padding(.vertical, 4)
            } header: {
                Text("The rule")
            } footer: {
                Text("(+) asks for a positive answer, (−) for a negative one. To say yes to a question with kein or nicht, answer doch, not ja.")
            }

            Section {
                if nounCount + verbCount == 0 {
                    Text("Add nouns with their article, or verbs with their present tense, to get questions here.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(YesNoMode.allCases) { mode in
                            ExerciseTile(title: mode.title, systemImage: mode.systemImage, value: nil,
                                         color: .jaNeinDoch, caption: mode.caption) {
                                start(mode)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Questions use your words: \(nounCount) nouns and \(verbCount) verbs.")
            }
        }
        .navigationTitle("Ja · Nein · Doch")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $round) { round in
            YesNoSessionView(round: round)
        }
    }

    private func start(_ mode: YesNoMode) {
        var rng = SystemRandomNumberGenerator()
        let questions = YesNoQuiz.make(count: Self.sessionLength, nouns: words.map(\.entry),
                                       verbs: verbs.map(\.entry), using: &rng)
        guard !questions.isEmpty else { return }
        round = YesNoRound(mode: mode, questions: questions)
    }
}

private struct RuleLine: View {
    let sign: String
    let question: String
    let answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(question) (\(sign))")
                .font(.subheadline)
            Text("→ \(answer)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.jaNeinDoch)
        }
    }
}

struct YesNoRound: Identifiable {
    let id = UUID()
    let mode: YesNoMode
    let questions: [YesNoQuestion]
}

/// One round of questions, one at a time, with the score at the end.
private struct YesNoSessionView: View {
    let round: YesNoRound
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var verdict: Verdict?
    @State private var given = ""
    @State private var correctCount = 0

    private var isFinished: Bool { index >= round.questions.count }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    finished
                } else {
                    ScrollView {
                        question(round.questions[index])
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !isFinished {
                        ProgressView(value: Double(index), total: Double(round.questions.count))
                            .tint(.jaNeinDoch)
                            .frame(width: 160)
                    }
                }
            }
        }
    }

    private func question(_ question: YesNoQuestion) -> some View {
        VStack(spacing: 24) {
            YesNoPromptCard(question: question)

            switch round.mode {
            case .choose:
                YesNoChoiceView(question: question, isAnswered: verdict != nil) { chosen in
                    grade(chosen == question.answer ? .correct : .wrong, given: chosen)
                }
            case .write:
                YesNoTypingView(isAnswered: verdict != nil) { text in
                    grade(question.check(text), given: text)
                }
            }

            if let verdict {
                YesNoFeedbackPanel(question: question, verdict: verdict, given: given,
                                   canOverride: round.mode == .write,
                                   onOverride: overrideAsCorrect, onContinue: advance)
            }
        }
        .id(index)
    }

    private var finished: some View {
        VStack(spacing: 16) {
            Text(correctCount == round.questions.count ? "🎉" : "💪")
                .font(.system(size: 64))
            Text("\(correctCount) / \(round.questions.count) right")
                .font(.title.bold())
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grade(_ verdict: Verdict, given: String) {
        self.given = given
        self.verdict = verdict
        if verdict == .correct { correctCount += 1 }
    }

    private func overrideAsCorrect() {
        guard verdict != .correct else { return }
        verdict = .correct
        correctCount += 1
    }

    private func advance() {
        verdict = nil
        given = ""
        index += 1
    }
}

private struct YesNoPromptCard: View {
    let question: YesNoQuestion

    var body: some View {
        VStack(spacing: 14) {
            Text(question.wantsYes ? "Answer positively (+)" : "Answer negatively (−)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(question.emoji)
                .font(.system(size: 44))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(question.question)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(question.wantsYes ? "+" : "−")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(question.wantsYes ? Color.green : Color.red))
                    .accessibilityLabel(question.wantsYes ? "positive" : "negative")
            }
            Button {
                Speaker.shared.speak(question.question)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Listen")
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct YesNoChoiceView: View {
    let question: YesNoQuestion
    let isAnswered: Bool
    let onSelect: (String) -> Void

    @State private var options: [String] = []
    @State private var selected: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options, id: \.self) { option in
                Button {
                    guard !isAnswered else { return }
                    selected = option
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(background(for: option), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
            }
        }
        .onAppear {
            var rng = SystemRandomNumberGenerator()
            options = question.options(using: &rng)
        }
    }

    private func background(for option: String) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if option == question.answer { return .green.opacity(0.3) }
        if option == selected { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

private struct YesNoTypingView: View {
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(AnswerWord.allCases, id: \.self) { word in
                    Button(word.title) { start(with: word) }
                        .buttonStyle(.bordered)
                }
            }
            TextField("Ja / Nein / Doch, ich …", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if !isAnswered {
                Button("Check", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmed.isEmpty)
            }
        }
        .disabled(isAnswered)
        .onAppear { isFocused = true }
    }

    /// Replaces the opening word, keeping whatever follows the comma.
    private func start(with word: AnswerWord) {
        let rest = text.split(separator: ",", maxSplits: 1).dropFirst().first.map(String.init) ?? " "
        text = word.title + "," + (rest.hasPrefix(" ") ? rest : " " + rest)
        isFocused = true
    }

    private func submit() {
        guard !isAnswered, !text.trimmed.isEmpty else { return }
        isFocused = false
        onSubmit(text.trimmed)
    }
}

private struct YesNoFeedbackPanel: View {
    let question: YesNoQuestion
    let verdict: Verdict
    let given: String
    let canOverride: Bool
    let onOverride: () -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

    private var color: Color {
        switch verdict {
        case .correct: return .green
        case .almost: return .orange
        case .wrong: return .red
        }
    }

    private var title: String {
        switch verdict {
        case .correct: return "Right!"
        case .almost: return "Almost: check the spelling"
        case .wrong: return "Wrong"
        }
    }

    /// Why this opening word, in one line.
    private var reason: String {
        switch question.answerWord {
        case .ja: return "Positive question, positive answer: ja."
        case .doch: return "The question has \(question.question.contains(" nicht ") ? "nicht" : "kein"): to say yes, answer doch."
        case .nein: return question.isNegated
            ? "Negative question, negative answer: nein, and keep the negation."
            : "Negative answer: nein, with kein or nicht."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: verdict == .correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(color)

            if verdict != .correct {
                Text("You answered: \(given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Text(question.answer)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                Button {
                    Speaker.shared.speak(question.answer)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }

            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack {
                if verdict != .correct && canOverride {
                    Button("I was right", action: onOverride)
                        .buttonStyle(.bordered)
                }
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if autoSpeak { Speaker.shared.speak(question.answer) }
        }
    }
}
