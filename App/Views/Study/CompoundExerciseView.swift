import LearnCore
import SwiftUI

/// Full-screen session of compound games.
struct CompoundSessionView: View {
    @ObservedObject var session: CompoundSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.isFinished {
                    CompoundSummaryView(session: session) { dismiss() }
                } else if let runner = session.runner {
                    ScrollView {
                        CompoundQuestionView(runner: runner, onContinue: session.advance)
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // A fresh view per question resets selections and typed text.
                    .id(ObjectIdentifier(runner))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if !session.isFinished {
                        ProgressView(value: Double(session.completed), total: Double(max(session.total, 1)))
                            .frame(width: 160)
                    }
                }
            }
        }
    }
}

/// One compound question with its feedback; used by the compound section, the bonus and lessons.
struct CompoundQuestionView: View {
    @ObservedObject var runner: CompoundRunner
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            switch runner.question {
            case .match(let round):
                MatchPairsView(round: round, runner: runner)
            case .complete(let complete):
                CompleteWordView(question: complete, isAnswered: runner.feedback != nil, onChoose: runner.choose)
            case .build(let build):
                BuildCompoundView(question: build, isAnswered: runner.feedback != nil, onSubmit: runner.build)
            case .type(let entry):
                TypeCompoundView(entry: entry, isAnswered: runner.feedback != nil, onSubmit: runner.type)
            }

            if let feedback = runner.feedback {
                CompoundFeedbackPanel(feedback: feedback, canOverride: runner.canOverride,
                                      onOverride: runner.overrideAsCorrect, onContinue: onContinue)
            }
        }
    }
}

/// The instruction and what is shown, on the usual card.
private struct CompoundCard<Content: View>: View {
    let instruction: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Match the pairs

private struct MatchPairsView: View {
    let round: CompoundMatchRound
    @ObservedObject var runner: CompoundRunner

    @State private var selectedLeft: String?
    @State private var wrongRight: String?

    var body: some View {
        VStack(spacing: 16) {
            CompoundCard(instruction: "Connect the words that make a compound") {
                Text("Tap a word on the left, then its partner on the right.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 10) {
                    ForEach(round.left, id: \.self) { word in
                        tile(word, state: leftState(word)) {
                            selectedLeft = selectedLeft == word ? nil : word
                        }
                        .disabled(runner.matched.contains(word) || runner.feedback != nil)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(round.right, id: \.self) { word in
                        tile(word, state: rightState(word)) {
                            pick(right: word)
                        }
                        .disabled(isRightMatched(word) || runner.feedback != nil)
                    }
                }
            }
        }
    }

    private enum TileState { case idle, selected, matched, wrong }

    private func tile(_ word: String, state: TileState, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(background(state), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if state == .selected {
                        RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func background(_ state: TileState) -> Color {
        switch state {
        case .idle: return Color(uiColor: .secondarySystemBackground)
        case .selected: return Color.accentColor.opacity(0.15)
        case .matched: return Color.green.opacity(0.3)
        case .wrong: return Color.red.opacity(0.3)
        }
    }

    private func leftState(_ word: String) -> TileState {
        if runner.matched.contains(word) { return .matched }
        return selectedLeft == word ? .selected : .idle
    }

    private func rightState(_ word: String) -> TileState {
        if isRightMatched(word) { return .matched }
        return wrongRight == word ? .wrong : .idle
    }

    private func isRightMatched(_ word: String) -> Bool {
        runner.matched.contains { left in round.compound(left: left, right: word) != nil }
    }

    private func pick(right word: String) {
        guard let left = selectedLeft else { return }
        if runner.matchPair(left: left, right: word) {
            selectedLeft = nil
        } else {
            wrongRight = word
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                if wrongRight == word { wrongRight = nil }
            }
        }
    }
}

// MARK: - Complete the word

private struct CompleteWordView: View {
    let question: CompoundCompleteQuestion
    let isAnswered: Bool
    let onChoose: (String) -> Void

    @State private var chosen: String?

    private var shownParts: String {
        question.entry.parts.enumerated()
            .map { $0.offset == question.missingIndex ? "___" : $0.element }
            .joined(separator: " + ")
    }

    var body: some View {
        VStack(spacing: 16) {
            CompoundCard(instruction: "Complete the compound") {
                Text(shownParts)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(question.entry.englishDisplay)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        guard !isAnswered else { return }
                        chosen = option
                        onChoose(option)
                    } label: {
                        Text(option)
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(background(for: option), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnswered)
                }
            }
        }
    }

    private func background(for option: String) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if option == question.answer { return .green.opacity(0.3) }
        if option == chosen { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

// MARK: - Build from meaning

private struct BuildCompoundView: View {
    let question: CompoundBuildQuestion
    let isAnswered: Bool
    let onSubmit: ([String]) -> Void

    /// Indices of the tapped tiles, in order.
    @State private var chosen: [Int] = []
    @AppStorage(SettingsKey.showEmoji) private var showEmoji = true

    var body: some View {
        VStack(spacing: 16) {
            CompoundCard(instruction: "Build the German compound") {
                if showEmoji {
                    Text(question.entry.emoji)
                        .font(.system(size: 52))
                }
                Text(question.entry.englishDisplay)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(chosen.isEmpty ? " " : chosen.map { question.tiles[$0] }.joined(separator: " + "))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .emojiToggle()

            FlowLayout(spacing: 10) {
                ForEach(Array(question.tiles.enumerated()), id: \.offset) { index, tile in
                    Button {
                        tap(index)
                    } label: {
                        Text(tile)
                            .font(.headline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(chosen.contains(index) ? Color.accentColor.opacity(0.25)
                                        : Color(uiColor: .secondarySystemBackground),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnswered)
                }
            }

            if !isAnswered {
                HStack {
                    Button("Clear") { chosen = [] }
                        .disabled(chosen.isEmpty)
                    Spacer()
                    Button("Check") { onSubmit(chosen.map { question.tiles[$0] }) }
                        .buttonStyle(.borderedProminent)
                        .disabled(chosen.count < 2)
                }
            }
        }
    }

    /// Tapping a chosen tile takes it back.
    private func tap(_ index: Int) {
        if let position = chosen.firstIndex(of: index) {
            chosen.remove(at: position)
        } else {
            chosen.append(index)
        }
    }
}

// MARK: - Type the compound

private struct TypeCompoundView: View {
    let entry: VocabEntry
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            CompoundCard(instruction: "Type the compound with its article") {
                Text(entry.partsDisplay)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(entry.englishDisplay)
                    .foregroundStyle(.secondary)
            }
            TextField("e.g. die Küchentür", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
                .disabled(isAnswered)
            if !isAnswered {
                Button("Check", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmed.isEmpty)
                Text("The article comes from the last part: die Tür → die Küchentür.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !text.trimmed.isEmpty, !isAnswered else { return }
        onSubmit(text)
    }
}

// MARK: - Feedback and summary

private struct CompoundFeedbackPanel: View {
    let feedback: CompoundFeedback
    let canOverride: Bool
    let onOverride: () -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

    private var title: String {
        switch feedback.verdict {
        case .correct: return "Right!"
        case .almost: return "Almost: check the spelling and the article"
        case .wrong: return "Wrong"
        }
    }

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .green
        case .almost: return .orange
        case .wrong: return .red
        }
    }

    /// The compounds themselves, to read aloud.
    private var spoken: String {
        feedback.solution.compactMap { $0.components(separatedBy: " → ").last }.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(color)
            if feedback.verdict != .correct, !feedback.given.isEmpty {
                Text("You answered: \(feedback.given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(feedback.solution, id: \.self) { line in
                Text(line)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
            }
            Button {
                Speaker.shared.speak(spoken)
            } label: {
                Label("Listen", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            HStack {
                if canOverride {
                    Button("I was right", action: onOverride)
                }
                Spacer()
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if autoSpeak { Speaker.shared.speak(spoken) }
        }
    }
}

private struct CompoundSummaryView: View {
    @ObservedObject var session: CompoundSession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("🧩")
                .font(.system(size: 80))
            Text("Session complete")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 12) {
                row("Right", count: session.results[.correct, default: 0], color: .green)
                row("Almost", count: session.results[.almost, default: 0], color: .orange)
                row("Wrong", count: session.results[.wrong, default: 0], color: .red)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private func row(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label)
            Spacer(minLength: 40)
            Text("\(count)").bold()
        }
    }
}
