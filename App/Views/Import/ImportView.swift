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
        case .words: return "Parole"
        case .phrases: return "Frasi"
        case .verbs: return "Verbi"
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
                    Picker("Cosa carichi", selection: $kindRaw) {
                        ForEach(ImportKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isExtracting)

                    if importKind == .phrases, let extras = phraseExtrasLabel {
                        Text("\(extras) · cambia in Impostazioni")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    preview

                    if !hasAPIKey {
                        Label("Imposta la API key di OpenRouter nelle Impostazioni.", systemImage: "key")
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
                            Label("Scatta una foto", systemImage: "camera")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!hasAPIKey || !UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Scegli dalla libreria", systemImage: "photo.on.rectangle")
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
                            Button("Riprova") { extract(lastImage) }
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
            .navigationTitle("Aggiungi parole")
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
                        addSaved(count == 1 ? "1 frase salvata" : "\(count) frasi salvate")
                    }
                case .words(let batch):
                    ReviewExtractedView(entries: batch.entries) { count in
                        addSaved(count == 1 ? "1 parola salvata" : "\(count) parole salvate")
                    }
                case .verbs(let batch):
                    ReviewVerbsView(verbs: batch.verbs, skipped: batch.skipped) { count in
                        addSaved(count == 1 ? "1 verbo salvato" : "\(count) verbi salvati")
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
        case .words: return "Estraggo le parole…"
        case .phrases:
            return phraseExtrasLabel == nil ? "Estraggo le frasi…" : "Estraggo frasi\(phraseImportWords && phraseImportVerbs ? ", parole e verbi" : phraseImportWords ? " e parole" : " e verbi")…"
        case .verbs: return "Cerco i verbi…"
        }
    }

    /// The extra extractions a phrase import runs, nil when both are off.
    private var phraseExtrasLabel: String? {
        switch (phraseImportWords, phraseImportVerbs) {
        case (true, true): return "+ parole e verbi"
        case (true, false): return "+ parole"
        case (false, true): return "+ verbi"
        case (false, false): return nil
        }
    }

    private var importHint: String {
        switch importKind {
        case .words:
            return "Fotografa una pagina di esercizi: estraggo le parole da imparare, ognuna con la sua emoji."
        case .phrases:
            return "Fotografa frasi, modi di dire o esercizi come \"Wie heißt die Frage?\": estraggo le frasi, completo le parti mancanti e le raggruppo per categoria."
        case .verbs:
            return "Fotografa una pagina con verbi (liste, tabelle, testi): estraggo ogni verbo con la coniugazione al presente."
        }
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Impossibile leggere l'immagine."
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
            errorMessage = "Impossibile preparare l'immagine."
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
                        progressTitle = count == 1 ? "Coniugo 1 verbo nuovo…" : "Coniugo \(count) verbi nuovi…"
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
                case .failure(let error)?: notices.append("Parole: \(error.localizedDescription)")
                case nil: break
                }
                switch await verbResult {
                case .success(let outcome)?: handle(outcome, into: &found)
                case .failure(let error)?: notices.append("Verbi: \(error.localizedDescription)")
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
                ? "Il verbo della foto è già nel vocabolario"
                : "Tutti i \(count) verbi della foto sono già nel vocabolario")
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

