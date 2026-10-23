import LearnCore
import SwiftUI

/// Verb questions inside a session.
struct VerbExerciseView: View {
    let question: VerbQuestion
    @ObservedObject var session: StudySession

    private var isAnswered: Bool { session.feedback != nil }
    private var verb: VerbEntry { question.entry }

    var body: some View {
        VStack(spacing: 24) {
            BonusBanner(session: session)

            VerbPromptCard(question: question, isAnswered: isAnswered)

            switch question.kind {
            case .chooseForm:
                OptionGrid(options: question.options, correct: question.options.firstIndex(of: question.form),
                           isAnswered: isAnswered) { index in
                    let chosen = question.options[index]
                    session.submitVerb(VerbExercises.check(chosen, verb: verb, person: question.person), given: chosen)
                }
            case .whichPerson:
                let labels = Person.allCases.map(\.label)
                let right = verb.persons(with: question.form)
                OptionGrid(options: labels, correct: Person.allCases.firstIndex(of: question.person),
                           alsoCorrect: Set(right.map(\.rawValue)), isAnswered: isAnswered) { index in
                    let chosen = Person.allCases[index]
                    session.submitVerb(VerbExercises.checkPerson(chosen, form: question.form, verb: verb), given: chosen.label)
                }
            case .typeForm:
                FormTypingView(persons: [question.person], isAnswered: isAnswered) { answers in
                    session.submitVerb(VerbExercises.check(answers[0], verb: verb, person: question.person),
                                       given: answers[0])
                }
            case .fullTable:
                FormTypingView(persons: Person.allCases, isAnswered: isAnswered) { answers in
                    session.submitVerb(VerbExercises.checkTable(answers, verb: verb),
                                       given: answers.joined(separator: ", "))
                }
            case .speak:
                SpeechAnswerView(hint: "Say “\(question.person.pronoun) …”", isAnswered: isAnswered) { transcripts in
                    session.submitVerb(VerbExercises.checkSpoken(transcripts, verb: verb, person: question.person),
                                       given: transcripts.first ?? "—")
                }
            case .translateChoice:
                OptionGrid(options: question.options, correct: question.options.firstIndex(of: verb.infinitive),
                           isAnswered: isAnswered) { index in
                    let chosen = question.options[index]
                    session.submitVerb(chosen == verb.infinitive ? .correct : .wrong, given: chosen)
                }
            case .translateGerman:
                SingleAnswerField(placeholder: "Infinitive in German", isAnswered: isAnswered) { text in
                    session.submitVerb(VerbExercises.checkTranslation(text, verb: verb), given: text)
                }
            case .translateEnglish:
                SingleAnswerField(placeholder: "In English", isAnswered: isAnswered) { text in
                    session.submitVerb(VerbExercises.checkEnglish(text, verb: verb), given: text)
                }
            case .translateSpeak:
                SpeechAnswerView(hint: "Say the infinitive", isAnswered: isAnswered) { transcripts in
                    session.submitVerb(VerbExercises.checkSpokenInfinitive(transcripts, verb: verb),
                                       given: transcripts.first ?? "—")
                }
            }

            if let feedback = session.feedback {
                VerbFeedbackPanel(
                    question: question,
                    feedback: feedback,
                    onOverride: session.overrideAsCorrect,
                    onEdit: session.updateVerb,
                    onContinue: session.advance
                )
            }
        }
    }
}

private struct VerbPromptCard: View {
    let question: VerbQuestion
    let isAnswered: Bool

    @AppStorage(SettingsKey.showEmoji) private var showEmoji = true

    private var verb: VerbEntry { question.entry }

    private var instruction: String {
        switch question.kind {
        case .chooseForm: return "Choose the right form"
        case .typeForm: return "Conjugate in the present"
        case .fullTable: return "Conjugate for every person"
        case .whichPerson: return "Which person is it?"
        case .speak: return "Say pronoun and verb"
        case .translateChoice: return "Choose the German verb"
        case .translateGerman: return "Type the verb in German"
        case .translateEnglish: return "Type it in English"
        case .translateSpeak: return "Say the verb in German"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            // The emoji would give the meaning away when it is the question.
            if showEmoji, question.kind != .translateEnglish || isAnswered {
                Text(verb.emoji)
                    .font(.system(size: 52))
            }
            switch question.kind {
            case .translateChoice, .translateGerman, .translateSpeak:
                Text(verb.english)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
            case .translateEnglish:
                Text(verb.infinitive)
                    .font(.title.bold())
                Button {
                    Speaker.shared.speak(verb.infinitive)
                } label: {
                    Label("Listen", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            case .whichPerson:
                Text(question.form)
                    .font(.title.bold())
                Text("\(verb.infinitive) · \(verb.english)")
                    .foregroundStyle(.secondary)
            case .fullTable:
                Text(verb.infinitive)
                    .font(.title.bold())
                Text(verb.english)
                    .foregroundStyle(.secondary)
            case .chooseForm, .typeForm, .speak:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(question.person.label)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Color.verbs)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(verb.infinitive)
                        .font(.title.bold())
                }
                Text(verb.english)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .emojiToggle()
    }
}

/// Two-column option buttons; after answering, every right option turns green.
private struct OptionGrid: View {
    let options: [String]
    let correct: Int?
    var alsoCorrect: Set<Int> = []
    let isAnswered: Bool
    let onSelect: (Int) -> Void

    @State private var selected: Int?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    guard !isAnswered else { return }
                    selected = index
                    onSelect(index)
                } label: {
                    Text(option)
                        .font(.title3.weight(.medium))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(background(for: index), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isAnswered)
            }
        }
    }

    private func background(for index: Int) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if index == correct || alsoCorrect.contains(index) { return .green.opacity(0.3) }
        if index == selected { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

/// A single answer field (translation games).
private struct SingleAnswerField: View {
    let placeholder: String
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .textInputAutocapitalization(.never)
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

    private func submit() {
        guard !isAnswered, !text.trimmed.isEmpty else { return }
        isFocused = false
        onSubmit(text.trimmed)
    }
}

/// One field per person, with the pronoun in front.
private struct FormTypingView: View {
    let persons: [Person]
    let isAnswered: Bool
    let onSubmit: ([String]) -> Void

    @State private var answers: [String]
    @FocusState private var focused: Int?

    init(persons: [Person], isAnswered: Bool, onSubmit: @escaping ([String]) -> Void) {
        self.persons = persons
        self.isAnswered = isAnswered
        self.onSubmit = onSubmit
        _answers = State(initialValue: Array(repeating: "", count: persons.count))
    }

    private var canSubmit: Bool { answers.allSatisfy { !$0.trimmed.isEmpty } }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(persons.indices, id: \.self) { index in
                HStack {
                    Text(persons[index].label)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                    TextField("…", text: $answers[index])
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: index)
                        .submitLabel(index == persons.count - 1 ? .done : .next)
                        .onSubmit {
                            if index < persons.count - 1 { focused = index + 1 } else { submit() }
                        }
                }
            }
            if !isAnswered {
                Button("Check", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    .padding(.top, 4)
            }
        }
        .disabled(isAnswered)
        .onAppear { focused = 0 }
    }

    private func submit() {
        guard !isAnswered, canSubmit else { return }
        focused = nil
        onSubmit(answers.map(\.trimmed))
    }
}

private struct VerbFeedbackPanel: View {
    let question: VerbQuestion
    let feedback: AnswerFeedback
    let onOverride: () -> Void
    let onEdit: (VerbEntry) -> Void
    let onContinue: () -> Void

    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @AppStorage(SettingsKey.showEmoji) private var showEmoji = true
    @State private var isEditing = false

    private var verb: VerbEntry { question.entry }

    private var color: Color {
        switch feedback.verdict {
        case .correct: return .green
        case .almost: return .orange
        case .wrong: return .red
        }
    }

    private var title: String {
        switch feedback.verdict {
        case .correct: return feedback.overridden ? "OK, counted as right" : "Right!"
        case .almost: return "Almost: check the spelling"
        case .wrong: return "Wrong"
        }
    }

    private var icon: String {
        switch feedback.verdict {
        case .correct: return "checkmark.circle.fill"
        case .almost: return "exclamationmark.circle.fill"
        case .wrong: return "xmark.circle.fill"
        }
    }

    private var spoken: String {
        if question.kind.isTranslation { return verb.infinitive }
        return question.kind == .fullTable
            ? Person.allCases.map { "\($0.pronoun) \(verb.form(for: $0))" }.joined(separator: ", ")
            : "\(question.person.pronoun) \(question.form)"
    }

    /// Choice games: the right option is already highlighted, no "I was right".
    private var isChoice: Bool {
        [.chooseForm, .whichPerson, .translateChoice].contains(question.kind)
    }

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            if feedback.verdict != .correct || feedback.overridden {
                Text("You answered: \(feedback.given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if question.kind.isTranslation {
                HStack {
                    Text(showEmoji ? "\(verb.emoji) \(verb.infinitive)" : verb.infinitive)
                        .font(.title3.bold())
                    Button {
                        Speaker.shared.speak(spoken)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                }
                Text(verb.english)
                    .foregroundStyle(.secondary)
            } else if question.kind != .fullTable {
                HStack {
                    Text("\(question.person.pronoun) \(question.form)")
                        .font(.title3.bold())
                    Button {
                        Speaker.shared.speak(spoken)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                }
            }
            ConjugationGrid(verb: verb, highlight: question.kind == .fullTable || question.kind.isTranslation ? nil : question.person)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            if let note = verb.note {
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
                        Label("Edit verb…", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "flag")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Report a mistake")
                if feedback.verdict != .correct && !isChoice {
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
            if autoSpeak {
                Speaker.shared.speak(spoken)
            }
        }
        .sheet(isPresented: $isEditing) {
            VerbEditView(title: "Edit verb", entry: verb, onSave: onEdit)
        }
    }
}
