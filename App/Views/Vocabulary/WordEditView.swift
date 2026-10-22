import LearnCore
import SwiftUI

/// Edits a vocabulary entry; used for manual words, existing words and extracted words under review.
struct WordEditView: View {
    let title: String
    /// Existing themes offered as shortcuts.
    let themes: [String]
    let onSave: (VocabEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VocabEntry
    @State private var englishText: String
    @State private var pluralText: String

    init(title: String, entry: VocabEntry, themes: [String] = [], onSave: @escaping (VocabEntry) -> Void) {
        self.title = title
        self.themes = themes
        self.onSave = onSave
        _draft = State(initialValue: entry)
        _englishText = State(initialValue: entry.english.joined(separator: " / "))
        _pluralText = State(initialValue: entry.plural ?? "")
    }

    private var englishList: [String] {
        englishText.split(separator: "/").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private var isValid: Bool { !draft.german.trimmed.isEmpty && !englishList.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tedesco") {
                    TextField("Parola, senza articolo", text: $draft.german)
                        .autocorrectionDisabled()
                    Picker("Articolo", selection: $draft.article) {
                        Text("—").tag(Article?.none)
                        ForEach(Article.allCases, id: \.self) { article in
                            Text(article.rawValue).tag(Article?.some(article))
                        }
                    }
                    .pickerStyle(.segmented)
                    if draft.article != nil {
                        TextField("Plurale, senza articolo", text: $pluralText)
                            .autocorrectionDisabled()
                    }
                }
                Section {
                    TextField("table / desk", text: $englishText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Inglese")
                } footer: {
                    Text("Separa più traduzioni con /")
                }
                Section("Tema") {
                    HStack {
                        TextField("Tema", text: $draft.category)
                        if !themes.isEmpty {
                            Menu {
                                ForEach(themes, id: \.self) { theme in
                                    Button(theme) { draft.category = theme }
                                }
                            } label: {
                                Image(systemName: "list.bullet")
                            }
                        }
                    }
                }
                Section("Altro") {
                    Picker("Tipo", selection: $draft.partOfSpeech) {
                        ForEach(PartOfSpeech.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Emoji", text: $draft.emoji)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva", action: save)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        var entry = draft
        entry.german = draft.german.trimmed
        entry.english = englishList
        let plural = pluralText.trimmed
        entry.plural = entry.article == nil || plural.isEmpty ? nil : plural
        if entry.article != nil { entry.partOfSpeech = .noun }
        entry.emoji = entry.emoji.trimmed.first.map(String.init) ?? "📝"
        let category = entry.category.trimmed
        entry.category = category.isEmpty ? VocabEntry.defaultCategory : category
        onSave(entry)
        dismiss()
    }
}
