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
                } else if let number = session.numberExercise {
                    ScrollView {
                        NumberExerciseView(exercise: number, session: session)
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(number.id)
                } else if let phrase = session.phraseQuestion {
                    ScrollView {
                        PhraseExerciseView(question: phrase, session: session)
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(phrase.id)
                } else if let verb = session.verbQuestion {
                    ScrollView {
                        VerbExerciseView(question: verb, session: session)
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(verb.id)
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
            BonusBanner(session: session)

            PromptCard(exercise: exercise, isAnswered: isAnswered)

            switch exercise.kind {
            case .multipleChoice:
                MultipleChoiceView(exercise: exercise, isAnswered: isAnswered) { index in
                    let verdict: Verdict = index == exercise.correctIndex ? .correct : .wrong
                    // Article options follow the fixed gender order, so the pick maps to a gender.
                    let recheck: AnswerRecheck? = exercise.area == .article
                        ? { $0.article == Article.allCases[index] ? .correct : .wrong }
                        : nil
                    session.submit(verdict, given: exercise.options[index], recheck: recheck)
                }
            case .typeGerman, .typeEnglish:
                TypingView(exercise: exercise, isAnswered: isAnswered) { verdict, given, recheck in
                    session.submit(verdict, given: given, recheck: recheck)
                }
            case .speakGerman:
                SpeakingView(exercise: exercise, isAnswered: isAnswered) { verdict, given, recheck in
                    session.submit(verdict, given: given, recheck: recheck)
                }
            }

            if let feedback = session.feedback {
                FeedbackPanel(
                    exercise: exercise,
                    feedback: feedback,
                    themes: session.themes,
                    onOverride: session.overrideAsCorrect,
                    onCorrectArticle: session.correctArticle(to:),
                    onEditWord: session.updateWord,
                    onContinue: session.advance
                )
            }
        }
    }
}

/// Announces the bonus part on its first question, then marks its questions.
struct BonusBanner: View {
    @ObservedObject var session: StudySession

    var body: some View {
        if session.isBonusStart {
            Label("Bonus: ripasso di tutto quello che hai visto", systemImage: "gift.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.accentColor))
        } else if session.isInBonus {
            Label("Bonus", systemImage: "gift")
                .font(.caption.bold())
                .foregroundStyle(Color.accentColor)
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
            if exercise.area != .translation {
                Text(exercise.entry.englishDisplay)
                    .foregroundStyle(.secondary)
            }
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
        .background {
            if let genderColor {
                RoundedRectangle(cornerRadius: 20).fill(genderColor)
            } else {
                RoundedRectangle(cornerRadius: 20).fill(.thinMaterial)
            }
        }
    }

    /// Translation cards are tinted by the noun's gender; elsewhere the colour would give the answer away.
    private var genderColor: Color? {
        guard exercise.area == .translation, let article = exercise.entry.article else { return nil }
        return .gender(article)
    }
}

struct FeedbackPanel: View {
    let exercise: Exercise
    let feedback: AnswerFeedback
    let themes: [String]
    let onOverride: () -> Void
    let onCorrectArticle: (Article) -> Void
    let onEditWord: (VocabEntry) -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @State private var isEditingWord = false

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

    /// What to show and read aloud as the right answer.
    private var solution: String {
        switch exercise.area {
        case .translation: return exercise.entry.fullGerman
        case .article: return exercise.expectedAnswer
        case .plural: return "\(exercise.entry.withArticle) → \(exercise.expectedAnswer)"
        }
    }

    private var spokenSolution: String {
        exercise.area == .plural ? exercise.expectedAnswer : solution.replacingOccurrences(of: " / ", with: ", ")
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
                Text("\(exercise.entry.emoji) \(solution)")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Button {
                    Speaker.shared.speak(spokenSolution)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }
            Text(exercise.entry.englishDisplay)
                .foregroundStyle(.secondary)

            if let article = feedback.correctedArticle {
                Label("Genere corretto: \(article.rawValue) (\(article.genderLabel))", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if exercise.area == .article {
                    reportMenu
                }
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
                Speaker.shared.speak(spokenSolution)
            }
        }
        .onChange(of: feedback.correctedArticle) { _, article in
            if autoSpeak && article != nil {
                Speaker.shared.speak(spokenSolution)
            }
        }
        .sheet(isPresented: $isEditingWord) {
            WordEditView(title: "Modifica parola", entry: exercise.entry, themes: themes, onSave: onEditWord)
        }
    }

    /// Lets the learner fix a gender the extraction got wrong, or edit the word.
    private var reportMenu: some View {
        Menu {
            Section("Il genere giusto è…") {
                ForEach(Article.allCases.filter { $0 != exercise.entry.article }, id: \.self) { article in
                    Button("\(article.rawValue) · \(article.genderLabel)") { onCorrectArticle(article) }
                }
            }
            Button {
                isEditingWord = true
            } label: {
                Label("Modifica parola…", systemImage: "pencil")
            }
        } label: {
            Label("Segnala errore", systemImage: "flag")
        }
        .buttonStyle(.bordered)
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
            let stars = session.earnedStars
            if !stars.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nuove stelle")
                        .font(.headline)
                    ForEach(stars, id: \.self) { star in
                        Label("\(star.theme) · \(star.area.title)", systemImage: "star.fill")
                            .foregroundStyle(star.area.color)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
            if session.isLesson {
                LessonFeedback()
            }
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

/// "How was it?": tunes the next local lessons.
private struct LessonFeedback: View {
    @State private var answered = false

    var body: some View {
        VStack(spacing: 10) {
            Text(answered ? "Grazie! Ne terrò conto domani." : "Com'è andata la lezione?")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !answered {
                HStack {
                    button("Troppo facile", change: 1)
                    button("Giusta", change: 0)
                    button("Troppo difficile", change: -1)
                }
            }
        }
    }

    private func button(_ title: String, change: Int) -> some View {
        Button(title) {
            LessonStore.shared.recordFeedback(change)
            answered = true
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
