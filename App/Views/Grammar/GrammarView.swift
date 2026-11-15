import LearnCore
import SwiftData
import SwiftUI

/// The Grammar tab: the learner's pills and topics to start new ones.
struct GrammarView: View {
    @ObservedObject private var store = GrammarPillStore.shared
    @State private var path: [UUID] = []
    @State private var isCreating = false
    @StateObject private var generator = GrammarGenerator()

    private let course = GrammarCourse.a1

    /// Pills of the course, by topic title.
    private var coursePills: [String: GrammarPill] {
        var result: [String: GrammarPill] = [:]
        for pill in store.pills where result[pill.topic.title.lowercased()] == nil {
            result[pill.topic.title.lowercased()] = pill
        }
        return result
    }

    /// Pills outside the course: other levels and the learner's own topics.
    private var otherPills: [GrammarPill] {
        let courseTitles = Set(course.topics.map { $0.title.lowercased() })
        return store.pills.filter { !courseTitles.contains($0.topic.title.lowercased()) }
    }

    /// The first course topic without a star, in the book's order.
    private var nextTopic: GrammarTopic? {
        let pills = coursePills
        return course.topics.first { pills[$0.title.lowercased()]?.hasStar != true }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    CourseHeader(course: course, pills: coursePills, next: nextTopic, isWorking: generator.isWorking) { topic in
                        open(topic)
                    }
                }

                if let error = generator.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                ForEach(course.chapters) { chapter in
                    Section {
                        ForEach(chapter.topics) { topic in
                            Button {
                                open(topic)
                            } label: {
                                CourseTopicRow(topic: topic, pill: coursePills[topic.title.lowercased()],
                                               isNext: topic == nextTopic)
                            }
                            .buttonStyle(.plain)
                            .disabled(generator.isWorking)
                        }
                    } header: {
                        Text("Chapter \(chapter.number) · \(chapter.title)")
                    } footer: {
                        if chapter.number == 1 {
                            Text("Every lesson of the course is ready, also offline. Only the exercises with your words are written by the AI.")
                        }
                    }
                }

                Section {
                    ForEach(otherPills) { pill in
                        NavigationLink(value: pill.id) {
                            GrammarPillRow(pill: pill)
                        }
                    }
                    .onDelete { offsets in
                        let pills = otherPills
                        for index in offsets { store.delete(pills[index].id) }
                    }
                    Button {
                        isCreating = true
                    } label: {
                        Label("A2–B1 topics or your own…", systemImage: "plus.circle")
                    }
                    .disabled(generator.isWorking)
                } header: {
                    Text("Beyond the course")
                }
            }
            .navigationTitle("Grammar")
            .navigationDestination(for: UUID.self) { id in
                GrammarPillView(pillID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New pill")
                    .disabled(generator.isWorking)
                }
            }
            .sheet(isPresented: $isCreating) {
                NewGrammarPillSheet(generator: generator) { id in
                    path.append(id)
                }
            }
            .overlay {
                if generator.isWorking && !isCreating {
                    GeneratingOverlay(text: "Writing your pill…")
                }
            }
        }
    }

    /// Opens the topic's pill, writing it first when it does not exist yet.
    private func open(_ topic: GrammarTopic) {
        if let pill = coursePills[topic.title.lowercased()] {
            path.append(pill.id)
            return
        }
        Task { @MainActor in
            if let pill = await generator.makePill(topic) {
                path.append(pill.id)
            }
        }
    }
}

/// Calls the model and saves the pill; shared by the list and the topic sheet.
@MainActor
final class GrammarGenerator: ObservableObject {
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    func makePill(_ topic: GrammarTopic) async -> GrammarPill? {
        // Course topics ship with their lesson: no model call, works offline.
        if let lesson = GrammarLibrary.lesson(for: topic) {
            errorMessage = nil
            let pill = GrammarPill(topic: topic, lesson: lesson)
            GrammarPillStore.shared.add(pill)
            return pill
        }
        guard let key = Secrets.openRouterKey else {
            errorMessage = OpenRouterClient.ClientError.missingAPIKey.localizedDescription
            return nil
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let lesson = try await OpenRouterClient(apiKey: key, model: OpenRouterModels.grammarModel()).grammarLesson(topic: topic)
            var topic = topic
            if topic.emoji == "💊" { topic.emoji = lesson.emoji }
            if topic.level.isEmpty { topic.level = lesson.level }
            let pill = GrammarPill(topic: topic, lesson: lesson)
            GrammarPillStore.shared.add(pill)
            return pill
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}

/// Progress through the course and the next topic to study.
private struct CourseHeader: View {
    let course: GrammarCourse
    let pills: [String: GrammarPill]
    let next: GrammarTopic?
    let isWorking: Bool
    let onOpen: (GrammarTopic) -> Void

    private var mastered: Int { course.topics.filter { pills[$0.title.lowercased()]?.hasStar == true }.count }
    private var started: Int { course.topics.filter { pills[$0.title.lowercased()] != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(course.level) course").font(.title2.bold())
                    Text("\(mastered) of \(course.topics.count) mastered · \(started) started")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressRing(value: Double(mastered) / Double(max(course.topics.count, 1)), color: .purple)
                    .frame(width: 54, height: 54)
            }
            if let next {
                Button {
                    onOpen(next)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill").font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pills[next.title.lowercased()] == nil ? "Next up" : "Continue")
                                .font(.caption.weight(.semibold))
                                .opacity(0.85)
                            Text(next.title).font(.headline).multilineTextAlignment(.leading)
                            if let chapter = next.chapter {
                                Text("Chapter \(chapter)").font(.caption).opacity(0.85)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(Color.purple.gradient, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            } else {
                Label("Course complete: every topic has its star!", systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 6)
    }
}

/// A course topic with where the learner is on it.
private struct CourseTopicRow: View {
    let topic: GrammarTopic
    let pill: GrammarPill?
    let isNext: Bool

    private var status: String {
        guard let pill else { return topic.detail }
        if let mastery = pill.mastery { return "\(Int((mastery * 100).rounded()))% · \(pill.scores.count == 1 ? "1 round" : "\(pill.scores.count) rounds")" }
        return pill.lessonCompleted ? "Lesson done · practice next" : "Lesson to start"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(pill?.lesson.emoji ?? topic.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                    .font(.body.weight(isNext ? .semibold : .medium))
                    .multilineTextAlignment(.leading)
                Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if let pill {
                if pill.hasStar {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                } else if let mastery = pill.mastery {
                    ProgressRing(value: mastery, color: .purple).frame(width: 34, height: 34)
                } else {
                    Image(systemName: pill.lessonCompleted ? "checkmark.circle" : "circle.dashed")
                        .foregroundStyle(.purple)
                }
            } else {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}

struct GrammarPillRow: View {
    let pill: GrammarPill

    private var status: String {
        if let mastery = pill.mastery {
            return "\(Int((mastery * 100).rounded()))% · \(pill.scores.count == 1 ? "1 round" : "\(pill.scores.count) rounds")"
        }
        return pill.lessonCompleted ? "Lesson done · practice next" : "Lesson to start"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(pill.lesson.emoji).font(.title)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pill.lesson.title).font(.headline)
                    LevelBadge(level: pill.lesson.level)
                }
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if pill.hasStar {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            } else if pill.mastery != nil {
                ProgressRing(value: pill.mastery ?? 0, color: .purple)
                    .frame(width: 34, height: 34)
            }
        }
    }
}

struct GrammarTopicRow: View {
    let topic: GrammarTopic

    var body: some View {
        HStack(spacing: 12) {
            Text(topic.emoji).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(topic.title).font(.body.weight(.medium))
                    LevelBadge(level: topic.level)
                }
                if !topic.detail.isEmpty {
                    Text(topic.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
        }
        .contentShape(Rectangle())
    }
}

struct LevelBadge: View {
    let level: String

    var body: some View {
        if !level.isEmpty {
            Text(level)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.purple.opacity(0.18)))
        }
    }
}

struct GeneratingOverlay: View {
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text(text).font(.headline)
            Text("This takes a few seconds").font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Every catalogue topic by level, plus a free text topic.
private struct NewGrammarPillSheet: View {
    @ObservedObject var generator: GrammarGenerator
    let onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = GrammarPillStore.shared
    @State private var custom = ""

    private let levels = ["A2", "B1"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E.g. “wo and wohin”, “als or wenn”", text: $custom, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        create(GrammarTopic(title: custom.trimmed))
                    } label: {
                        Label("Create the pill", systemImage: "sparkles")
                    }
                    .disabled(custom.trimmed.isEmpty || generator.isWorking)
                } header: {
                    Text("Your own topic")
                } footer: {
                    Text("Anything that confuses you, in English, German or Italian.")
                }

                if let error = generator.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }

                ForEach(levels, id: \.self) { level in
                    Section(level) {
                        ForEach(GrammarTopic.catalogue.filter { $0.level == level }) { topic in
                            if let existing = store.pills.first(where: { $0.topic.title.lowercased() == topic.title.lowercased() }) {
                                Button {
                                    dismiss()
                                    onCreated(existing.id)
                                } label: {
                                    HStack {
                                        GrammarTopicRow(topic: topic)
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button { create(topic) } label: { GrammarTopicRow(topic: topic) }
                                    .buttonStyle(.plain)
                                    .disabled(generator.isWorking)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New grammar pill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(generator.isWorking)
                }
            }
            .overlay {
                if generator.isWorking { GeneratingOverlay(text: "Writing your pill…") }
            }
            .interactiveDismissDisabled(generator.isWorking)
        }
    }

    private func create(_ topic: GrammarTopic) {
        Task { @MainActor in
            if let pill = await generator.makePill(topic) {
                dismiss()
                onCreated(pill.id)
            }
        }
    }
}

/// A pill: open the lesson, practise with your words, ask for new exercises.
struct GrammarPillView: View {
    let pillID: UUID

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = GrammarPillStore.shared
    @Query private var words: [Word]
    @Query private var phrases: [Phrase]
    @Query private var verbs: [Verb]
    @State private var showsLesson = false
    @State private var practicePill: GrammarPill?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var confirmsDelete = false

    var body: some View {
        if let pill = store.pill(pillID) {
            content(pill)
        } else {
            ContentUnavailableView("Pill deleted", systemImage: "trash")
        }
    }

    private func content(_ pill: GrammarPill) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        Text(pill.lesson.emoji).font(.system(size: 48))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pill.lesson.title)
                                .font(.title2.bold())
                                .lineLimit(3)
                                .minimumScaleFactor(0.8)
                                .fixedSize(horizontal: false, vertical: true)
                            LevelBadge(level: pill.lesson.level)
                        }
                        .layoutPriority(1)
                        Spacer(minLength: 0)
                        if let mastery = pill.mastery {
                            ProgressRing(value: mastery, color: .purple).frame(width: 54, height: 54)
                        }
                    }
                    if !pill.lesson.summary.isEmpty {
                        Text(pill.lesson.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Button {
                    showsLesson = true
                } label: {
                    ActionCard(icon: pill.lessonCompleted ? "book.closed.fill" : "play.circle.fill",
                               title: pill.lessonCompleted ? "Review the lesson" : "Start the lesson",
                               subtitle: "\(pill.lesson.cards.count) short cards · \(pill.lesson.games.count) quick games",
                               color: pill.lessonCompleted ? .secondary : .purple)
                }
                .buttonStyle(.plain)

                Button {
                    practice(pill, fresh: pill.exercises.isEmpty)
                } label: {
                    ActionCard(icon: "pencil.and.list.clipboard",
                               title: "Practice with my words",
                               subtitle: pill.exercises.isEmpty
                                   ? "Exercises written around your vocabulary"
                                   : "\(pill.exercises.count) exercises ready",
                               color: pill.lessonCompleted ? .purple : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)

                if !pill.exercises.isEmpty {
                    Button {
                        practice(pill, fresh: true)
                    } label: {
                        Label("New exercises with other words", systemImage: "sparkles")
                    }
                    .disabled(isGenerating)
                }
            } footer: {
                Text(vocabularyNote)
            }

            Section {
                NavigationLink {
                    GrammarChatView(pillID: pill.id)
                } label: {
                    ActionCard(icon: "bubble.left.and.text.bubble.right.fill",
                               title: "Ask the tutor",
                               subtitle: pill.chat.isEmpty
                                   ? "Doubts about this topic? Ask, or send a photo of your book"
                                   : "\(pill.chat.filter { $0.role == .user }.count) questions so far",
                               color: .purple, showsChevron: false)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            if !pill.scores.isEmpty {
                Section("Progress") {
                    LabeledContent("Last round", value: "\(Int(((pill.scores.last ?? 0) * 100).rounded()))%")
                    LabeledContent("Mastery (last 3)", value: "\(Int(((pill.mastery ?? 0) * 100).rounded()))%")
                    if let last = pill.lastPracticed {
                        LabeledContent("Practised", value: last.formatted(.relative(presentation: .named)))
                    }
                }
            }

            if !pill.mistakes.isEmpty {
                Section {
                    ForEach(Array(pill.mistakes.suffix(6).reversed().enumerated()), id: \.offset) { _, mistake in
                        VStack(alignment: .leading, spacing: 2) {
                            markdownText(mistake.prompt).font(.subheadline.weight(.medium))
                            Text("You: “\(mistake.given)” · right: “\(mistake.expected)”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Recent mistakes")
                } footer: {
                    Text("New exercises train these points again, with other words.")
                }
            }

            Section("Cheat sheet") {
                ForEach(Array(pill.lesson.cards.enumerated()), id: \.offset) { _, card in
                    DisclosureGroup(card.title.isEmpty ? "Card" : card.title) {
                        GrammarCardView(card: card).padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle(pill.lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Delete pill", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete this pill?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.delete(pill.id)
                dismiss()
            }
        } message: {
            Text("The lesson and its progress are removed. Your words are not touched.")
        }
        .overlay {
            if isGenerating { GeneratingOverlay(text: "Writing exercises with your words…") }
        }
        .fullScreenCover(isPresented: $showsLesson) {
            GrammarLessonView(pill: pill) {
                // Opening the exercises while the lesson is still closing fails: wait a moment.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if let current = store.pill(pillID) { practice(current, fresh: current.exercises.isEmpty) }
                }
            }
        }
        .fullScreenCover(item: $practicePill) { pill in
            GrammarPracticeView(pill: pill) {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    if let current = store.pill(pillID) { practice(current, fresh: true) }
                }
            }
        }
    }

    private var vocabularyNote: String {
        let total = words.count + verbs.count + phrases.count
        guard total > 0 else { return "Your vocabulary is empty: the exercises will use common words." }
        return "Uses up to \(GrammarVocabulary.limits.values.reduce(0, +)) of your \(total) words, verbs and phrases, the ones you already practised first."
    }

    /// Starts the current set, or asks the model for a new one first.
    private func practice(_ pill: GrammarPill, fresh: Bool) {
        guard fresh else {
            practicePill = pill
            return
        }
        guard let key = Secrets.openRouterKey else {
            errorMessage = OpenRouterClient.ClientError.missingAPIKey.localizedDescription
            return
        }
        isGenerating = true
        errorMessage = nil
        let vocabulary = vocabularySample()
        Task { @MainActor in
            defer { isGenerating = false }
            do {
                let exercises = try await OpenRouterClient(apiKey: key, model: OpenRouterModels.grammarModel())
                    .grammarExercises(pill: pill, vocabulary: vocabulary)
                store.update(pill.id) { $0.exercises = exercises }
                practicePill = store.pill(pill.id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func vocabularySample() -> [GrammarVocabItem] {
        var items: [GrammarVocabItem] = []
        for word in words {
            let entry = word.entry
            let known = !word.srs(for: .translation).isNew
            if entry.partOfSpeech == .noun {
                items.append(.noun(german: entry.german, article: entry.article, plural: entry.plural,
                                   english: entry.english, known: known))
            } else {
                items.append(.word(german: entry.german, partOfSpeech: entry.partOfSpeech, english: entry.english, known: known))
            }
        }
        items += verbs.map { GrammarVocabItem.verb($0.entry, known: !$0.srs.isNew) }
        items += phrases.map { GrammarVocabItem.phrase(german: $0.german, english: $0.english, known: !$0.srs.isNew) }
        var rng = SystemRandomNumberGenerator()
        return GrammarVocabulary.sample(items, using: &rng)
    }
}

private struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    /// Off inside a NavigationLink, which draws its own chevron.
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(color == .secondary ? Color.accentColor : color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
