import LearnCore
import SwiftData
import SwiftUI

struct ReviewItem: Identifiable {
    var entry: VocabEntry
    var isSelected: Bool
    /// Goes in the word set made from this batch, when there is one.
    var inSet = true

    var id: UUID { entry.id }
}

/// Lets the learner fix the model's output before it reaches the vocabulary.
struct ReviewExtractedView: View {
    /// Words saved and the word set created, if any.
    let onSaved: (Int, WordSet?) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingWords: [Word]
    @State private var items: [ReviewItem]
    @State private var editing: ReviewItem?
    @State private var didMarkDuplicates = false
    @State private var isNamingTheme = false
    @State private var newTheme = ""
    @AppStorage(SettingsKey.reviewCreatesSet) private var createsSet = false
    @State private var setName = WordSetPicker.nextName(existing: WordSetStore.shared.sets.map(\.name))

    init(entries: [VocabEntry], onSaved: @escaping (Int, WordSet?) -> Void) {
        self.onSaved = onSaved
        _items = State(initialValue: entries.map { ReviewItem(entry: $0, isSelected: true) })
    }

    private var existingByKey: [String: Word] {
        Dictionary(existingWords.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    /// German words the parts of a compound can link to: the vocabulary plus the selected words of this batch.
    private var linkableKeys: Set<String> {
        Set(existingWords.map { PhraseChecker.key($0.german) }
            + items.filter(\.isSelected).map { PhraseChecker.key($0.entry.german) })
    }

    /// Ids of the words the set will hold: existing words for duplicates, the new word
    /// for selected ones; new words left unselected are not saved, so they stay out.
    private var setWordIDs: [UUID] {
        guard createsSet else { return [] }
        let existing = existingByKey
        var seen = Set<UUID>()
        return items.compactMap { item -> UUID? in
            guard item.inSet else { return nil }
            if let word = existing[item.entry.dedupeKey] { return word.id }
            return item.isSelected ? item.entry.id : nil
        }
        .filter { seen.insert($0).inserted }
    }

    /// Themes of this batch, in order of first appearance.
    private var batchThemes: [String] {
        var seen = Set<String>()
        return items.map(\.entry.category).filter { seen.insert($0).inserted }
    }

    /// Everything offered when changing a theme: the vocabulary's themes plus the new ones.
    private var allThemes: [String] {
        let existing = existingWords.categories
        return existing + batchThemes.filter { !existing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Also create a word set", isOn: $createsSet)
                    if createsSet {
                        TextField("Set name", text: $setName)
                    }
                } footer: {
                    if createsSet {
                        Text("Every word goes in the set (\(setWordIDs.count) now); tap the stack icon to leave one out. Words already in your vocabulary join with their progress; new words you deselect are not saved, so they stay out.")
                    }
                }

                ForEach(batchThemes, id: \.self) { theme in
                    Section {
                        ForEach(items.filter { $0.entry.category == theme }) { item in
                            row(for: item, isDuplicate: existingByKey[item.entry.dedupeKey] != nil)
                        }
                        .onDelete { offsets in
                            let themed = items.filter { $0.entry.category == theme }
                            let ids = Set(offsets.map { themed[$0].id })
                            items.removeAll { ids.contains($0.id) }
                        }
                    } header: {
                        Text(existingWords.categories.contains(theme) ? theme : "\(theme) · new theme")
                    }
                }
                Section {
                    EmptyView()
                } footer: {
                    Text("Tap the pencil to fix a word. Words already in your vocabulary are deselected: if you select them, they update the existing word without losing progress. Compound words show their parts: linked when the part is in your vocabulary or selected here.")
                }
            }
            .navigationTitle(items.count == 1 ? "1 word found" : "\(items.count) words found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save (\(selectedCount))", action: save)
                        .disabled(selectedCount == 0 && setWordIDs.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        ForEach(allThemes, id: \.self) { theme in
                            Button(theme) { setThemeOfSelected(theme) }
                        }
                        Divider()
                        Button("New theme…") {
                            newTheme = ""
                            isNamingTheme = true
                        }
                    } label: {
                        Label("Change theme of selected", systemImage: "tag")
                    }
                    .disabled(selectedCount == 0)
                }
            }
            .alert("New theme", isPresented: $isNamingTheme) {
                TextField("Theme", text: $newTheme)
                Button("Cancel", role: .cancel) {}
                Button("Apply") { setThemeOfSelected(newTheme.trimmed) }
            } message: {
                Text("It will be given to the \(selectedCount) selected words.")
            }
            .sheet(item: $editing) { item in
                WordEditView(title: "Edit", entry: item.entry, themes: allThemes) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].entry = updated
                    }
                }
            }
            .onAppear(perform: deselectDuplicates)
        }
    }

    private func row(for item: ReviewItem, isDuplicate: Bool) -> some View {
        let entry = item.entry
        return HStack(spacing: 12) {
            Button {
                toggle(item.id)
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)

            Text(entry.emoji)
                .font(.largeTitle)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.fullGerman)
                    .font(.headline)
                Text(entry.englishDisplay)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.isCompound {
                    let known = linkableKeys
                    HStack(spacing: 4) {
                        ForEach(Array(entry.parts.enumerated()), id: \.offset) { index, part in
                            if index > 0 { Text("+").foregroundStyle(.secondary) }
                            let isKnown = known.contains(PhraseChecker.key(part))
                            Label(part, systemImage: isKnown ? "link" : "exclamationmark.circle")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(isKnown ? Color.compounds : Color.orange)
                        }
                    }
                    .font(.caption)
                    .accessibilityLabel("Parts: \(entry.partsDisplay)")
                }
                if isDuplicate {
                    Text("Already in your vocabulary")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            if createsSet {
                // A new word that will not be saved cannot be in the set.
                let canJoin = isDuplicate || item.isSelected
                Button {
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].inSet.toggle()
                    }
                } label: {
                    Image(systemName: item.inSet ? "square.stack.fill" : "square.stack")
                        .foregroundStyle(Color.accentColor)
                        .opacity(canJoin ? 1 : 0.3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(item.inSet ? "In the word set" : "Not in the word set")
            }

            Button {
                editing = item
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggle(_ id: UUID) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isSelected.toggle()
        }
    }

    private func setThemeOfSelected(_ theme: String) {
        guard !theme.isEmpty else { return }
        for index in items.indices where items[index].isSelected {
            items[index].entry.category = theme
        }
    }

    private func deselectDuplicates() {
        guard !didMarkDuplicates else { return }
        didMarkDuplicates = true
        let existing = existingByKey
        for index in items.indices where existing[items[index].entry.dedupeKey] != nil {
            items[index].isSelected = false
        }
    }

    private func save() {
        let existing = existingByKey
        let memberIDs = setWordIDs
        var count = 0
        for item in items where item.isSelected {
            if let word = existing[item.entry.dedupeKey] {
                word.update(from: item.entry)
            } else {
                context.insert(Word(entry: item.entry))
            }
            count += 1
        }
        try? context.save()
        let set = memberIDs.isEmpty ? nil : WordSetStore.shared.create(name: setName, wordIDs: memberIDs)
        onSaved(count, set)
        dismiss()
    }
}
