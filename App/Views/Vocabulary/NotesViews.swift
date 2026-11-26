import LearnCore
import SwiftUI

/// The learner's own notes, most recently edited first.
struct NotesListView: View {
    @ObservedObject private var store = NoteStore.shared
    @State private var editing: StudyNote?

    var body: some View {
        List {
            if !store.notes.isEmpty {
                Text(store.notes.count == 1 ? "1 note" : "\(store.notes.count) notes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(store.notes) { note in
                Button { editing = note } label: {
                    NoteRow(note: note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for id in offsets.map({ store.notes[$0].id }) { store.delete(id) }
            }
        }
        .overlay {
            if store.notes.isEmpty {
                ContentUnavailableView(
                    "No notes",
                    systemImage: "note.text",
                    description: Text("Write down what you want to remember, e.g. “es gibt = ci sono”, and let the AI explain it. Add one with +.")
                )
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = StudyNote() } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { note in
            NoteEditView(note: note, isNew: store.note(note.id) == nil)
        }
    }
}

struct NoteRow: View {
    let note: StudyNote

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(note.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if note.explanation != nil {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Explained")
                }
            }
            if !note.title.trimmed.isEmpty, !note.text.trimmed.isEmpty {
                Text(note.text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

/// Writes a note; “Explain with AI” tidies it up and adds why it works that way.
struct NoteEditView: View {
    let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel
    @State private var draft: StudyNote
    /// The note as it was before the last AI change, so it can be undone.
    @State private var beforeAI: StudyNote?
    @State private var isImproving = false
    @State private var message: String?

    init(note: StudyNote, isNew: Bool) {
        self.isNew = isNew
        _draft = State(initialValue: note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("About") {
                    TextField("e.g. es gibt", text: $draft.title)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("e.g. es gibt = ci sono", text: $draft.text, axis: .vertical)
                        .lineLimit(3...12)
                    AIFillButton(title: draft.explanation == nil ? "Explain with AI" : "Explain again with AI",
                                 isFilling: isImproving, message: message, action: improve)
                        .disabled(draft.isEmpty || isImproving)
                    if let beforeAI {
                        Button {
                            draft = beforeAI
                            self.beforeAI = nil
                        } label: {
                            Label("Undo AI changes", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("My note")
                } footer: {
                    Text("Write it your way. “Explain with AI” corrects the note and explains why, e.g. why “es gibt” is not “lui dà”.")
                }
                if let explanation = draft.explanation {
                    Section("Explanation") {
                        markdownText(explanation)
                            .textSelection(.enabled)
                        Button(role: .destructive) {
                            draft.explanation = nil
                        } label: {
                            Label("Remove explanation", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .navigationTitle(isNew ? "New note" : "Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(draft.isEmpty)
                }
            }
        }
    }

    private func improve() {
        guard !draft.isEmpty, !isImproving else { return }
        guard let key = Secrets.openRouterKey else {
            message = "Add an OpenRouter API key in Settings to explain notes with AI."
            return
        }
        let modelID = model.trimmed.isEmpty ? OpenRouterModels.defaultModel : model.trimmed
        let original = draft
        isImproving = true
        message = nil
        Task { @MainActor in
            defer { isImproving = false }
            do {
                let result = try await OpenRouterClient(apiKey: key, model: modelID).improveNote(original)
                beforeAI = original
                if !result.title.isEmpty { draft.title = result.title }
                if !result.text.isEmpty { draft.text = result.text }
                draft.explanation = result.explanation
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func save() {
        var note = draft
        note.title = note.title.trimmed
        note.text = note.text.trimmed
        NoteStore.shared.save(note)
        dismiss()
    }
}
