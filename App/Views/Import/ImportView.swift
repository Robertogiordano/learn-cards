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
    @State private var phraseBatch: ExtractedPhrases?
    @State private var verbBatch: ExtractedVerbs?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isExtracting = false
    /// Shown while extracting; the verb import changes it between its two steps.
    @State private var progressTitle = ""
    @State private var extractionStart = Date()
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var batch: ExtractedBatch?
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
            .sheet(item: $batch) { batch in
                ReviewExtractedView(entries: batch.entries) { count in
                    savedMessage = count == 1 ? "1 parola salvata nel vocabolario" : "\(count) parole salvate nel vocabolario"
                }
            }
            .sheet(item: $verbBatch) { batch in
                ReviewVerbsView(verbs: batch.verbs, skipped: batch.skipped) { count in
                    savedMessage = count == 1 ? "1 verbo salvato" : "\(count) verbi salvati"
                }
            }
            .sheet(item: $phraseBatch) { batch in
                ReviewPhrasesView(phrases: batch.phrases) { count in
                    savedMessage = count == 1 ? "1 frase salvata" : "\(count) frasi salvate"
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
        case .phrases: return "Estraggo le frasi…"
        case .verbs: return "Cerco i verbi…"
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
        let categories = kind == .phrases ? phrases.categories : words.categories
        let savedVerbKeys = Set(verbs.map(\.dedupeKey))
        progressTitle = extractingTitle
        extractionStart = .now
        isExtracting = true
        Task { @MainActor in
            defer { isExtracting = false }
            do {
                let client = OpenRouterClient(apiKey: key, model: modelID, existingCategories: categories)
                switch kind {
                case .words:
                    batch = ExtractedBatch(entries: try await client.extractVocabulary(fromJPEG: jpeg))
                case .phrases:
                    phraseBatch = ExtractedPhrases(phrases: try await client.extractPhrases(fromJPEG: jpeg))
                case .verbs:
                    // Infinitives first: only the verbs not yet saved get conjugated.
                    let infinitives = try await client.extractVerbInfinitives(fromJPEG: jpeg)
                    let missing = VerbExtractionPlan.missing(infinitives, existingKeys: savedVerbKeys)
                    let skipped = infinitives.filter { !missing.contains($0) }
                    guard !missing.isEmpty else {
                        savedMessage = infinitives.count == 1
                            ? "Il verbo della foto è già nel vocabolario"
                            : "Tutti i \(infinitives.count) verbi della foto sono già nel vocabolario"
                        return
                    }
                    progressTitle = missing.count == 1 ? "Coniugo 1 verbo nuovo…" : "Coniugo \(missing.count) verbi nuovi…"
                    verbBatch = ExtractedVerbs(verbs: try await client.conjugateVerbs(missing), skipped: skipped)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
