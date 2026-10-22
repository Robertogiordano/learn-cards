import LearnCore
import SwiftData
import SwiftUI

/// Saved phrases grouped by category: search, edit, delete, add by hand.
struct PhrasesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Phrase.createdAt, order: .reverse) private var phrases: [Phrase]
    @State private var search = ""
    @State private var editing: Phrase?
    @State private var isAdding = false

    private var visible: [Phrase] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return phrases }
        return phrases.filter { phrase in
            [phrase.german, phrase.english, phrase.category, phrase.response ?? ""]
                .contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        let visible = self.visible
        let grouped = Dictionary(grouping: visible, by: { $0.category })

        return List {
            if !phrases.isEmpty {
                Text("\(phrases.count) frasi in \(phrases.categories.count) categorie")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(visible.categories, id: \.self) { category in
                let items = grouped[category] ?? []
                Section {
                    ForEach(items) { phrase in
                        Button { editing = phrase } label: {
                            PhraseSummary(entry: phrase.entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(items[index]) }
                        try? context.save()
                    }
                } header: {
                    Text("\(category) · \(items.count)")
                }
            }
        }
        .overlay {
            if phrases.isEmpty {
                ContentUnavailableView(
                    "Nessuna frase",
                    systemImage: "text.bubble",
                    description: Text("Nella scheda Aggiungi scegli «Frasi» e fotografa una pagina, oppure aggiungine una con +.")
                )
            }
        }
        .searchable(text: $search, prompt: "Cerca nelle frasi")
        .navigationTitle("Frasi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Label("Aggiungi", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { phrase in
            PhraseEditView(title: "Modifica frase", entry: phrase.entry, categories: phrases.categories) { updated in
                phrase.update(from: updated)
                try? context.save()
            }
        }
        .sheet(isPresented: $isAdding) {
            PhraseEditView(title: "Nuova frase", entry: PhraseEntry(german: "", english: ""),
                           categories: phrases.categories) { entry in
                if let existing = phrases.first(where: { $0.dedupeKey == entry.dedupeKey }) {
                    existing.update(from: entry)
                } else {
                    context.insert(Phrase(entry: entry))
                }
                try? context.save()
            }
        }
    }
}
