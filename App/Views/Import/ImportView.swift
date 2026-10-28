import LearnCore
import PhotosUI
import SwiftData
import SwiftUI

struct ExtractedBatch: Identifiable {
    let id = UUID()
    let entries: [VocabEntry]
}

struct ExtractedPhrases: Identifiable {
    let id = UUID()
    let phrases: [PhraseEntry]
}

struct ExtractedVerbs: Identifiable {
    let id = UUID()
    let verbs: [VerbEntry]
    /// Verbs on the photo that were already saved, so they were not conjugated again.
    var skipped: [String] = []
}

/// One review sheet; a phrase import can queue up to three, shown one after the other.
enum PendingReview: Identifiable {
    case phrases(ExtractedPhrases)
    case words(ExtractedBatch)
    case verbs(ExtractedVerbs)

    var id: UUID {
        switch self {
        case .phrases(let batch): return batch.id
        case .words(let batch): return batch.id
        case .verbs(let batch): return batch.id
        }
    }
}

/// What a photo is uploaded for: each use case has its own specialised prompt.
enum ImportKind: String, CaseIterable, Identifiable {
    case words, phrases, verbs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .words: return "Words"
        case .phrases: return "Phrases"
        case .verbs: return "Verbs"
        }
    }
}

struct ImportView: View {
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @Query private var words: [Word]
    @Query private var phrases: [Phrase]
    @Query private var verbs: [Verb]
    @AppStorage(SettingsKey.importKind) private var kindRaw = ImportKind.words.rawValue
    @AppStorage(SettingsKey.phraseImportWords) private var phraseImportWords = true
    @AppStorage(SettingsKey.phraseImportVerbs) private var phraseImportVerbs = true
    /// Reviews still to show after the current one.
    @State private var reviews: [PendingReview] = []
    @State private var currentReview: PendingReview?
    /// What was saved from the last photo, one part per review.
    @State private var savedParts: [String] = []
    /// Side notes on the last photo: verbs already known, a secondary extraction that failed.
    @State private var notices: [String] = []
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isExtracting = false
    /// Shown while extracting; the verb import changes it between its two steps.
    @State private var progressTitle = ""
    @State private var extractionStart = Date()
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var lastImage: UIImage?
    @State private var hasAPIKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker("What you upload", selection: $kindRaw) {
                        ForEach(ImportKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isExtracting)

                    if importKind == .phrases, let extras = phraseExtrasLabel {
                        Text("\(extras) · change in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    preview

                    if !hasAPIKey {
                        Label("Set your OpenRouter API key in Settings.", systemImage: "key")
                            .foregroundStyle(.orange)
                    }

                    if isExtracting {
                        VStack(spacing: 6) {
                            ProgressView(progressTitle)
                            TimelineView(.periodic(from: extractionStart, by: 1)) { context in
                                Text("\(Int(context.date.timeIntervalSince(extractionStart))) s")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                    } else {
                        Button { showCamera = true } label: {
                            Label("Take a photo", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!hasAPIKey || !UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose from library", systemImage: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!hasAPIKey)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                        if let lastImage, !isExtracting {
                            Button("Try again") { extract(lastImage) }
                        }
                    }

                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    ForEach(notices, id: \.self) { notice in
                        Label(notice, systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Add")
            .onAppear { hasAPIKey = Secrets.openRouterKey != nil }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in extract(image) }
                    .ignoresSafeArea()
            }
            // One sheet at a time: the next review opens once the previous one has closed.
            .sheet(item: $currentReview, onDismiss: showNextReview) { review in
                switch review {
                case .phrases(let batch):
                    ReviewPhrasesView(phrases: batch.phrases) { count in
                        addSaved(count == 1 ? "1 phrase saved" : "\(count) phrases saved")
                    }
                case .words(let batch):
                    ReviewExtractedView(entries: batch.entries) { count, set in
                        if count > 0 {
                            addSaved(count == 1 ? "1 word saved" : "\(count) words saved")
                        }
                        if let set {
                            addSaved("set “\(set.name)” with \(set.wordIDs.count) words")
                        }
                    }
                case .verbs(let batch):
                    ReviewVerbsView(verbs: batch.verbs, skipped: batch.skipped) { count in
                        addSaved(count == 1 ? "1 verb saved" : "\(count) verbs saved")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let lastImage {
            Image(uiImage: lastImage)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
                .padding(.top, 40)
            Text(importHint)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var importKind: ImportKind { ImportKind(rawValue: kindRaw) ?? .words }

    private var extractingTitle: String {
        switch importKind {
        case .words: return "Extracting words…"
        case .phrases:
            return phraseExtrasLabel == nil ? "Extracting phrases…" : "Extracting phrases\(phraseImportWords && phraseImportVerbs ? ", words and verbs" : phraseImportWords ? " and words" : " and verbs")…"
        case .verbs: return "Looking for verbs…"
        }
    }

    /// The extra extractions a phrase import runs, nil when both are off.
    private var phraseExtrasLabel: String? {
        switch (phraseImportWords, phraseImportVerbs) {
        case (true, true): return "+ words and verbs"
        case (true, false): return "+ words"
        case (false, true): return "+ verbs"
        case (false, false): return nil
        }
    }

    private var importHint: String {
        switch importKind {
        case .words:
            return "Take a photo of an exercise page: I extract the words to learn, each with its emoji."
        case .phrases:
            return "Take a photo of phrases, idioms or exercises like \"Wie heißt die Frage?\": I extract the phrases, fill in the missing parts and group them by category."
        case .verbs:
            return "Take a photo of a page with verbs (lists, tables, texts): I extract each verb with its present tense."
        }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Could not read the image."
                return
            }
            extract(image)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func extract(_ image: UIImage) {
        lastImage = image
        errorMessage = nil
        savedMessage = nil
        savedParts = []
        notices = []
        guard let key = Secrets.openRouterKey else {
            errorMessage = OpenRouterClient.ClientError.missingAPIKey.localizedDescription
            return
        }
        guard let jpeg = ImagePreprocessor.jpegData(from: image) else {
            errorMessage = "Could not prepare the image."
            return
        }
        let modelID = model.trimmed.isEmpty ? OpenRouterModels.defaultModel : model.trimmed
        let kind = importKind
        let wordClient = OpenRouterClient(apiKey: key, model: modelID, existingCategories: words.categories)
        let phraseClient = OpenRouterClient(apiKey: key, model: modelID, existingCategories: phrases.categories)
        let savedVerbKeys = Set(verbs.map(\.dedupeKey))
        let alsoWords = phraseImportWords
        let alsoVerbs = phraseImportVerbs
        progressTitle = extractingTitle
        extractionStart = .now
        isExtracting = true
        Task { @MainActor in
            defer { isExtracting = false }
            switch kind {
            case .words:
                do {
                    let entries = try await wordClient.extractVocabulary(fromJPEG: jpeg)
                    queueReviews([.words(ExtractedBatch(entries: entries))])
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .verbs:
                do {
                    let outcome = try await Self.extractNewVerbs(client: wordClient, jpeg: jpeg, savedKeys: savedVerbKeys) { count in
                        progressTitle = count == 1 ? "Conjugating 1 new verb…" : "Conjugating \(count) new verbs…"
                    }
                    handle(outcome)
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .phrases:
                // The same photo, three independent extractions in parallel: one failing does not stop the others.
                async let phraseResult = Self.capture(true) { try await phraseClient.extractPhrases(fromJPEG: jpeg) }
                async let wordResult = Self.capture(alsoWords) { try await wordClient.extractVocabulary(fromJPEG: jpeg) }
                async let verbResult = Self.capture(alsoVerbs) {
                    try await Self.extractNewVerbs(client: wordClient, jpeg: jpeg, savedKeys: savedVerbKeys)
                }
                var found: [PendingReview] = []
                switch await phraseResult {
                case .success(let phrases)?: found.append(.phrases(ExtractedPhrases(phrases: phrases)))
                case .failure(let error)?: errorMessage = error.localizedDescription
                case nil: break
                }
                switch await wordResult {
                case .success(let entries)?:
                    // Verbs go to their own section when that extraction runs too.
                    let kept = alsoVerbs ? entries.filter { $0.partOfSpeech != .verb } : entries
                    if !kept.isEmpty { found.append(.words(ExtractedBatch(entries: kept))) }
                case .failure(let error)?: notices.append("Words: \(error.localizedDescription)")
                case nil: break
                }
                switch await verbResult {
                case .success(let outcome)?: handle(outcome, into: &found)
                case .failure(let error)?: notices.append("Verbs: \(error.localizedDescription)")
                case nil: break
                }
                queueReviews(found)
            }
        }
    }

    /// What the verb import found: new verbs to review, or how many on the photo were all already saved.
    private enum VerbOutcome {
        case new(ExtractedVerbs)
        case allKnown(Int)
    }

    /// Infinitives first: only the verbs not yet saved get conjugated.
    private static func extractNewVerbs(client: OpenRouterClient, jpeg: Data, savedKeys: Set<String>,
                                        onConjugating: (Int) -> Void = { _ in }) async throws -> VerbOutcome {
        let infinitives = try await client.extractVerbInfinitives(fromJPEG: jpeg)
        let missing = VerbExtractionPlan.missing(infinitives, existingKeys: savedKeys)
        guard !missing.isEmpty else { return .allKnown(infinitives.count) }
        onConjugating(missing.count)
        let skipped = infinitives.filter { !missing.contains($0) }
        return .new(ExtractedVerbs(verbs: try await client.conjugateVerbs(missing), skipped: skipped))
    }

    /// Runs `work` when enabled, keeping its error instead of throwing it.
    private static func capture<T>(_ enabled: Bool, _ work: () async throws -> T) async -> Result<T, Error>? {
        guard enabled else { return nil }
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }

    private func handle(_ outcome: VerbOutcome) {
        var found: [PendingReview] = []
        handle(outcome, into: &found)
        queueReviews(found)
    }

    private func handle(_ outcome: VerbOutcome, into found: inout [PendingReview]) {
        switch outcome {
        case .new(let batch):
            found.append(.verbs(batch))
        case .allKnown(let count):
            notices.append(count == 1
                ? "The verb in the photo is already in your vocabulary"
                : "All \(count) verbs in the photo are already in your vocabulary")
        }
    }

    private func queueReviews(_ found: [PendingReview]) {
        reviews = found
        showNextReview()
    }

    private func showNextReview() {
        guard currentReview == nil, !reviews.isEmpty else { return }
        currentReview = reviews.removeFirst()
    }

    private func addSaved(_ part: String) {
        savedParts.append(part)
        savedMessage = savedParts.joined(separator: " · ")
    }
}

