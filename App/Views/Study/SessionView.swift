import LearnCore
import SwiftUI

struct SessionView: View {
    @ObservedObject var session: StudySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if session.isFinished {
                    SessionSummaryView(session: session) { dismiss() }
                } else if let exercise = session.exercise {
                    ScrollView {
                        ExerciseView(exercise: exercise, session: session)
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    // A fresh view per exercise resets typed text and selections.
                    .id(exercise.id)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
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

struct ExerciseView: View {
    let exercise: Exercise
    @ObservedObject var session: StudySession

    private var isAnswered: Bool { session.feedback != nil }

    var body: some View {
        VStack(spacing: 24) {
            PromptCard(exercise: exercise, isAnswered: isAnswered)

            switch exercise.kind {
            case .multipleChoice:
                MultipleChoiceView(exercise: exercise, isAnswered: isAnswered) { index in
                    let verdict: Verdict = index == exercise.correctIndex ? .correct : .wrong
                    session.submit(verdict, given: exercise.options[index])
                }
            case .typeGerman, .typeEnglish:
                TypingView(exercise: exercise, isAnswered: isAnswered) { verdict, given in
                    session.submit(verdict, given: given)
                }
            case .speakGerman:
                SpeakingView(exercise: exercise, isAnswered: isAnswered) { verdict, given in
                    session.submit(verdict, given: given)
                }
            }

            if let feedback = session.feedback {
                FeedbackPanel(
                    exercise: exercise,
                    feedback: feedback,
                    onOverride: session.overrideAsCorrect,
                    onContinue: session.advance
                )
            }
        }
    }
}

struct PromptCard: View {
    let exercise: Exercise
    let isAnswered: Bool

    var body: some View {
        VStack(spacing: 10) {
            Text(exercise.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // The emoji would give a German → English answer away, so it waits.
            if exercise.kind != .typeEnglish || isAnswered {
                Text(exercise.entry.emoji)
                    .font(.system(size: 72))
            }
            Text(exercise.prompt)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            if exercise.kind == .typeEnglish {
                Button {
                    Speaker.shared.speak(exercise.prompt)
                } label: {
                    Label("Ascolta", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct FeedbackPanel: View {
    let exercise: Exercise
    let feedback: AnswerFeedback
    let onOverride: () -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true

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

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .green
        case .almost: return .orange
        case .wrong: return .red
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
                Text("\(exercise.entry.emoji) \(exercise.entry.fullGerman)")
                    .font(.title3.bold())
                Button {
                    Speaker.shared.speak(exercise.entry.fullGerman)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }
            Text(exercise.entry.englishDisplay)
                .foregroundStyle(.secondary)

            HStack {
                if feedback.verdict != .correct && exercise.kind != .multipleChoice {
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
            if autoSpeak && !feedback.overridden {
                Speaker.shared.speak(exercise.entry.fullGerman)
            }
        }
    }
}

struct SessionSummaryView: View {
    @ObservedObject var session: StudySession
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("🎉")
                .font(.system(size: 80))
            Text("Sessione completata")
                .font(.title.bold())
            VStack(alignment: .leading, spacing: 12) {
                summaryRow("Giuste", count: session.results[.correct, default: 0], color: .green)
                summaryRow("Quasi", count: session.results[.almost, default: 0], color: .orange)
                summaryRow("Sbagliate", count: session.results[.wrong, default: 0], color: .red)
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            Button("Fine", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private func summaryRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label)
            Spacer(minLength: 40)
            Text("\(count)").bold()
        }
    }
}
