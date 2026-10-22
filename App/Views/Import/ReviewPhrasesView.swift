import LearnCore
import SwiftData
import SwiftUI

struct ReviewPhraseItem: Identifiable {
    var entry: PhraseEntry
    var isSelected: Bool

    var id: UUID { entry.id }
}

/// Lets the learner check the extracted phrases (and the solved gaps) before saving them.
struct ReviewPhrasesView: View {
    let onSaved: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingPhrases: [Phrase]
    @State private var items: [ReviewPhraseItem]
    @State private var editing: ReviewPhraseItem?
    @State private var didMarkDuplicates = false
    @State private var isNamingCategory = false
    @State private var newCategory = ""

    init(phrases: [PhraseEntry], onSaved: @escaping (Int) -> Void) {
        self.onSaved = onSaved
        _items = State(initialValue: phrases.map { ReviewPhraseItem(entry: $0, isSelected: true) })
    }

    private var existingByKey: [String: Phrase] {
        Dictionary(existingPhrases.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    private var batchCategories: [String] {
        var seen = Set<String>()
        return items.map(\.entry.category).filter { seen.insert($0).inserted }
    }

    private var allCategories: [String] {
        let existing = existingPhrases.categories
        return existing + batchCategories.filter { !existing.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(batchCategories, id: \.self) { category in
                    Section {
                        ForEach(items.filter { $0.entry.category == category }) { item in
                            row(for: item, isDuplicate: existingByKey[item.entry.dedupeKey] != nil)
                        }
                        .onDelete { offsets in
                            let inCategory = items.filter { $0.entry.category == category }
                            let ids = Set(offsets.map { inCategory[$0].id })
                            items.removeAll { ids.contains($0.id) }
                        }
                    } header: {
                        Text(existingPhrases.categories.contains(category) ? category : "\(category) · nuova categoria")
                    }
                }
            }
            .navigationTitle(items.count == 1 ? "1 frase trovata" : "\(items.count) frasi trovate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva (\(selectedCount))", action: save)
                        .disabled(selectedCount == 0)
                }
                ToolbarItem(placement: .bottomBar) {
                    Menu {
                        ForEach(allCategories, id: \.self) { category in
                            Button(category) { setCategoryOfSelected(category) }
                        }
                        Divider()
                        Button("Nuova categoria…") {
                            newCategory = ""
                            isNamingCategory = true
                        }
                    } label: {
                        Label("Cambia categoria alle selezionate", systemImage: "tag")
                    }
                    .disabled(selectedCount == 0)
                }
            }
            .alert("Nuova categoria", isPresented: $isNamingCategory) {
                TextField("Categoria", text: $newCategory)
                Button("Annulla", role: .cancel) {}
                Button("Applica") { setCategoryOfSelected(newCategory.trimmed) }
            }
            .sheet(item: $editing) { item in
                PhraseEditView(title: "Modifica frase", entry: item.entry, categories: allCategories) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].entry = updated
                    }
                }
            }
            .onAppear(perform: deselectDuplicates)
        }
    }

    private func row(for item: ReviewPhraseItem, isDuplicate: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].isSelected.toggle()
                }
            } label: {
                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.borderless)

            PhraseSummary(entry: item.entry)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    editing = item
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                if isDuplicate {
                    Text("Già salvata")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func setCategoryOfSelected(_ category: String) {
        guard !category.isEmpty else { return }
        for index in items.indices where items[index].isSelected {
            items[index].entry.category = category
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
        var count = 0
        for item in items where item.isSelected {
            if let phrase = existing[item.entry.dedupeKey] {
                phrase.update(from: item.entry)
            } else {
                context.insert(Phrase(entry: item.entry))
            }
            count += 1
        }
        try? context.save()
        onSaved(count)
        dismiss()
    }
}

/// German, English and, for question/answer pairs, the answer.
struct PhraseSummary: View {
    let entry: PhraseEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(entry.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.german)
                    .font(.headline)
                Text(entry.english)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let response = entry.response {
                    Label(response, systemImage: "arrowshape.turn.up.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = entry.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
