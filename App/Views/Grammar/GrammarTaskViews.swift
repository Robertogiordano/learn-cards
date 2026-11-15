import LearnCore
import SwiftUI

/// Inline markdown (**bold**) from the model, falling back to plain text.
func markdownText(_ text: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: text, options: options) {
        return Text(attributed)
    }
    return Text(text)
}

/// Counts the time spent on a screen towards the daily goal, without long pauses.
struct ActiveClock {
    private var since = Date()

    @MainActor mutating func commit(maximum: TimeInterval) {
        let now = Date()
        ActivityStore.shared.addActive(seconds: min(now.timeIntervalSince(since), maximum))
        since = now
    }

    mutating func restart() { since = Date() }
}

/// One game or exercise: asks, checks, explains, then hands the result over on Continue.
struct GrammarTaskView: View {
    let task: GrammarTask
    var continueTitle = "Continue"
    /// Right or wrong and the answer given (for the mistakes list).
    let onFinish: (Bool, String) -> Void

    @State private var result: (correct: Bool, given: String)?
    @State private var overridden = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(task.kind.title, systemImage: task.kind.systemImage)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            prompt

            if !task.uses.isEmpty {
                Label("Your words: " + task.uses.prefix(3).joined(separator: ", "), systemImage: "person.text.rectangle")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

            input
                .disabled(result != nil)

            if let result {
                feedback(result)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var prompt: some View {
        switch task.kind {
        case .choice, .gap:
            let filled = result.map { _ in task.prompt.replacingOccurrences(of: "___", with: "**\(task.answers.first ?? "")**") }
            markdownText(filled ?? task.prompt.replacingOccurrences(of: "___", with: "_____"))
                .font(.title2.weight(.semibold))
        default:
            markdownText(task.prompt)
                .font(.title3.weight(.semibold))
        }
        if !task.english.isEmpty {
            Text(task.english)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var input: some View {
        switch task.kind {
        case .choice:
            GrammarChoiceInput(task: task, isAnswered: result != nil) { index in
                answer(index == task.correctIndex, given: task.options[index])
            }
        case .gap:
            GrammarTypingInput(placeholder: "Missing word", multiline: false, isAnswered: result != nil) { text in
                answer(GrammarChecker.check(text, task: task), given: text)
            }
        case .transform:
            GrammarTypingInput(placeholder: "Write the sentence", multiline: true, isAnswered: result != nil) { text in
                answer(GrammarChecker.check(text, task: task), given: text)
            }
        case .order:
            GrammarTilesInput(task: task, isAnswered: result != nil) { tiles in
                answer(GrammarChecker.check(tiles: tiles, task: task), given: tiles.joined(separator: " "))
            }
        case .match:
            GrammarMatchInput(task: task) { mistakes in
                answer(mistakes == 0, given: mistakes == 1 ? "1 wrong pair" : "\(mistakes) wrong pairs")
            }
        case .sort:
            GrammarSortInput(task: task) { wrong in
                answer(wrong.isEmpty, given: wrong.joined(separator: ", "))
            }
        }
    }

    private func answer(_ correct: Bool, given: String) {
        guard result == nil else { return }
        result = (correct, given.trimmed)
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
        if let spoken = spokenAnswer, UserDefaults.standard.object(forKey: SettingsKey.autoSpeak) as? Bool ?? true {
            Speaker.shared.speak(spoken)
        }
    }

    /// The German sentence to read aloud once answered.
    private var spokenAnswer: String? {
        switch task.kind {
        case .choice, .gap:
            guard let answer = task.answers.first, task.prompt.contains("___") else { return task.answers.first }
            return task.prompt.replacingOccurrences(of: "___", with: answer)
        case .order, .transform: return task.answers.first
        case .match, .sort: return nil
        }
    }

    private func feedback(_ result: (correct: Bool, given: String)) -> some View {
        let correct = result.correct || overridden
        return VStack(alignment: .leading, spacing: 10) {
            Label(correct ? (overridden ? "OK, counted as right" : "Right!") : "Not quite",
                  systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(correct ? .green : .red)

            if !result.correct, task.kind != .match, task.kind != .sort {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.answers.first ?? "")
                        .font(.body.bold())
                    if let spoken = spokenAnswer {
                        Button {
                            Speaker.shared.speak(spoken)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Listen")
                    }
                }
                if task.answers.count > 1 {
                    Text("Also right: " + task.answers.dropFirst().joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !task.explanation.isEmpty {
                markdownText(task.explanation)
                    .font(.subheadline)
            }

            HStack {
                // The model can be wrong too, and typed answers have no typo tolerance.
                if !result.correct, !overridden, [.gap, .transform, .order].contains(task.kind) {
                    Button("I was right") { overridden = true }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(continueTitle) { onFinish(correct, result.given) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background((correct ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Inputs

private struct GrammarChoiceInput: View {
    let task: GrammarTask
    let isAnswered: Bool
    let onSelect: (Int) -> Void

    @State private var selected: Int?

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(task.options.enumerated()), id: \.offset) { index, option in
                Button {
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
            }
        }
    }

    private func background(for index: Int) -> Color {
        guard isAnswered else { return Color(uiColor: .secondarySystemBackground) }
        if index == task.correctIndex { return .green.opacity(0.3) }
        if index == selected { return .red.opacity(0.3) }
        return Color(uiColor: .secondarySystemBackground)
    }
}

private struct GrammarTypingInput: View {
    let placeholder: String
    let multiline: Bool
    let isAnswered: Bool
    let onSubmit: (String) -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if multiline {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...4)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.title3)
            .textInputAutocapitalization(multiline ? .sentences : .never)
            .autocorrectionDisabled()
            .focused($isFocused)
            .submitLabel(.done)
            .onSubmit(submit)

            if !isAnswered {
                HStack {
                    Text("ae, oe, ue, ss work for ä, ö, ü, ß.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check", action: submit)
                        .buttonStyle(.borderedProminent)
                        .disabled(text.trimmed.isEmpty)
                }
            }
        }
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !isAnswered, !text.trimmed.isEmpty else { return }
        isFocused = false
        onSubmit(text)
    }
}

/// Tap the tiles in order; tap a placed tile to put it back.
private struct GrammarTilesInput: View {
    let task: GrammarTask
    let isAnswered: Bool
    let onSubmit: ([String]) -> Void

    @State private var order: [Int] = []
    @State private var chosen: [Int] = []

    private var tiles: [String] { task.tiles }

    var body: some View {
        VStack(spacing: 16) {
            FlowLayout(spacing: 8) {
                ForEach(chosen, id: \.self) { index in
                    tile(tiles[index], filled: true) { chosen.removeAll { $0 == index } }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5])))

            FlowLayout(spacing: 8) {
                ForEach(order, id: \.self) { index in
                    let used = chosen.contains(index)
                    tile(tiles[index], filled: false) { chosen.append(index) }
                        .opacity(used ? 0.25 : 1)
                        .disabled(used)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            if !isAnswered {
                Button("Check") { onSubmit(chosen.map { tiles[$0] }) }
                    .buttonStyle(.borderedProminent)
                    .disabled(chosen.count != tiles.count)
            }
        }
        .animation(.snappy, value: chosen)
        .onAppear {
            guard order.isEmpty else { return }
            var shuffled = Array(tiles.indices).shuffled()
            // Never hand the sentence over already in order.
            if shuffled == Array(tiles.indices), tiles.count > 1 { shuffled.reverse() }
            order = shuffled
        }
    }

    private func tile(_ word: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(.body.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(filled ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// Two columns: tap one on the left, then its partner on the right.
private struct GrammarMatchInput: View {
    let task: GrammarTask
    let onDone: (Int) -> Void

    @State private var rightOrder: [Int] = []
    @State private var selectedLeft: Int?
    @State private var matched = Set<Int>()
    @State private var wrongFlash: Int?
    @State private var mistakes = 0

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(task.pairs.indices, id: \.self) { index in
                    cell(task.pairs[index].left, state: matched.contains(index) ? .done : (selectedLeft == index ? .selected : .idle)) {
                        selectedLeft = index
                    }
                }
            }
            VStack(spacing: 10) {
                ForEach(rightOrder, id: \.self) { index in
                    cell(task.pairs[index].right, state: matched.contains(index) ? .done : (wrongFlash == index ? .wrong : .idle)) {
                        tapRight(index)
                    }
                }
            }
        }
        .animation(.snappy, value: matched)
        .onAppear {
            guard rightOrder.isEmpty else { return }
            var shuffled = Array(task.pairs.indices).shuffled()
            if shuffled == Array(task.pairs.indices) { shuffled.reverse() }
            rightOrder = shuffled
        }
    }

    private enum CellState { case idle, selected, done, wrong }

    private func tapRight(_ index: Int) {
        guard let left = selectedLeft else { return }
        if left == index {
            matched.insert(index)
            selectedLeft = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if matched.count == task.pairs.count { onDone(mistakes) }
        } else {
            mistakes += 1
            wrongFlash = index
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                if wrongFlash == index { wrongFlash = nil }
            }
        }
    }

    private func cell(_ text: String, state: CellState, action: @escaping () -> Void) -> some View {
        let fill: Color = switch state {
        case .idle: Color(uiColor: .secondarySystemBackground)
        case .selected: Color.accentColor.opacity(0.25)
        case .done: Color.green.opacity(0.25)
        case .wrong: Color.red.opacity(0.3)
        }
        return Button(action: action) {
            Text(text)
                .font(.body.weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 6)
                .background(fill, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(state == .done)
    }
}

/// One item at a time: drop it into the right bucket.
private struct GrammarSortInput: View {
    let task: GrammarTask
    /// The items put in the wrong bucket.
    let onDone: ([String]) -> Void

    @State private var order: [Int] = []
    @State private var position = 0
    @State private var placed: [(item: String, bucket: String, right: Bool)] = []
    @State private var flash: Bool?

    var body: some View {
        VStack(spacing: 16) {
            if position < order.count {
                let pair = task.pairs[order[position]]
                Text(pair.left)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background((flash.map { $0 ? Color.green : Color.red } ?? Color.accentColor).opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 16))
                    .id(position)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                Text("\(position + 1) of \(order.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(task.buckets, id: \.self) { bucket in
                        Button { drop(into: bucket) } label: {
                            Text(bucket)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 64)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(flash != nil)
                    }
                }
            }

            if !placed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(placed.enumerated()), id: \.offset) { _, entry in
                        Label {
                            Text("\(entry.item) → \(entry.bucket)")
                        } icon: {
                            Image(systemName: entry.right ? "checkmark" : "xmark")
                                .foregroundStyle(entry.right ? .green : .red)
                        }
                        .font(.footnote)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.snappy, value: position)
        .onAppear {
            if order.isEmpty { order = Array(task.pairs.indices).shuffled() }
        }
    }

    private func drop(into bucket: String) {
        let pair = task.pairs[order[position]]
        let right = GrammarChecker.key(bucket) == GrammarChecker.key(pair.right)
        placed.append((pair.left, pair.right, right))
        flash = right
        UIImpactFeedbackGenerator(style: right ? .light : .rigid).impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(right ? 300 : 700))
            flash = nil
            position += 1
            if position >= order.count {
                onDone(placed.filter { !$0.right }.map(\.item))
            }
        }
    }
}
