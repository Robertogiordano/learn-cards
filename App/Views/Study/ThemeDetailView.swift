import LearnCore
import SwiftData
import SwiftUI

/// One theme of the path, or one word set: progress per area and a session to train each one.
struct ThemeDetailView: View {
    private let title: String
    /// The words of a set; nil for a theme, whose words are found by category.
    private let setWordIDs: Set<UUID>?

    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @State private var activeSession: StudySession?
    @State private var alertMessage: String?
    @State private var expandedAreas: Set<StudyArea> = []

    init(theme: String) {
        title = theme
        setWordIDs = nil
    }

    init(set: WordSet) {
        title = set.name
        setWordIDs = Set(set.wordIDs)
    }

    private var themeWords: [Word] {
        let scoped = setWordIDs.map { ids in words.filter { ids.contains($0.id) } }
            ?? words.filter { $0.category == title }
        return scoped.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        let themeWords = self.themeWords
        // A set spans several themes: count its words as one group.
        let progress = PathPlanner.themeProgress(themeWords.map { word in
            var pathWord = word.pathWord
            pathWord.category = title
            return pathWord
        }).first

        return List {
            if let progress {
                Section {
                    header(progress, emoji: themeWords.first?.emoji ?? "📝")
                } footer: {
                    Text("Each exercise has its own percentage and the area averages them. One right answer is worth half a word, two in a row the whole word; the star comes at 80%.")
                }

                ForEach(StudyArea.allCases, id: \.self) { area in
                    if progress.mastery[area] != nil {
                        Section {
                            areaCard(area, progress: progress, words: themeWords.filter { $0.isApplicable(to: area) })
                        }
                    }
                }
            }

            Section("Words") {
                ForEach(themeWords) { word in
                    WordRow(word: word)
                }
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeSession) { session in
            SessionView(session: session)
        }
        .alert("Heads up", isPresented: Binding(isPresent: $alertMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func header(_ progress: ThemeProgress, emoji: String) -> some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 44))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.bold())
                Text(progress.newCount > 0
                     ? "\(progress.wordCount) words · \(progress.newCount) new"
                     : "\(progress.wordCount) words")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StarsView(progress: progress)
                .font(.title3)
        }
        .padding(.vertical, 6)
    }

    private func areaCard(_ area: StudyArea, progress: ThemeProgress, words: [Word]) -> some View {
        let mastery = progress.mastery[area] ?? 0
        let due = words.filter { !$0.srs(for: area).isNew && $0.isDue(in: area) }.count
        let new = words.filter { $0.srs(for: area).isNew }.count
        let isExpanded = expandedAreas.contains(area)
        var details: [String] = []
        if due > 0 { details.append("\(due) to review") }
        if new > 0 { details.append("\(new) new") }
        if details.isEmpty { details.append(words.count == 1 ? "1 word" : "\(words.count) words") }

        return VStack(spacing: 14) {
            Button {
                withAnimation(.snappy) {
                    if isExpanded { expandedAreas.remove(area) } else { expandedAreas.insert(area) }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: area.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(area.color.gradient, in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(area.title)
                                .font(.headline)
                            if progress.hasStar(area) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(details.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(value: mastery, color: area.color)
                        .frame(width: 46, height: 46)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the exercises" : "Shows the exercises")

            if isExpanded {
                Button {
                    start(area, words: words, policy: .adaptive)
                } label: {
                    Label("Train automatically", systemImage: "wand.and.stars")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(area.color)
                .controlSize(.large)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(area.kinds, id: \.self) { kind in
                        let mode = StudyMode(rawValue: kind.rawValue) ?? .mixed
                        ExerciseTile(title: mode.shortTitle(in: area), systemImage: mode.systemImage,
                                     value: progress.kindMastery[area]?[kind] ?? 0, color: area.color) {
                            start(area, words: words, policy: .fixed(kind))
                        }
                    }
                    ExerciseTile(title: StudyMode.mixed.shortTitle(in: area), systemImage: StudyMode.mixed.systemImage,
                                 value: nil, color: area.color) {
                        start(area, words: words, policy: .fixed(nil))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
    }

    /// Due reviews first, then new words, then the weakest in the chosen exercise, rotating.
    /// `policy` is automatic (by how well each word is known) or one chosen kind of exercise.
    private func start(_ area: StudyArea, words: [Word], policy: KindPolicy) {
        let kind: ExerciseKind?
        if case .fixed(let chosen) = policy { kind = chosen } else { kind = nil }
        let candidates = words.map { $0.candidate(for: area, kind: kind) }
        let speakingOnly: Bool
        if case .fixed(.speakGerman?) = policy { speakingOnly = true } else { speakingOnly = false }
        Task { @MainActor in
            let allowSpeaking = speakingOnly || speakingInMixed ? await SpeechRecognizer.requestPermissions() : false
            if speakingOnly && !allowSpeaking {
                alertMessage = SpeechRecognizer.permissionDeniedMessage
                return
            }
            let ids = SessionPlanner.select(candidates, now: .now, limit: sessionSize, includeNotDue: true)
            guard !ids.isEmpty else { return }
            activeSession = StudySession(items: ids.map { StudyItem(wordID: $0, area: area) }, allWords: self.words,
                                         kindPolicy: policy, allowSpeaking: allowSpeaking, context: context)
        }
    }
}

/// A way to train an area, with the percentage of its kind of exercise.
struct ExerciseTile: View {
    let title: String
    let systemImage: String
    /// nil for options that mix several kinds.
    let value: Double?
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(color)
                    Spacer()
                    if let value {
                        Text("\(Int((value * 100).rounded()))%")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2, reservesSpace: true)
                if let value {
                    ProgressBar(value: value, color: color)
                } else {
                    Text("all exercises")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Circular progress with the percentage in the middle.
struct ProgressRing: View {
    let value: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0, min(value, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%")
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .animation(.snappy, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((value * 100).rounded())) percent")
    }
}

/// Thin bar whose track is tinted, so an empty bar does not look like a separator.
struct ProgressBar: View {
    let value: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * max(0, min(value, 1)))
            }
        }
        .frame(height: 6)
    }
}
