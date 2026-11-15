import LearnCore
import SwiftUI

// MARK: - Lesson

/// The theory, one card per screen, with little games in between.
struct GrammarLessonView: View {
    let pill: GrammarPill
    /// Called from the last screen: go straight to the exercises.
    let onPractice: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var clock = ActiveClock()

    private var steps: [GrammarLesson.Step] { pill.lesson.steps }

    var body: some View {
        NavigationStack {
            Group {
                if index < steps.count {
                    ScrollView {
                        step(steps[index])
                            .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(index)
                } else {
                    finished
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                }
                ToolbarItem(placement: .principal) {
                    if index < steps.count {
                        ProgressView(value: Double(index), total: Double(max(steps.count, 1)))
                            .frame(width: 160)
                    }
                }
            }
        }
        .onAppear { clock.restart() }
    }

    @ViewBuilder private func step(_ step: GrammarLesson.Step) -> some View {
        switch step {
        case .card(let card):
            VStack(alignment: .leading, spacing: 20) {
                if index == 0 {
                    HStack(spacing: 12) {
                        Text(pill.lesson.emoji).font(.system(size: 44))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pill.lesson.title).font(.title2.bold())
                            if !pill.lesson.summary.isEmpty {
                                Text(pill.lesson.summary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                GrammarCardView(card: card)
                navigation
            }
        case .game(let game):
            VStack(alignment: .leading, spacing: 12) {
                Label("Quick game", systemImage: "gamecontroller.fill")
                    .font(.headline)
                    .foregroundStyle(.purple)
                GrammarTaskView(task: game) { _, _ in next() }
                    .padding()
                    .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var navigation: some View {
        HStack {
            if index > 0 {
                Button {
                    withAnimation { index -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button {
                next()
            } label: {
                Label(index == steps.count - 1 ? "Finish" : "Next", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 8)
    }

    private var finished: some View {
        VStack(spacing: 20) {
            Text("🎓").font(.system(size: 80))
            Text("Lesson complete").font(.title.bold())
            Text("Now use it with your own words: the exercises are written around your vocabulary.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                close()
                onPractice()
            } label: {
                Label("Practice with my words", systemImage: "pencil.and.list.clipboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Later") { close() }
        }
        .padding(32)
    }

    private func next() {
        clock.commit(maximum: 120)
        withAnimation { index += 1 }
        if index >= steps.count {
            GrammarPillStore.shared.update(pill.id) { $0.lessonCompleted = true }
        }
    }

    private func close() {
        clock.commit(maximum: 120)
        dismiss()
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

/// One theory card: text, examples to listen to, a table and a tip.
struct GrammarCardView: View {
    let card: GrammarCard

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !card.title.isEmpty {
                Text(card.title).font(.title3.bold())
            }
            markdownText(card.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if !card.table.isEmpty {
                GrammarTableView(table: card.table)
            }

            if !card.examples.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(card.examples.enumerated()), id: \.offset) { _, example in
                        Button {
                            Speaker.shared.speak(example.german.replacingOccurrences(of: "**", with: ""))
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    markdownText(example.german).font(.body)
                                    Text(example.english).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }

            if !card.tip.isEmpty {
                Label {
                    markdownText(card.tip).font(.subheadline)
                } icon: {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct GrammarTableView: View {
    let table: GrammarTable

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                if !table.headers.isEmpty {
                    GridRow {
                        ForEach(Array(table.headers.enumerated()), id: \.offset) { _, header in
                            cell(header).font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }
                    }
                    .background(Color.accentColor.opacity(0.12))
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                            markdownCell(value).fontWeight(column == 0 ? .semibold : .regular)
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2) ? Color.clear : Color(uiColor: .secondarySystemBackground))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2)))
        }
    }

    private func cell(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
    }

    private func markdownCell(_ text: String) -> some View {
        markdownText(text)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minWidth: 64, maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Practice

/// The exercises of a pill: one at a time; a wrong one comes back once at the end.
struct GrammarPracticeView: View {
    let pill: GrammarPill
    /// Asks for a fresh set from the summary screen.
    let onNewExercises: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var queue: [GrammarTask] = []
    @State private var position = 0
    /// First-try results, which make the score.
    @State private var firstTry: [UUID: Bool] = [:]
    @State private var retried = Set<UUID>()
    @State private var mistakes: [GrammarMistake] = []
    @State private var saved = false
    @State private var clock = ActiveClock()

    private var isFinished: Bool { !queue.isEmpty && position >= queue.count }
    private var score: Double {
        firstTry.isEmpty ? 0 : Double(firstTry.values.filter { $0 }.count) / Double(firstTry.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isFinished {
                    summary
                } else if position < queue.count {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if position >= pill.exercises.count {
                                Label("Once more", systemImage: "arrow.counterclockwise")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            GrammarTaskView(task: queue[position]) { correct, given in
                                answered(queue[position], correct: correct, given: given)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(position)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Close") { close() }
                }
                ToolbarItem(placement: .principal) {
                    if !isFinished {
                        ProgressView(value: Double(position), total: Double(max(queue.count, 1)))
                            .frame(width: 160)
                    }
                }
            }
        }
        .onAppear {
            if queue.isEmpty { queue = pill.exercises }
            clock.restart()
        }
    }

    private func answered(_ task: GrammarTask, correct: Bool, given: String) {
        clock.commit(maximum: 90)
        if firstTry[task.id] == nil {
            firstTry[task.id] = correct
            if !correct {
                mistakes.append(GrammarMistake(prompt: task.prompt, given: given, expected: task.displayAnswer))
            }
        }
        if !correct, !retried.contains(task.id) {
            retried.insert(task.id)
            queue.append(task)
        }
        position += 1
        if position >= queue.count { save() }
    }

    private func save() {
        guard !saved, !firstTry.isEmpty else { return }
        saved = true
        GrammarPillStore.shared.update(pill.id) { $0.record(score: score, mistakes: mistakes) }
    }

    private func close() {
        clock.commit(maximum: 90)
        dismiss()
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(score >= GrammarPill.starThreshold ? "🌟" : "💪").font(.system(size: 72))
                Text("\(Int((score * 100).rounded()))% right on the first try")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(score >= GrammarPill.starThreshold
                     ? "Great! Keep it fresh with a new set in a few days."
                     : "Do a new set: it trains again the points you missed, with other words.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if !mistakes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("To remember").font(.headline)
                        ForEach(Array(mistakes.enumerated()), id: \.offset) { _, mistake in
                            VStack(alignment: .leading, spacing: 2) {
                                markdownText(mistake.prompt).font(.subheadline.weight(.medium))
                                Text("You: “\(mistake.given)” · right: “\(mistake.expected)”")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    dismiss()
                    onNewExercises()
                } label: {
                    Label("New exercises", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Done") { dismiss() }
            }
            .padding(32)
        }
    }
}
