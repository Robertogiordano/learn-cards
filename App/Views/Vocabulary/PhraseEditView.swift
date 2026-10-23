import LearnCore
import SwiftUI

/// Edits a phrase: manual phrases, saved ones and extracted ones under review.
struct PhraseEditView: View {
    let title: String
    let categories: [String]
    let onSave: (PhraseEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PhraseEntry
    @State private var variantsText: String
    @State private var responseText: String
    @State private var noteText: String

    init(title: String, entry: PhraseEntry, categories: [String] = [], onSave: @escaping (PhraseEntry) -> Void) {
        self.title = title
        self.categories = categories
        self.onSave = onSave
        _draft = State(initialValue: entry)
        _variantsText = State(initialValue: entry.variants.joined(separator: "\n"))
        _responseText = State(initialValue: entry.response ?? "")
        _noteText = State(initialValue: entry.note ?? "")
    }

    private var isValid: Bool { !draft.german.trimmed.isEmpty && !draft.english.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("German") {
                    TextField("Phrase", text: $draft.german, axis: .vertical)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("One per line", text: $variantsText, axis: .vertical)
                        .lineLimit(1...4)
                        .autocorrectionDisabled()
                } header: {
                    Text("Other correct forms")
                } footer: {
                    Text("These count as right answers too, e.g. the form with “Sie”.")
                }
                Section("English") {
                    TextField("Translation", text: $draft.english, axis: .vertical)
                }
                Section {
                    TextField("Answer in German", text: $responseText, axis: .vertical)
                        .autocorrectionDisabled()
                } header: {
                    Text("Answer")
                } footer: {
                    Text("For questions: enables the “Question from answer” exercise.")
                }
                Section("Note") {
                    TextField("Literal meaning or explanation", text: $noteText, axis: .vertical)
                }
                Section("Category") {
                    HStack {
                        TextField("Category", text: $draft.category)
                        if !categories.isEmpty {
                            Menu {
                                ForEach(categories, id: \.self) { category in
                                    Button(category) { draft.category = category }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                        }
                    }
                }
                Section("Other") {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(PhraseKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Emoji", text: $draft.emoji)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        var entry = draft
        entry.german = draft.german.trimmed
        entry.english = draft.english.trimmed
        let key = PhraseChecker.key(entry.german)
        var seen: Set<String> = [key]
        entry.variants = variantsText.split(separator: "\n").map { String($0).trimmed }
            .filter { !$0.isEmpty && seen.insert(PhraseChecker.key($0)).inserted }
        entry.response = responseText.trimmed.isEmpty ? nil : responseText.trimmed
        entry.note = noteText.trimmed.isEmpty ? nil : noteText.trimmed
        let category = entry.category.trimmed
        entry.category = category.isEmpty ? PhraseEntry.defaultCategory : category
        entry.emoji = entry.emoji.trimmed.first.map(String.init) ?? "💬"
        onSave(entry)
        dismiss()
    }
}
