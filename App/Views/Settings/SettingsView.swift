import LearnCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var words: [Word]
    @Query private var phrases: [Phrase]
    @Query private var verbs: [Verb]
    @AppStorage(SettingsKey.dailyGoalMinutes) private var goalMinutes = 0
    @AppStorage(SettingsKey.reminderEnabled) private var reminderEnabled = false
    @AppStorage(SettingsKey.reminderMinutes) private var reminderMinutes = 18 * 60
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @AppStorage(SettingsKey.sessionSize) private var sessionSize = 20
    @AppStorage(SettingsKey.lessonNewWords) private var lessonNewWords = 8
    @AppStorage(SettingsKey.bonusSize) private var bonusSize = 15
    @AppStorage(SettingsKey.speakingInMixed) private var speakingInMixed = true
    @AppStorage(SettingsKey.autoSpeak) private var autoSpeak = true
    @AppStorage(SettingsKey.showEmoji) private var showEmoji = true
    @AppStorage(SettingsKey.phraseImportWords) private var phraseImportWords = true
    @AppStorage(SettingsKey.phraseImportVerbs) private var phraseImportVerbs = true
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
                goalSection
                apiSection
                modelSection
                studySection
                importSection
                backupSection
            }
            .navigationTitle("Settings")
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
                    message = "Backup exported: \(words.count) words, \(phrases.count) phrases and \(verbs.count) verbs."
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        pendingImport = try BackupService.prepareImport(from: url, existing: words, existingPhrases: phrases,
                                                                             existingVerbs: verbs)
                    } catch {
                        message = "Invalid backup: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .confirmationDialog(
                "Import backup",
                isPresented: Binding(isPresent: $pendingImport),
                titleVisibility: .visible,
                presenting: pendingImport
            ) { pending in
                Button("Merge: \(pending.newCount) new, \(pending.updatedCount) updated") {
                    run(success: "Import complete: \(pending.newCount) new, \(pending.updatedCount) updated.") {
                        try BackupService.applyMerge(pending, existing: words, existingPhrases: phrases,
                                                    existingVerbs: verbs, context: context)
                    }
                }
                Button("Replace everything (\(pending.backup.words.count) words, \(pending.phraseCount) phrases, \(pending.verbCount) verbs)", role: .destructive) {
                    run(success: "Vocabulary replaced with the backup.") {
                        try BackupService.replaceAll(with: pending.backup, existing: words, existingPhrases: phrases,
                                                    existingVerbs: verbs, context: context)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("The backup from \(pending.backup.exportedAt.formatted(date: .abbreviated, time: .shortened)) holds \(pending.backup.words.count) words, \(pending.phraseCount) phrases and \(pending.verbCount) verbs. Merge keeps the most recent version of each; Replace deletes your current vocabulary, phrases and verbs.")
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
            Button("Save API key") {
                let saved = KeychainStore.set(apiKey.trimmed, for: Secrets.openRouterAccount)
                keyStatus = saved ? "Saved in the Keychain." : "Could not save the key."
            }
            .disabled(apiKey.trimmed.isEmpty)
            if let keyStatus {
                Text(keyStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link("Create a key on openrouter.ai", destination: URL(string: "https://openrouter.ai/keys")!)
        } header: {
            Text("OpenRouter")
        } footer: {
            Text("The key stays on this iPhone only and is not included in backups.")
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
            TextField("Other model (OpenRouter id)", text: $model)
                .font(.callout.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Extraction model")
        } footer: {
            Text("It needs a model that accepts images. You can paste any id from openrouter.ai/models.")
        }
    }

    private var goalSection: some View {
        Section {
            Picker("Daily goal", selection: $goalMinutes) {
                Text("None").tag(0)
                ForEach([5, 10, 15, 20], id: \.self) { minutes in
                    Text("\(minutes) min").tag(minutes)
                }
            }
            Toggle("Reminder", isOn: $reminderEnabled)
            if reminderEnabled {
                DatePicker("Reminder time", selection: reminderTime, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Goal")
        } footer: {
            Text("Today's lesson lasts as long as your goal. The reminder only comes on days you have not reached it yet.")
        }
        .onChange(of: goalMinutes) { _, _ in
            refreshLocalLesson()
            ReminderScheduler.reschedule()
        }
        .onChange(of: reminderEnabled) { _, enabled in
            Task { @MainActor in
                if enabled, !(await ReminderScheduler.requestAuthorization()) {
                    reminderEnabled = false
                    message = "To get reminders, allow notifications in Settings > LearnCards."
                }
                ReminderScheduler.reschedule()
            }
        }
        .onChange(of: reminderMinutes) { _, _ in ReminderScheduler.reschedule() }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: reminderMinutes, to: Calendar.current.startOfDay(for: .now)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// A new goal resizes today's local lesson, if it has not been started.
    private func refreshLocalLesson() {
        guard let lesson = LessonStore.shared.today, !lesson.fromCoach, lesson.done.isEmpty else { return }
        LessonStore.shared.replace(with: DailyLessonBuilder.local(words: words, phrases: phrases, verbs: verbs))
    }

    private var studySection: some View {
        Section("Study") {
            Stepper("New words per lesson: \(lessonNewWords)", value: $lessonNewWords, in: 3...30)
            Stepper("Bonus questions: \(bonusSize)", value: $bonusSize, in: 5...50, step: 5)
            Stepper("Words per free or theme session: \(sessionSize)", value: $sessionSize, in: 5...100, step: 5)
            Toggle("Speaking in mixed sessions", isOn: $speakingInMixed)
            Toggle("Read the answer aloud", isOn: $autoSpeak)
            Toggle("Show emoji in exercises", isOn: $showEmoji)
        }
    }

    private var importSection: some View {
        Section {
            Toggle("Also extract words", isOn: $phraseImportWords)
            Toggle("Also extract verbs", isOn: $phraseImportVerbs)
        } header: {
            Text("Phrase import")
        } footer: {
            Text("When you upload phrases, words and verbs are extracted from the same photo too. With Words or Verbs only that is extracted.")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                do {
                    exportDocument = BackupDocument(data: try BackupService.exportData(words: words, phrases: phrases, verbs: verbs))
                    isExporting = true
                } catch {
                    message = error.localizedDescription
                }
            } label: {
                Label("Export vocabulary", systemImage: "square.and.arrow.up")
            }
            .disabled(words.isEmpty && phrases.isEmpty && verbs.isEmpty)

            Button {
                isImporting = true
            } label: {
                Label("Import backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text(lastExportText)
        }
    }

    private var lastExportText: String {
        guard lastExport > 0 else {
            return "You have not exported a backup yet. Your data lives only on this iPhone: export now and then to Files or iCloud Drive."
        }
        let date = Date(timeIntervalSince1970: lastExport)
        return "Last export: \(date.formatted(.relative(presentation: .named)))."
    }

    private func run(success: String, _ action: () throws -> Void) {
        do {
            try action()
            message = success
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }
}
