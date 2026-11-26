import LearnCore
import SwiftData
import SwiftUI

extension Color {
    static let separable = Color.orange
}

extension SeparableExerciseKind {
    var systemImage: String {
        switch self {
        case .separableOrNot: return "scissors"
        case .findVerb: return "magnifyingglass"
        case .chooseSentence: return "list.bullet.circle"
        case .writeSentence: return "keyboard"
        }
    }

    var instruction: String {
        switch self {
        case .separableOrNot: return "Is this verb separable?"
        case .findVerb: return "Which verb is in this sentence?"
        case .chooseSentence: return "Choose the right sentence"
        case .writeSentence: return "Write the sentence in German"
        }
    }
}

/// Row of the separable-verbs section on the path.
struct SeparableVerbsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("✂️")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Separable verbs")
                    .font(.headline)
                Text("ich stehe um 8 Uhr auf · ich verstehe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Separable and non-separable verbs: recognising them, finding them in a sentence and using them.
struct SeparableVerbsView: View {
    @Query private var verbs: [Verb]
    @State private var round: SeparableRound?

    private static let sessionLength = 10

    private var usable: [VerbEntry] { verbs.map(\.entry).filter(SeparablePractice.canUse(verb:)) }
    private var separableCount: Int { usable.filter { SeparablePractice.prefix(of: $0) != nil }.count }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("**auf**stehen → Ich **stehe** um 8 Uhr **auf**.")
                    Text("**an**rufen → **Rufst** du Anna morgen **an**?")
                    Text("**ver**stehen → Ich **verstehe** das. (never splits)")
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            } header: {
                Text("The rule")
            } footer: {
                Text("A separable prefix (an, auf, aus, ein, mit, zu, fern…) leaves the verb and goes to the end of the sentence. Be-, ver-, er-, ent-, ge-, zer-, emp- and miss- always stay on the verb.")
            }

            Section {
                if separableCount == 0 {
                    Text("Add some separable verbs (e.g. aufstehen, anrufen, einkaufen) in Vocabulary → Verbs to practise here.")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(SeparableExerciseKind.allCases, id: \.self) { kind in
                            ExerciseTile(title: kind.title, systemImage: kind.systemImage, value: nil,
                                         color: .separable, caption: kind.caption) {
                                start(kind)
                            }
                        }
                        ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .separable,
                                     caption: "all four") {
                            start(nil)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text("Uses your verbs: \(separableCount) separable and \(usable.count - separableCount) not separable. Modal and reflexive verbs are left out.")
            }
        }
        .navigationTitle("Separable verbs")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $round) { round in
            SeparableSessionView(round: round)
        }
    }

    private func start(_ kind: SeparableExerciseKind?) {
        var rng = SystemRandomNumberGenerator()
        let exercises = SeparablePractice.make(count: Self.sessionLength, kind: kind, verbs: usable, using: &rng)
        guard !exercises.isEmpty else { return }
        round = SeparableRound(exercises: exercises)
    }
}

struct SeparableRound: Identifiable {
    let id = UUID()
    let exercises: [SeparableExercise]
}

/// One round, one exercise at a time, with the score at the end.
private struct SeparableSessionView: View {
    let round: SeparableRound
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var verdict: Verdict?
    @State private var given = ""
    @State private var correctCount = 0

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
                            .tint(.separable)
                            .frame(width: 160)
                    }
                }
            }
        }
    }

    private func exercise(_ exercise: SeparableExercise) -> some View {
        VStack(spacing: 24) {
            SeparablePromptCard(exercise: exercise)

            if exercise.kind == .writeSentence {
                SeparableTypingView(isAnswered: verdict != nil) { text in
                    grade(exercise.check(text), given: text)
                }
            } else {
                SeparableChoiceView(exercise: exercise, isAnswered: verdict != nil) { chosen in
                    grade(exercise.check(chosen), given: chosen)
                }
            }

            if let verdict {
                SeparableFeedbackPanel(exercise: exercise, verdict: verdict, given: given,
                                       canOverride: exercise.kind == .writeSentence,
                                       onOverride: overrideAsCorrect, onContinue: advance)
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

private struct SeparablePromptCard: View {
    let exercise: SeparableExercise

    var body: some View {
        VStack(spacing: 12) {
            Text(exercise.kind.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(exercise.emoji)
                .font(.system(size: 44))
            switch exercise.kind {
            case .separableOrNot:
                Text(exercise.verb.infinitive)
                    .font(.title.weight(.semibold))
                Text(exercise.verb.english)
                    .font(.subheadline.italic())
                    .foregroundStyle(.secondary)
            case .findVerb:
                HStack(alignment: .firstTextBaseline) {
                    Text(exercise.sentence)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    listenButton(exercise.sentence)
                }
            case .chooseSentence, .writeSentence:
                EnglishLine(text: exercise.english ?? exercise.verb.english)
                    .font(.title3)
                Text(exercise.verb.infinitive)
                    .font(.title2.weight(.semibold))
                if exercise.kind == .writeSentence {
                    HStack(spacing: 6) {
                        ForEach(exercise.cues, id: \.self) { cue in
                            Text(cue)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.separable.opacity(0.15)))
                        }
                    }
                    Text(exercise.sentence.hasSuffix("?") ? "Ends with a question mark" : "Ends with a full stop")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private func listenButton(_ text: String) -> some View {
        Button {
            Speaker.shared.speak(text)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Listen")
    }
}

private struct SeparableChoiceView: View {
    let exercise: SeparableExercise
    let isAnswered: Bool
    let onSelect: (String) -> Void

    @State private var selected: String?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(exercise.options, id: \.self) { option in
                Button {
                    guard !isAnswered else { return }
                    selected = option
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(.body.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(background(for: option), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
            }
        }
    }

    private func background(for option: String) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if option == exercise.answer { return .green.opacity(0.3) }
        if option == selected { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

private struct SeparableTypingView: View {
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField("Write the sentence…", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
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

    private func submit() {
        guard !isAnswered, !text.trimmed.isEmpty else { return }
        isFocused = false
        onSubmit(text.trimmed)
    }
}

private struct SeparableFeedbackPanel: View {
    let exercise: SeparableExercise
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

    /// Writing: every accepted order; otherwise the sentence of the exercise.
    private var sentences: [String] {
        exercise.kind == .writeSentence ? exercise.accepted : [exercise.sentence]
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

            HStack(spacing: 6) {
                Text(exercise.verb.infinitive)
                    .font(.headline)
                Text(exercise.verb.english)
                    .foregroundStyle(.secondary)
                Text(exercise.isSeparable ? "separable" : "not separable")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.separable.opacity(0.15)))
            }

            ForEach(Array(sentences.enumerated()), id: \.offset) { offset, sentence in
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
            EnglishLine(text: exercise.english)

            Text(exercise.explanation)
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
            if autoSpeak { Speaker.shared.speak(sentences[0]) }
        }
    }
}
