import LearnCore
import SwiftUI

/// Number questions inside a session: listen and pick, listen and type, write in words, say it.
struct NumberExerciseView: View {
    let exercise: NumberExercise
    @ObservedObject var session: StudySession

    private var isAnswered: Bool { session.feedback != nil }

    var body: some View {
        VStack(spacing: 24) {
            BonusBanner(session: session)

            NumberPromptCard(exercise: exercise, isAnswered: isAnswered)

            switch exercise.kind {
            case .listenChoice:
                NumberChoiceView(exercise: exercise, isAnswered: isAnswered) { index in
                    let verdict: Verdict = index == exercise.correctIndex ? .correct : .wrong
                    session.submitNumber(verdict, given: GermanNumbers.digits(exercise.options[index]))
                }
            case .listenDigits:
                NumberTypingView(placeholder: "Scrivi le cifre", isDigits: true, isAnswered: isAnswered) { text in
                    session.submitNumber(NumberQuiz.checkDigits(text, number: exercise.number), given: text)
                }
            case .writeWords:
                NumberTypingView(placeholder: "Scrivi a lettere", isDigits: false, isAnswered: isAnswered) { text in
                    session.submitNumber(NumberQuiz.checkWords(text, number: exercise.number), given: text)
                }
            case .speak:
                SpeechAnswerView(hint: "Tocca il microfono e di' il numero", isAnswered: isAnswered) { transcripts in
                    session.submitNumber(NumberQuiz.checkSpoken(transcripts, number: exercise.number),
                                         given: transcripts.first ?? "—")
                }
            }

            if let feedback = session.feedback {
                NumberFeedbackPanel(
                    exercise: exercise,
                    feedback: feedback,
                    onOverride: session.overrideAsCorrect,
                    onContinue: session.advance
                )
            }
        }
    }
}

private struct NumberPromptCard: View {
    let exercise: NumberExercise
    let isAnswered: Bool

    private var instruction: String {
        switch exercise.kind {
        case .listenChoice: return "Ascolta e scegli il numero"
        case .listenDigits: return "Ascolta e scrivi il numero in cifre"
        case .writeWords: return "Scrivi il numero a lettere"
        case .speak: return "Di' il numero in tedesco"
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if exercise.kind.isListening {
                HStack(spacing: 14) {
                    Button {
                        Speaker.shared.speak(String(exercise.number))
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 40))
                            .frame(width: 96, height: 96)
                            .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    }
                    .accessibilityLabel("Ascolta di nuovo")
                    Button {
                        Speaker.shared.speak(String(exercise.number), slow: true)
                    } label: {
                        Image(systemName: "tortoise.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(Circle().fill(Color.accentColor.opacity(0.1)))
                    }
                    .accessibilityLabel("Ascolta lentamente")
                }
                if isAnswered {
                    Text(exercise.digits)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                }
            } else {
                Text(exercise.digits)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if exercise.kind.isListening {
                Speaker.shared.speak(String(exercise.number))
            }
        }
    }
}

private struct NumberChoiceView: View {
    let exercise: NumberExercise
    let isAnswered: Bool
    let onSelect: (Int) -> Void

    @State private var selected: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !isAnswered else { return }
                    selected = index
                    onSelect(index)
                } label: {
                    Text(GermanNumbers.digits(option))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(background(for: index), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
            }
        }
    }

    private func background(for index: Int) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if index == exercise.correctIndex { return .green.opacity(0.3) }
        if index == selected { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

private struct NumberTypingView: View {
    let placeholder: String
    let isDigits: Bool
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .keyboardType(isDigits ? .numberPad : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if !isAnswered {
                Button("Controlla", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmed.isEmpty)
                if !isDigits {
                    Text("Tutto attaccato, come in tedesco: einundzwanzig. Puoi scrivere ss al posto di ß.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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

private struct NumberFeedbackPanel: View {
    let exercise: NumberExercise
    let feedback: AnswerFeedback
    let onOverride: () -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .green
        case .almost: return .orange
        case .wrong: return .red
        }
    }

    private var title: String {
        switch feedback.verdict {
        case .correct: return feedback.overridden ? "Ok, contata giusta" : "Giusto!"
        case .almost: return "Quasi: controlla l'ortografia"
        case .wrong: return "Sbagliato"
        }
    }

    private var icon: String {
        switch feedback.verdict {
        case .correct: return "checkmark.circle.fill"
        case .almost: return "exclamationmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            if feedback.verdict != .correct || feedback.overridden {
                Text("Hai risposto: \(feedback.given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(exercise.digits)
                    .font(.title2.bold().monospacedDigit())
                Button {
                    Speaker.shared.speak(String(exercise.number))
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }
            Text(exercise.words)
                .font(.title3)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)

            HStack {
                if feedback.verdict != .correct && exercise.kind != .listenChoice {
                    Button("Avevo ragione", action: onOverride)
                        .buttonStyle(.bordered)
                }
                Button("Continua", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            // Listening questions already played the number.
            if autoSpeak && !exercise.kind.isListening {
                Speaker.shared.speak(String(exercise.number))
            }
        }
    }
}
