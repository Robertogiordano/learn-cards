import LearnCore
import PhotosUI
import SwiftData
import SwiftUI

struct ExtractedBatch: Identifiable {
    let id = UUID()
    let entries: [VocabEntry]
}

struct ImportView: View {
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @Query private var words: [Word]
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isExtracting = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    @State private var batch: ExtractedBatch?
    @State private var lastImage: UIImage?
    @State private var hasAPIKey = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    preview

                    if !hasAPIKey {
                        Label("Imposta la API key di OpenRouter nelle Impostazioni.", systemImage: "key")
                            .foregroundStyle(.orange)
                    }

                    if isExtracting {
                        ProgressView("Estraggo le parole…")
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
            Text("Fotografa una pagina di esercizi: estraggo le parole da imparare, ognuna con la sua emoji.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
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
        let categories = words.categories
        isExtracting = true
        Task { @MainActor in
            defer { isExtracting = false }
            do {
                let client = OpenRouterClient(apiKey: key, model: modelID, existingCategories: categories)
                let entries = try await client.extractVocabulary(fromJPEG: jpeg)
                batch = ExtractedBatch(entries: entries)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
