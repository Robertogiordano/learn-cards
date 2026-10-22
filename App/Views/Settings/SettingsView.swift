import LearnCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @AppStorage(SettingsKey.lastExport) private var lastExport: Double = 0

    @State private var apiKey = ""
    @State private var keyStatus: String?
    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingImport: PendingImport?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                modelSection
                studySection
                backupSection
            }
            .navigationTitle("Impostazioni")
            .onAppear { apiKey = Secrets.openRouterKey ?? "" }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: BackupService.defaultFilename()
            ) { result in
                switch result {
                case .success:
                    lastExport = Date().timeIntervalSince1970
                    message = "Backup esportato: \(words.count) parole."
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        pendingImport = try BackupService.prepareImport(from: url, existing: words)
                    } catch {
                        message = "Backup non valido: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Importa backup",
                isPresented: Binding(isPresent: $pendingImport),
                titleVisibility: .visible,
                presenting: pendingImport
            ) { pending in
                Button("Unisci: \(pending.merge.inserts.count) nuove, \(pending.merge.updates.count) aggiornate") {
                    run(success: "Import completato: \(pending.merge.inserts.count) nuove, \(pending.merge.updates.count) aggiornate.") {
                        try BackupService.applyMerge(pending.merge, existing: words, context: context)
                    }
                }
                Button("Sostituisci tutto (\(pending.backup.words.count) parole)", role: .destructive) {
                    run(success: "Vocabolario sostituito con il backup.") {
                        try BackupService.replaceAll(with: pending.backup, existing: words, context: context)
                    }
                }
                Button("Annulla", role: .cancel) {}
            } message: { pending in
                Text("Il backup del \(pending.backup.exportedAt.formatted(date: .abbreviated, time: .shortened)) contiene \(pending.backup.words.count) parole. Unisci tiene la versione più recente di ogni parola; Sostituisci cancella il vocabolario attuale.")
            }
            .alert("Backup", isPresented: Binding(isPresent: $message)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var apiSection: some View {
        Section {
            SecureField("sk-or-…", text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Salva API key") {
                let saved = KeychainStore.set(apiKey.trimmed, for: Secrets.openRouterAccount)
                keyStatus = saved ? "Salvata nel Portachiavi." : "Impossibile salvare la key."
            }
            .disabled(apiKey.trimmed.isEmpty)
            if let keyStatus {
                Text(keyStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link("Crea una key su openrouter.ai", destination: URL(string: "https://openrouter.ai/keys")!)
        } header: {
            Text("OpenRouter")
        } footer: {
            Text("La key resta solo su questo iPhone e non viene inclusa nei backup.")
        }
    }

    private var modelSection: some View {
        Section {
            ForEach(OpenRouterModels.presets) { preset in
                Button {
                    model = preset.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .foregroundStyle(.primary)
                            Text(preset.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model == preset.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            TextField("Altro modello (id OpenRouter)", text: $model)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Modello per l'estrazione")
        } footer: {
            Text("Serve un modello che accetti immagini. Puoi incollare qualsiasi id da openrouter.ai/models.")
        }
    }

    private var studySection: some View {
        Section("Studio") {
            Stepper("Parole per sessione: \(sessionSize)", value: $sessionSize, in: 5...100, step: 5)
            Toggle("Pronuncia nel misto", isOn: $speakingInMixed)
            Toggle("Leggi ad alta voce la soluzione", isOn: $autoSpeak)
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try BackupService.exportData(words: words))
                    isExporting = true
                } catch {
                    message = error.localizedDescription
                }
            } label: {
                Label("Esporta vocabolario", systemImage: "square.and.arrow.up")
            }
            .disabled(words.isEmpty)

            Button {
                isImporting = true
            } label: {
                Label("Importa backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(lastExportText)
        }
    }

    private var lastExportText: String {
        guard lastExport > 0 else {
            return "Non hai ancora esportato un backup. I dati stanno solo su questo iPhone: esporta ogni tanto su File o iCloud Drive."
        }
        let date = Date(timeIntervalSince1970: lastExport)
        return "Ultimo export: \(date.formatted(.relative(presentation: .named)))."
    }

    private func run(success: String, _ action: () throws -> Void) {
        do {
            try action()
            message = success
        } catch {
            message = "Import non riuscito: \(error.localizedDescription)"
        }
    }
}
