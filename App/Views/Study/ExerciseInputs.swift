import LearnCore
import SwiftUI

struct MultipleChoiceView: View {
    let exercise: Exercise
    let isAnswered: Bool
    let onSelect: (Int) -> Void

    @State private var selected: Int?

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(exercise.options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !isAnswered else { return }
                    selected = index
                    onSelect(index)
                } label: {
                    VStack(spacing: 2) {
                        Text(option)
                            .font(.title3)
                        if index < exercise.optionDetails.count {
                            Text(exercise.optionDetails[index])
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
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

/// Typed answers; the layout depends on the area.
struct TypingView: View {
    let exercise: Exercise
    let isAnswered: Bool
    let onSubmit: (Verdict, String, @escaping AnswerRecheck) -> Void

    private enum Field { case first, second }

    @State private var first = ""
    @State private var second = ""
    @FocusState private var focus: Field?

    private var canSubmit: Bool {
        exercise.area == .article ? !first.trimmed.isEmpty && !second.trimmed.isEmpty : !first.trimmed.isEmpty
    }

    var body: some View {
        VStack(spacing: 14) {
            switch exercise.area {
            case .translation:
                answerField(exercise.kind == .typeEnglish ? "In inglese" : "In tedesco", text: $first, field: .first, isLast: true)
            case .article:
                HStack {
                    answerField("der/die/das", text: $first, field: .first, isLast: false)
                        .frame(width: 130)
                    Text(exercise.entry.german).font(.title3)
                    Spacer()
                }
                HStack {
                    answerField("ein/eine", text: $second, field: .second, isLast: true)
                        .frame(width: 130)
                    Text(exercise.entry.german).font(.title3)
                    Spacer()
                }
            case .plural:
                HStack {
                    Text("die")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    answerField("Plurale", text: $first, field: .first, isLast: true)
                }
            }

            if !isAnswered {
                Button("Controlla") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                if exercise.kind == .typeGerman && exercise.area != .article {
                    Text("Puoi scrivere ae, oe, ue, ss al posto di ä, ö, ü, ß.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isAnswered)
        .onAppear { focus = .first }
    }

    private func answerField(_ placeholder: String, text: Binding<String>, field: Field, isLast: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focus, equals: field)
            .submitLabel(isLast ? .done : .next)
            .onSubmit {
                if isLast { submit() } else { focus = .second }
            }
    }

    private func submit() {
        guard !isAnswered, canSubmit else { return }
        focus = nil
        let entry = exercise.entry
        let first = self.first, second = self.second
        let check: AnswerRecheck
        let given: String
        switch exercise.area {
        case .translation where exercise.kind == .typeEnglish:
            check = { AnswerChecker.compareEnglish(first, accepted: $0.english) }
            given = first.trimmed
        case .translation:
            check = { AnswerChecker.checkTranslation(first, entry: $0) }
            given = first.trimmed
        case .article:
            check = { AnswerChecker.checkArticle(definite: first, indefinite: second, entry: $0) }
            given = "\(first.trimmed) \(entry.german) / \(second.trimmed) \(entry.german)"
        case .plural:
            check = { AnswerChecker.checkPlural(first, entry: $0) }
            given = "die \(first.trimmed)"
        }
        onSubmit(check(entry), given, check)
    }
}

struct SpeakingView: View {
    let exercise: Exercise
    let isAnswered: Bool
    let onSubmit: (Verdict, String, @escaping AnswerRecheck) -> Void

    private var hint: String {
        switch exercise.area {
        case .translation: return "Tocca il microfono e parla"
        case .article: return "Es. „der Tisch, ein Tisch“"
        case .plural: return "Es. „die Tische“"
        }
    }

    var body: some View {
        SpeechAnswerView(hint: hint, isAnswered: isAnswered) { transcripts in
            let area = exercise.area
            let check: AnswerRecheck = { AnswerChecker.checkSpoken(transcripts, entry: $0, area: area) }
            onSubmit(check(exercise.entry), transcripts.first ?? "—", check)
        }
    }
}

/// Microphone button with the live transcription; hands the candidate transcriptions over when done.
struct SpeechAnswerView: View {
    let hint: String
    let isAnswered: Bool
    let onFinish: ([String]) -> Void

    @StateObject private var recognizer = SpeechRecognizer()
    @State private var isEvaluating = false

    private var transcriptText: String {
        if let best = recognizer.transcripts.first { return best }
        return recognizer.isRecording ? "Ti ascolto…" : hint
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(transcriptText)
                .font(.title3)
                .foregroundStyle(recognizer.transcripts.isEmpty ? Color.secondary : Color.primary)
                .multilineTextAlignment(.center)
                .frame(minHeight: 60)

            if let error = recognizer.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !isAnswered {
                Button(action: toggle) {
                    Image(systemName: recognizer.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 84))
                        .foregroundStyle(recognizer.isRecording ? Color.red : Color.accentColor)
                }
                .disabled(isEvaluating)
                .accessibilityLabel(recognizer.isRecording ? "Ferma" : "Parla")

                Text(recognizer.isRecording ? "Tocca di nuovo quando hai finito" : " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear { recognizer.cancel() }
    }

    private func toggle() {
        guard recognizer.isRecording else {
            recognizer.start()
            return
        }
        isEvaluating = true
        Task { @MainActor in
            let transcripts = await recognizer.stop()
            isEvaluating = false
            onFinish(transcripts)
        }
    }
}

/// Top-right switch on the exercise cards: hides or shows the emoji in every exercise.
struct EmojiToggleButton: View {
    @AppStorage(SettingsKey.showEmoji) private var showEmoji = true

    var body: some View {
        Button {
            showEmoji.toggle()
        } label: {
            Image(systemName: showEmoji ? "eye" : "eye.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showEmoji ? "Nascondi emoji" : "Mostra emoji")
    }
}

extension View {
    /// Places the emoji switch in the top-right corner of an exercise card.
    func emojiToggle() -> some View {
        overlay(alignment: .topTrailing) {
            EmojiToggleButton()
                .padding(6)
        }
    }
}
