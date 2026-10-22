import LearnCore
import SwiftUI

/// Phrase questions inside a session.
struct PhraseExerciseView: View {
    let question: PhraseQuestion
    @ObservedObject var session: StudySession

    private var isAnswered: Bool { session.feedback != nil }
    private var entry: PhraseEntry { question.entry }

    var body: some View {
        VStack(spacing: 24) {
            BonusBanner(session: session)

            PhrasePromptCard(question: question, isAnswered: isAnswered)

            switch question.kind {
            case .reorder:
                ReorderView(tiles: question.tiles, isAnswered: isAnswered) { chosen in
                    session.submitPhrase(PhraseExercises.checkReorder(chosen, entry: entry),
                                         given: chosen.joined(separator: " "))
                }
            case .translate, .questionFromAnswer, .dictation:
                SentenceTypingView(isAnswered: isAnswered) { text in
                    session.submitPhrase(PhraseChecker.check(text, accepted: entry.accepted), given: text)
                }
            case .cloze:
                SentenceTypingView(placeholder: "Parola mancante", isAnswered: isAnswered) { text in
                    let answer = question.cloze?.answer ?? ""
                    session.submitPhrase(AnswerChecker.compareGerman(text, answer), given: text)
                }
            case .speak:
                SpeechAnswerView(hint: "Tocca il microfono e di' la frase", isAnswered: isAnswered) { transcripts in
                    session.submitPhrase(PhraseChecker.checkSpoken(transcripts, accepted: entry.accepted),
                                         given: transcripts.first ?? "—")
                }
            }

            if let feedback = session.feedback {
                PhraseFeedbackPanel(
                    question: question,
                    feedback: feedback,
                    categories: session.phraseCategories,
                    onOverride: session.overrideAsCorrect,
                    onEdit: session.updatePhrase,
                    onContinue: session.advance
                )
            }
        }
    }
}

private struct PhrasePromptCard: View {
    let question: PhraseQuestion
    let isAnswered: Bool

    private var entry: PhraseEntry { question.entry }

    private var instruction: String {
        switch question.kind {
        case .reorder: return "Metti le parole nell'ordine giusto"
        case .translate: return "Scrivi in tedesco"
        case .questionFromAnswer: return "Qual è la domanda?"
        case .cloze: return "Completa la frase"
        case .dictation: return "Ascolta e scrivi la frase"
        case .speak: return "Di' in tedesco"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(entry.emoji)
                .font(.system(size: 52))

            switch question.kind {
            case .questionFromAnswer:
                Text(entry.response ?? "")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Risposta · \(entry.english)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .cloze:
                Text(question.cloze?.shown ?? entry.german)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(entry.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .dictation:
                HStack(spacing: 14) {
                    Button {
                        Speaker.shared.speak(entry.german)
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.system(size: 34))
                            .frame(width: 84, height: 84)
                            .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    }
                    .accessibilityLabel("Ascolta di nuovo")
                    Button {
                        Speaker.shared.speak(entry.german, slow: true)
                    } label: {
                        Image(systemName: "tortoise.fill")
                            .font(.title2)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(Color.accentColor.opacity(0.1)))
                    }
                    .accessibilityLabel("Ascolta lentamente")
                }
            case .reorder, .translate, .speak:
                Text(entry.english)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if question.kind == .dictation {
                Speaker.shared.speak(entry.german)
            }
        }
    }
}

/// Tap the tiles in order; tap a placed tile to put it back.
private struct ReorderView: View {
    let tiles: [String]
    let isAnswered: Bool
    let onSubmit: ([String]) -> Void

    /// Indices into `tiles`, in the order chosen.
    @State private var chosen: [Int] = []

    var body: some View {
        VStack(spacing: 18) {
            FlowLayout(spacing: 8) {
                ForEach(chosen, id: \.self) { index in
                    tile(tiles[index], filled: true) {
                        chosen.removeAll { $0 == index }
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))

            FlowLayout(spacing: 8) {
                ForEach(tiles.indices, id: \.self) { index in
                    let used = chosen.contains(index)
                    tile(tiles[index], filled: false) {
                        chosen.append(index)
                    }
                    .opacity(used ? 0.25 : 1)
                    .disabled(used)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if !isAnswered {
                Button("Controlla") {
                    onSubmit(chosen.map { tiles[$0] })
                }
                .buttonStyle(.borderedProminent)
                .disabled(chosen.count != tiles.count)
            }
        }
        .disabled(isAnswered)
        .animation(.snappy, value: chosen)
    }

    private func tile(_ word: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.body.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(filled ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

/// A multi-line field for whole sentences.
private struct SentenceTypingView: View {
    var placeholder = "Scrivi in tedesco"
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if !isAnswered {
                Button("Controlla", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmed.isEmpty)
                Text("Maiuscole e punteggiatura non contano; puoi scrivere ae, oe, ue, ss.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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

private struct PhraseFeedbackPanel: View {
    let question: PhraseQuestion
    let feedback: AnswerFeedback
    let categories: [String]
    let onOverride: () -> Void
    let onEdit: (PhraseEntry) -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @State private var isEditing = false

    private var entry: PhraseEntry { question.entry }

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

    /// The solution with the words the learner missed in bold and coloured.
    private var solution: Text {
        guard feedback.verdict != .correct, question.kind != .cloze else { return Text(entry.german) }
        let missing = PhraseChecker.missingWords(in: feedback.given, expected: entry.german)
        let words = entry.german.split(separator: " ").map(String.init)
        return words.enumerated().reduce(Text("")) { text, element in
            let (index, word) = element
            let piece = Text(index == 0 ? word : " " + word)
            return text + (missing.contains(index) ? piece.bold().foregroundColor(color) : piece)
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
                    .multilineTextAlignment(.center)
            }

            HStack(alignment: .firstTextBaseline) {
                solution
                    .font(.title3)
                    .multilineTextAlignment(.center)
                Button {
                    Speaker.shared.speak(entry.german)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }
            if !entry.variants.isEmpty {
                Text("Anche: " + entry.variants.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text(entry.english)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let response = entry.response, question.kind != .questionFromAnswer {
                Label(response, systemImage: "arrowshape.turn.up.left")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let note = entry.note {
                Text(note)
                    .font(.footnote)
                    .italic()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Menu {
                    Button {
                        isEditing = true
                    } label: {
                        Label("Modifica frase…", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "flag")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Segnala errore")
                if feedback.verdict != .correct && question.kind != .reorder {
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
            if autoSpeak && question.kind != .dictation {
                Speaker.shared.speak(entry.german)
            }
        }
        .sheet(isPresented: $isEditing) {
            PhraseEditView(title: "Modifica frase", entry: entry, categories: categories, onSave: onEdit)
        }
    }
}

/// Lays children out left to right, wrapping to new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
