import LearnCore
import SwiftData
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
    /// Parts of a compound noun, in order.
    @State private var parts: [String]
    @State private var partInput = ""
    @State private var isSuggesting = false
    @State private var suggestMessage: String?
    @Query private var vocabulary: [Word]
    @AppStorage(SettingsKey.model) private var model = OpenRouterModels.defaultModel

    init(title: String, entry: VocabEntry, themes: [String] = [], onSave: @escaping (VocabEntry) -> Void) {
        self.title = title
        self.themes = themes
        self.onSave = onSave
        _draft = State(initialValue: entry)
        _englishText = State(initialValue: entry.english.joined(separator: " / "))
        _pluralText = State(initialValue: entry.plural ?? "")
        _parts = State(initialValue: entry.parts)
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
                    partsSection
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

    // MARK: - Parts

    /// Words of the vocabulary matching what is being typed, those starting with it first.
    private var suggestions: [Word] {
        let query = partInput.trimmed
        guard !query.isEmpty else { return [] }
        let chosen = Set(parts.map(PhraseChecker.key))
        let prefix = PhraseChecker.key(query)
        let matches = vocabulary.filter { word in
            word.id != draft.id && !chosen.contains(PhraseChecker.key(word.german))
                && VocabularySearch.matches(query, in: [word.german])
        }
        return Array(matches.sorted { lhs, rhs in
            let lhsStarts = PhraseChecker.key(lhs.german).hasPrefix(prefix)
            let rhsStarts = PhraseChecker.key(rhs.german).hasPrefix(prefix)
            if lhsStarts != rhsStarts { return lhsStarts }
            return lhs.german.count < rhs.german.count
        }.prefix(6))
    }

    private var partsSection: some View {
        Section {
            if !parts.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        Button {
                            parts.remove(at: index)
                        } label: {
                            HStack(spacing: 4) {
                                Text(part)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.compounds.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(part)")
                    }
                }
                .padding(.vertical, 4)
            }
            TextField(parts.isEmpty ? "Add a part, e.g. Küche" : "Add another part", text: $partInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(addTypedPart)
            ForEach(suggestions) { word in
                Button {
                    addPart(word.german)
                } label: {
                    HStack(spacing: 10) {
                        Text(word.emoji)
                        Text(word.entry.withArticle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                }
                .buttonStyle(.borderless)
            }
            Button(action: suggestParts) {
                HStack {
                    Label("Suggest parts", systemImage: "wand.and.stars")
                    if isSuggesting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(draft.german.trimmed.isEmpty || isSuggesting)
            if let suggestMessage {
                Text(suggestMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Parts")
        } footer: {
            Text("For a compound noun, the words it is made of, in order (Küche + Tür). Pick them from your words as you type, or let “Suggest parts” find them. With two or more parts it plays in Compound words.")
        }
    }

    private func addTypedPart() {
        let text = partInput.trimmed
        guard !text.isEmpty else { return }
        // A typed word that is in the vocabulary takes its spelling.
        let match = vocabulary.first { PhraseChecker.key($0.german) == PhraseChecker.key(text) }
        addPart(match?.german ?? text)
    }

    private func addPart(_ part: String) {
        parts.append(part)
        partInput = ""
        suggestMessage = nil
    }

    /// From the vocabulary first; the model only when no split is found there.
    private func suggestParts() {
        let word = draft.german.trimmed
        let known = vocabulary.filter { $0.id != draft.id }.map(\.german)
        if let local = CompoundSplitter.suggest(word, vocabulary: known) {
            parts = local
            partInput = ""
            suggestMessage = nil
            return
        }
        guard let key = Secrets.openRouterKey else {
            suggestMessage = "No split found among your words. Add an OpenRouter API key in Settings to ask the model."
            return
        }
        let modelID = model.trimmed.isEmpty ? OpenRouterModels.defaultModel : model.trimmed
        isSuggesting = true
        suggestMessage = nil
        Task { @MainActor in
            defer { isSuggesting = false }
            do {
                let found = try await OpenRouterClient(apiKey: key, model: modelID).splitCompound(word)
                guard !found.isEmpty else {
                    suggestMessage = "\(word) does not look like a compound."
                    return
                }
                // Parts already in the vocabulary keep its spelling.
                parts = found.map { part in
                    vocabulary.first { PhraseChecker.key($0.german) == PhraseChecker.key(part) }?.german ?? part
                }
                partInput = ""
            } catch {
                suggestMessage = error.localizedDescription
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
        var parts = self.parts
        if !partInput.trimmed.isEmpty { parts.append(partInput.trimmed) }
        entry.parts = entry.article != nil && parts.count >= 2 ? parts : []
        let category = entry.category.trimmed
        entry.category = category.isEmpty
            ? (entry.isCompound ? VocabEntry.compoundCategory : VocabEntry.defaultCategory)
            : category
        onSave(entry)
        dismiss()
    }
}
