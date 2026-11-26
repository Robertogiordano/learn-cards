import LearnCore
import SwiftUI

extension Color {
    static let clock = Color.indigo
}

extension TimeExerciseKind {
    var systemImage: String {
        switch self {
        case .readClock: return "clock"
        case .listenChoice: return "ear"
        case .writeInformal: return "character.cursor.ibeam"
        case .writeFormal: return "keyboard"
        case .toDigits: return "number"
        case .speak: return "mic"
        }
    }

    var instruction: String {
        switch self {
        case .readClock: return "What time is it? Choose the everyday way"
        case .listenChoice: return "Listen and choose the time"
        case .writeInformal: return "Write the time the everyday way"
        case .writeFormal: return "Write the time the official way"
        case .toDigits: return "Type the time in digits"
        case .speak: return "Say the time"
        }
    }
}

/// Row of the telling-the-time section on the path.
struct TimeRow: View {
    @ObservedObject private var store = TimeStatsStore.shared
    @AppStorage(SettingsKey.timeLevel) private var levelRaw = TimeLevel.halfHours.rawValue

    private var level: TimeLevel { TimeLevel(rawValue: levelRaw) ?? .halfHours }

    var body: some View {
        HStack(spacing: 12) {
            Text("🕒")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Telling the time")
                    .font(.headline)
                Text("Wie spät ist es? · \(level.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            ProgressRing(value: store.stats.progress(level), color: .clock)
                .frame(width: 38, height: 38)
        }
    }
}

/// Telling the time: pick a level, then a kind of exercise; the cheat sheet on top.
struct TimeView: View {
    @ObservedObject private var store = TimeStatsStore.shared
    @AppStorage(SettingsKey.timeLevel) private var levelRaw = TimeLevel.halfHours.rawValue
    @State private var round: TimeRound?
    @State private var isShowingCheatSheet = false
    @State private var alertMessage: String?

    private static let sessionLength = 10

    private var level: TimeLevel { TimeLevel(rawValue: levelRaw) ?? .halfHours }

    var body: some View {
        List {
            Section {
                Button {
                    isShowingCheatSheet = true
                } label: {
                    HStack(spacing: 14) {
                        ClockFace(time: ClockTime(hour: 3, minute: 30))
                            .frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cheat sheet")
                                .font(.headline)
                            Text("halb vier = 3:30 · Viertel nach · vor halb …")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                Picker("Level", selection: $levelRaw) {
                    ForEach(TimeLevel.allCases, id: \.self) { level in
                        Text(level.shortTitle).tag(level.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(level.title)
                            .font(.title3.bold())
                        Text(store.stats.mistakes(in: level).isEmpty
                             ? "No times to go over"
                             : "\(store.stats.mistakes(in: level).count) missed times to go over")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(value: store.stats.progress(level), color: .clock)
                        .frame(width: 54, height: 54)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Everyday times stay on the 5-minute marks, as people round them on a clock; “Any minute” only changes the official times. Each exercise counts the right answers among the last 20.")
            }

            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(TimeExerciseKind.allCases, id: \.self) { kind in
                        ExerciseTile(title: kind.title, systemImage: kind.systemImage,
                                     value: store.stats.progress(level, kind), color: .clock) {
                            start(kind)
                        }
                    }
                    ExerciseTile(title: "Mixed", systemImage: "shuffle", value: nil, color: .clock) {
                        start(nil)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Telling the time")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingCheatSheet) {
            TimeCheatSheetView()
        }
        .fullScreenCover(item: $round) { round in
            TimeSessionView(round: round)
        }
        .alert("Heads up", isPresented: Binding(isPresent: $alertMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func start(_ kind: TimeExerciseKind?) {
        let level = self.level
        Task { @MainActor in
            let wantsSpeaking = kind == nil || kind == .speak
            let allowSpeaking = wantsSpeaking ? await SpeechRecognizer.requestPermissions() : false
            if kind == .speak && !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            var rng = SystemRandomNumberGenerator()
            let kinds = TimeExerciseKind.allCases.filter { allowSpeaking || $0 != .speak }
            let stats = store.stats
            let exercises = (0..<Self.sessionLength).map { _ in
                TimeQuiz.make(kind: kind ?? kinds.randomElement(using: &rng) ?? .readClock,
                              level: level, stats: stats, using: &rng)
            }
            round = TimeRound(exercises: exercises)
        }
    }
}

struct TimeRound: Identifiable {
    let id = UUID()
    let exercises: [TimeExercise]
}

// MARK: - Session

/// One round of time questions, one at a time, with the score at the end.
private struct TimeSessionView: View {
    let round: TimeRound
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var verdict: Verdict?
    @State private var given = ""
    @State private var correctCount = 0
    /// When the current question appeared: active time counts toward the daily goal.
    @State private var shownAt = Date()

    private static let maximumAnswerSeconds: TimeInterval = 60

    private var isFinished: Bool { index >= round.exercises.count }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    finished
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            question(round.exercises[index])
                                .padding()
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .scrollToFeedback(when: verdict != nil, proxy: proxy)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .principal) {
                    if !isFinished {
                        ProgressView(value: Double(index), total: Double(round.exercises.count))
                            .tint(.clock)
                            .frame(width: 160)
                    }
                }
            }
        }
        .onAppear { shownAt = .now }
    }

    private func question(_ exercise: TimeExercise) -> some View {
        VStack(spacing: 24) {
            TimePromptCard(exercise: exercise)

            switch exercise.kind {
            case .readClock, .listenChoice:
                TimeChoiceView(exercise: exercise, isAnswered: verdict != nil) { chosen in
                    grade(chosen == exercise.answer ? .correct : .wrong, given: chosen, exercise: exercise)
                }
            case .writeInformal:
                TimeTypingView(placeholder: "e.g. Viertel nach drei", isDigits: false, isAnswered: verdict != nil) { text in
                    grade(GermanTime.checkInformal(text, time: exercise.time), given: text, exercise: exercise)
                }
            case .writeFormal:
                TimeTypingView(placeholder: "e.g. fünfzehn Uhr zwanzig", isDigits: false, isAnswered: verdict != nil) { text in
                    grade(GermanTime.checkFormal(text, time: exercise.time), given: text, exercise: exercise)
                }
            case .toDigits:
                TimeTypingView(placeholder: "e.g. 3:45", isDigits: true, isAnswered: verdict != nil) { text in
                    grade(GermanTime.checkDigits(text, time: exercise.time, clockFace: true), given: text, exercise: exercise)
                }
            case .speak:
                SpeechAnswerView(hint: "Tap the microphone and say the time", isAnswered: verdict != nil) { transcripts in
                    grade(GermanTime.checkSpoken(transcripts, time: exercise.time),
                          given: transcripts.first ?? "—", exercise: exercise)
                }
            }

            if let verdict {
                TimeFeedbackPanel(exercise: exercise, verdict: verdict, given: given,
                                  canOverride: exercise.kind.isTyping || exercise.kind == .speak,
                                  onOverride: { overrideAsCorrect(exercise) }, onContinue: advance)
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
            Button("Done") { close() }
                .buttonStyle(.borderedProminent)
                .tint(.clock)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "Almost" counts as right, as for numbers: a typo is not a wrong time.
    private func grade(_ verdict: Verdict, given: String, exercise: TimeExercise) {
        self.given = given
        self.verdict = verdict
        let correct = verdict != .wrong
        if correct { correctCount += 1 }
        ActivityStore.shared.addActive(seconds: min(Date.now.timeIntervalSince(shownAt), Self.maximumAnswerSeconds))
        TimeStatsStore.shared.record(correct, time: exercise.time, level: exercise.level, kind: exercise.kind)
    }

    private func overrideAsCorrect(_ exercise: TimeExercise) {
        guard verdict == .wrong else { return }
        verdict = .correct
        correctCount += 1
        TimeStatsStore.shared.replaceLast(with: true, time: exercise.time, level: exercise.level, kind: exercise.kind)
    }

    private func advance() {
        verdict = nil
        given = ""
        index += 1
        shownAt = .now
    }

    private func close() {
        dismiss()
    }
}

private struct TimePromptCard: View {
    let exercise: TimeExercise

    var body: some View {
        VStack(spacing: 14) {
            Text(exercise.kind.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch exercise.kind {
            case .readClock, .writeInformal:
                ClockFace(time: exercise.time)
                    .frame(width: 180, height: 180)
            case .speak:
                ClockFace(time: exercise.time)
                    .frame(width: 150, height: 150)
                Text(exercise.time.digital)
                    .font(.title2.monospacedDigit().weight(.semibold))
            case .writeFormal:
                Text(exercise.time.digital)
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
            case .toDigits:
                Text("Es ist \(GermanTime.informal(exercise.time)).")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                speakButton(slow: false)
            case .listenChoice:
                HStack(spacing: 28) {
                    speakButton(slow: false)
                    speakButton(slow: true)
                }
                .font(.system(size: 44))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if exercise.kind == .listenChoice { Speaker.shared.speak(exercise.spoken) }
        }
    }

    private func speakButton(slow: Bool) -> some View {
        Button {
            Speaker.shared.speak(exercise.spoken, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : "speaker.wave.3.fill")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(slow ? "Listen slowly" : "Listen")
    }
}

private struct TimeChoiceView: View {
    let exercise: TimeExercise
    let isAnswered: Bool
    let onSelect: (String) -> Void

    @State private var selected: String?

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(exercise.options, id: \.self) { option in
                Button {
                    guard !isAnswered else { return }
                    selected = option
                    onSelect(option)
                } label: {
                    Text(option)
                        .font(exercise.kind == .listenChoice ? .title2.monospacedDigit().weight(.semibold) : .body.weight(.medium))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .padding(.horizontal, 8)
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

private struct TimeTypingView: View {
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
                .keyboardType(isDigits ? .numbersAndPunctuation : .default)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if !isAnswered {
                Button("Check", action: submit)
                    .buttonStyle(.borderedProminent)
                    .tint(.clock)
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

private struct TimeFeedbackPanel: View {
    let exercise: TimeExercise
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

    /// The everyday phrasings and, unless the time was on a clock face only, the official one.
    private var informal: [String] { GermanTime.informalVariants(exercise.time) }

    var body: some View {
        VStack(spacing: 12) {
            Label(title, systemImage: verdict == .wrong ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(color)

            if verdict != .correct {
                Text("You answered: \(given)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                ClockFace(time: exercise.time)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.kind == .writeFormal ? exercise.time.digital : exercise.time.digital12)
                        .font(.title3.monospacedDigit().weight(.semibold))
                    ForEach(informal, id: \.self) { phrase in
                        Text(GermanTime.capitalized(phrase))
                            .font(exercise.kind == .writeFormal ? .subheadline : .headline)
                    }
                    if exercise.kind == .writeFormal || exercise.kind == .speak {
                        Text(GermanTime.formal(exercise.time))
                            .font(exercise.kind == .writeFormal ? .headline : .subheadline)
                    }
                }
                .textSelection(.enabled)
                Button {
                    Speaker.shared.speak(exercise.spoken)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
            }

            if let tip = TimeTips.tip(for: exercise) {
                Text(tip)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                if verdict == .wrong && canOverride {
                    Button("I was right", action: onOverride)
                        .buttonStyle(.bordered)
                }
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(.clock)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if autoSpeak && exercise.kind != .listenChoice { Speaker.shared.speak(exercise.spoken) }
        }
    }
}

/// One line on why the answer is what it is.
enum TimeTips {
    static func tip(for exercise: TimeExercise) -> String? {
        if exercise.kind == .writeFormal {
            return "Official time: hour + Uhr + minutes, 24-hour clock. 1:00 is “ein Uhr”, not “eins Uhr”."
        }
        let next = GermanNumbers.spell(exercise.time.adding(minutes: 60).hour12)
        switch exercise.time.minute {
        case 30: return "“halb” looks forward: halb \(next) is half way TO \(next)."
        case 25, 35: return "Around the half hour, count from “halb”: 5 before or after half past."
        case 15, 45: return "Viertel nach = quarter past, Viertel vor = quarter to the next hour."
        case 20, 40: return "Both are right: 20 past / 20 to, or 10 before / after half."
        case 0: return "On the hour: “… Uhr”. 1:00 is “ein Uhr”, but alone it is “eins”."
        default: return "Up to 20 past: “… nach”; from 20 to: “… vor” the next hour."
        }
    }
}

// MARK: - Clock face

/// An analog clock showing a time.
struct ClockFace: View {
    let time: ClockTime

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            ZStack {
                Circle()
                    .fill(Color(uiColor: .systemBackground))
                Circle()
                    .stroke(Color.clock, lineWidth: max(2, size * 0.03))
                ForEach(0..<60, id: \.self) { tick in
                    let isHour = tick % 5 == 0
                    Capsule()
                        .fill(isHour ? Color.primary : Color.secondary.opacity(0.5))
                        .frame(width: isHour ? max(1.5, size * 0.018) : max(0.75, size * 0.008),
                               height: isHour ? size * 0.07 : size * 0.035)
                        .offset(y: -radius + size * (isHour ? 0.075 : 0.058))
                        .rotationEffect(.degrees(Double(tick) * 6))
                }
                if size > 100 {
                    ForEach(1...12, id: \.self) { hour in
                        let angle = Double(hour) * 30 * .pi / 180
                        Text("\(hour)")
                            .font(.system(size: size * 0.09, weight: .medium, design: .rounded))
                            .offset(x: sin(angle) * radius * 0.7, y: -cos(angle) * radius * 0.7)
                    }
                }
                hand(length: radius * 0.5, width: max(2.5, size * 0.04), color: .primary,
                     degrees: (Double(time.hour % 12) + Double(time.minute) / 60) * 30)
                hand(length: radius * 0.78, width: max(1.5, size * 0.025), color: .clock,
                     degrees: Double(time.minute) * 6)
                Circle()
                    .fill(Color.clock)
                    .frame(width: size * 0.06, height: size * 0.06)
            }
            .frame(width: size, height: size)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Clock showing \(time.digital12)")
    }

    private func hand(length: CGFloat, width: CGFloat, color: Color, degrees: Double) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}
