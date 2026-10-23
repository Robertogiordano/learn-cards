import Charts
import LearnCore
import SwiftData
import SwiftUI

/// Top of the Study tab: today's minutes against the goal, the streak and today's lesson.
struct TodayCard: View {
    let onStartLesson: () -> Void
    let onAskCoach: () -> Void

    @ObservedObject private var activity = ActivityStore.shared
    @ObservedObject private var lessons = LessonStore.shared
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 0

    private var minutesToday: Int { activity.secondsToday / 60 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(value: goalMinutes > 0 ? Double(activity.secondsToday) / Double(goalMinutes * 60) : 0,
                                 color: .orange)
                        .opacity(goalMinutes > 0 ? 1 : 0.3)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 4) {
                    Text(goalMinutes > 0 ? "Today \(minutesToday) of \(goalMinutes) min" : "Today \(minutesToday) min")
                        .font(.headline)
                    if goalMinutes > 0 {
                        let streak = activity.stats.streak(goalMinutes: goalMinutes, today: .now)
                        Label(streak == 1 ? "1 day in a row" : "\(streak) days in a row", systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(streak > 0 ? Color.orange : Color.secondary)
                    } else {
                        Text("Set a goal in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                NavigationLink {
                    ProgressScreen()
                } label: {
                    Image(systemName: "chart.bar.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Progress")
            }

            if let lesson = lessons.today, let message = lesson.message {
                Label(message, systemImage: "sparkles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button(action: onStartLesson) {
                HStack(spacing: 12) {
                    Image(systemName: lessons.today?.isComplete == true ? "checkmark.seal.fill" : "calendar.badge.clock")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lessonTitle)
                            .font(.headline)
                        Text(lessonSubtitle)
                            .font(.caption)
                            .lineLimit(2)
                            .opacity(0.9)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .background(Color.orange.gradient, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button(action: onAskCoach) {
                Label("Ask the coach for a tailored lesson", systemImage: "sparkles")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
        }
        .padding(.vertical, 6)
    }

    private var lessonTitle: String {
        guard let lesson = lessons.today else { return "Today's lesson" }
        if lesson.isComplete { return "Lesson complete" }
        return lesson.done.isEmpty ? "Start today's lesson" : "Continue the lesson"
    }

    private var lessonSubtitle: String {
        guard let lesson = lessons.today else { return "Built from your mistakes and the themes to strengthen" }
        if lesson.isComplete { return "Do it again or ask the coach for another lesson" }
        var parts = ["\(lesson.remaining.count) questions · ~\(lesson.minutes) min"]
        if !lesson.focus.isEmpty { parts.append("Focus: " + lesson.focus.prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
}

/// "What do you want today?": the coach builds a lesson from the learner's material.
struct CoachSheet: View {
    let onLessonReady: (DailyLesson) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query private var words: [Word]
    @Query private var phrases: [Phrase]
    @Query private var verbs: [Verb]
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @State private var request = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let suggestions = [
        "Focus on my mistakes",
        "Light review, little time",
        "Only stem-changing verbs",
        "Articles der/die/das",
        "Phrases and questions",
        "Numbers by ear",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E.g. I have a test on separable verbs tomorrow", text: $request, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("What do you want to do today?")
                } footer: {
                    Text("The coach only uses your own material (words, phrases, verbs, numbers) and your recent mistakes. Leave it empty and the coach decides.")
                }
                Section("Ideas") {
                    FlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) { request = suggestion }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Prepare", action: prepare)
                    }
                }
            }
            .interactiveDismissDisabled(isWorking)
        }
    }

    private func prepare() {
        guard let key = Secrets.openRouterKey else {
            errorMessage = OpenRouterClient.ClientError.missingAPIKey.localizedDescription
            return
        }
        let summary = DailyLessonBuilder.summary(words: words, phrases: phrases, verbs: verbs, request: request.trimmed)
        let modelID = model.trimmed.isEmpty ? OpenRouterModels.defaultModel : model.trimmed
        isWorking = true
        errorMessage = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                let plan = try await OpenRouterClient(apiKey: key, model: modelID).coachPlan(summary: summary)
                let lesson = DailyLessonBuilder.fromCoach(plan, words: words, phrases: phrases, verbs: verbs)
                guard !lesson.items.isEmpty else {
                    errorMessage = "The coach found no suitable exercises in your material. Try another request."
                    return
                }
                onLessonReady(lesson)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Minutes per day, streak and the most frequent mistakes.
struct ProgressScreen: View {
    @ObservedObject private var activity = ActivityStore.shared
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 0
    @State private var range = 7

    private var days: [(date: Date, seconds: Int)] { activity.stats.lastDays(range, today: .now) }

    /// Exercises where mistakes happened most in the last 30 days.
    private var frequentMistakes: [(label: String, count: Int)] {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let grouped = Dictionary(grouping: activity.stats.errors(since: since)) { error in
            "\(error.theme ?? "Numbers") · \(Self.exerciseLabel(error.exercise))"
        }
        let counted = grouped.map { (label: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
        return Array(counted.prefix(6))
    }

    var body: some View {
        List {
            Section {
                Picker("Period", selection: $range) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented)

                Chart {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Minutes", Double(day.seconds) / 60)
                        )
                        .foregroundStyle(goalMinutes > 0 && day.seconds >= goalMinutes * 60 ? Color.orange : Color.orange.opacity(0.4))
                    }
                    if goalMinutes > 0 {
                        RuleMark(y: .value("Goal", goalMinutes))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow).day())
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 6)

                let total = days.map(\.seconds).reduce(0, +) / 60
                LabeledContent("Total", value: "\(total) min")
                if goalMinutes > 0 {
                    LabeledContent("Days with goal met",
                                   value: "\(days.filter { $0.seconds >= goalMinutes * 60 }.count) of \(range)")
                    LabeledContent("Current streak", value: "\(activity.stats.streak(goalMinutes: goalMinutes, today: .now)) days")
                }
            } footer: {
                Text("Counts active time in exercises; long pauses do not count. The streak forgives one missed day a week.")
            }

            Section("Where you slip most (30 days)") {
                if frequentMistakes.isEmpty {
                    Text("No mistakes recorded. Great!")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(frequentMistakes.enumerated()), id: \.offset) { _, mistake in
                    LabeledContent(mistake.label, value: "\(mistake.count)")
                }
            }

            Section("Recent mistakes") {
                ForEach(Array(activity.stats.errors.suffix(10).reversed().enumerated()), id: \.offset) { _, error in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(error.prompt)
                            .font(.subheadline.weight(.medium))
                        Text("You answered “\(error.given)” · right: “\(error.expected)”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "article.typeGerman" → "Articolo · Scrivi".
    static func exerciseLabel(_ exercise: String) -> String {
        let parts = exercise.split(separator: ".").map(String.init)
        guard parts.count == 2 else { return exercise }
        switch parts[0] {
        case "number": return "Numbers · " + (NumberExerciseKind(rawValue: parts[1])?.title ?? parts[1])
        case "phrase": return "Phrases · " + (PhraseExerciseKind(rawValue: parts[1])?.title ?? parts[1])
        case "verb": return "Verbs · " + (VerbExerciseKind(rawValue: parts[1])?.title ?? parts[1])
        default:
            let area = StudyArea(rawValue: parts[0])
            let mode = StudyMode(rawValue: parts[1])
            return [area?.title, area.flatMap { mode?.shortTitle(in: $0) }].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
