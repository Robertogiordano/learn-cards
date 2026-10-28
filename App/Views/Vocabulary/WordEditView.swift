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
    @State private var partsText: String

    init(title: String, entry: VocabEntry, themes: [String] = [], onSave: @escaping (VocabEntry) -> Void) {
        self.title = title
        self.themes = themes
        self.onSave = onSave
        _draft = State(initialValue: entry)
        _englishText = State(initialValue: entry.english.joined(separator: " / "))
        _pluralText = State(initialValue: entry.plural ?? "")
        _partsText = State(initialValue: entry.parts.joined(separator: " + "))
    }

    private var englishList: [String] {
        englishText.split(separator: "/").map { String($0).trimmed }.filter { !$0.isEmpty }
    }

    private var isValid: Bool { !draft.german.trimmed.isEmpty && !englishList.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("German") {
                    TextField("Word, without article", text: $draft.german)
                        .autocorrectionDisabled()
                    Picker("Article", selection: $draft.article) {
                        Text("—").tag(Article?.none)
                        ForEach(Article.allCases, id: \.self) { article in
                            Text(article.rawValue).tag(Article?.some(article))
                        }
                    }
                    .pickerStyle(.segmented)
                    if draft.article != nil {
                        TextField("Plural, without article", text: $pluralText)
                            .autocorrectionDisabled()
                    }
                }
                if draft.article != nil {
                    Section {
                        TextField("Küche + Tür", text: $partsText)
                            .autocorrectionDisabled()
                    } header: {
                        Text("Parts")
                    } footer: {
                        Text("For a compound noun, the words it is made of, joined with +. It then plays in Compound words.")
                    }
                }
                Section {
                    TextField("table / desk", text: $englishText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("English")
                } footer: {
                    Text("Separate several translations with /")
                }
                Section("Theme") {
                    HStack {
                        TextField("Theme", text: $draft.category)
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
                Section("Other") {
                    Picker("Type", selection: $draft.partOfSpeech) {
                        ForEach(PartOfSpeech.allCases, id: \.self) { Text($0.label).tag($0) }
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
        entry.english = englishList
        let plural = pluralText.trimmed
        entry.plural = entry.article == nil || plural.isEmpty ? nil : plural
        if entry.article != nil { entry.partOfSpeech = .noun }
        entry.emoji = entry.emoji.trimmed.first.map(String.init) ?? "📝"
        let parts = partsText.split(separator: "+").map { String($0).trimmed }.filter { !$0.isEmpty }
        entry.parts = entry.article != nil && parts.count >= 2 ? parts : []
        let category = entry.category.trimmed
        entry.category = category.isEmpty
            ? (entry.isCompound ? VocabEntry.compoundCategory : VocabEntry.defaultCategory)
            : category
        onSave(entry)
        dismiss()
    }
}
