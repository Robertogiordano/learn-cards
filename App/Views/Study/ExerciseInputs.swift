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
                    Text(option)
                        .font(.title3)
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

struct TypingView: View {
    let exercise: Exercise
    let isAnswered: Bool
    let onSubmit: (Verdict, String) -> Void

    private enum Field { case word, plural }

    @State private var article: Article?
    @State private var word = ""
    @State private var plural = ""
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 14) {
            if exercise.requiresArticle {
                Picker("Articolo", selection: $article) {
                    ForEach(Article.allCases, id: \.self) { article in
                        Text(article.rawValue).tag(Article?.some(article))
                    }
                }
                .pickerStyle(.segmented)
            }

            TextField(exercise.kind == .typeEnglish ? "In inglese" : "In tedesco", text: $word)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .word)
                .submitLabel(exercise.requiresPlural ? .next : .done)
                .onSubmit {
                    if exercise.requiresPlural { focus = .plural } else { submit() }
                }

            if exercise.requiresPlural {
                HStack {
                    Text("die")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    TextField("Plurale", text: $plural)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .plural)
                        .submitLabel(.done)
                        .onSubmit { submit() }
                }
            }

            if !isAnswered {
                Button("Controlla") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(word.trimmed.isEmpty)
                if exercise.kind == .typeGerman {
                    Text("Puoi scrivere ae, oe, ue, ss al posto di ä, ö, ü, ß.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(isAnswered)
        .onAppear { focus = .word }
    }

    private func submit() {
        guard !isAnswered, !word.trimmed.isEmpty else { return }
        focus = nil
        if exercise.kind == .typeEnglish {
            onSubmit(AnswerChecker.compareEnglish(word, accepted: exercise.entry.english), word.trimmed)
            return
        }
        let answer = GermanAnswer(article: article, word: word, plural: plural)
        let verdict = AnswerChecker.checkGerman(answer, entry: exercise.entry, level: exercise.level)
        var given = [article?.rawValue, word.trimmed].compactMap { $0 }.joined(separator: " ")
        if exercise.requiresPlural {
            given += ", die \(plural.trimmed)"
        }
        onSubmit(verdict, given)
    }
}

struct SpeakingView: View {
    let exercise: Exercise
    let isAnswered: Bool
    let onSubmit: (Verdict, String) -> Void

    @StateObject private var recognizer = SpeechRecognizer()
    @State private var isEvaluating = false

    private var transcriptText: String {
        if let best = recognizer.transcripts.first { return best }
        return recognizer.isRecording ? "Ti ascolto…" : "Tocca il microfono e parla"
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
            let verdict = AnswerChecker.checkSpoken(transcripts, entry: exercise.entry, level: exercise.level)
            onSubmit(verdict, transcripts.first ?? "—")
        }
    }
}
