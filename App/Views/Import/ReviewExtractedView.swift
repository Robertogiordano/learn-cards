import LearnCore
import SwiftData
import SwiftUI

struct ReviewItem: Identifiable {
    var entry: VocabEntry
    var isSelected: Bool

    var id: UUID { entry.id }
}

/// Lets the learner fix the model's output before it reaches the vocabulary.
struct ReviewExtractedView: View {
    let onSaved: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingWords: [Word]
    @State private var items: [ReviewItem]
    @State private var editing: ReviewItem?
    @State private var didMarkDuplicates = false

    init(entries: [VocabEntry], onSaved: @escaping (Int) -> Void) {
        self.onSaved = onSaved
        _items = State(initialValue: entries.map { ReviewItem(entry: $0, isSelected: true) })
    }

    private var existingByKey: [String: Word] {
        Dictionary(existingWords.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedCount: Int { items.filter(\.isSelected).count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($items) { $item in
                        row(for: $item, isDuplicate: existingByKey[item.entry.dedupeKey] != nil)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                } footer: {
                    Text("Tocca la matita per correggere una parola. Le parole già nel vocabolario sono deselezionate: se le selezioni, aggiornano quella esistente senza perdere i progressi.")
                }
            }
            .navigationTitle(items.count == 1 ? "1 parola trovata" : "\(items.count) parole trovate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva (\(selectedCount))", action: save)
                        .disabled(selectedCount == 0)
                }
            }
            .sheet(item: $editing) { item in
                WordEditView(title: "Modifica", entry: item.entry) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].entry = updated
                    }
                }
            }
            .onAppear(perform: deselectDuplicates)
        }
    }

    private func row(for item: Binding<ReviewItem>, isDuplicate: Bool) -> some View {
        let entry = item.wrappedValue.entry
        return HStack(spacing: 12) {
            Button {
                item.wrappedValue.isSelected.toggle()
            } label: {
                Image(systemName: item.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
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
                if isDuplicate {
                    Text("Già nel vocabolario")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            Button {
                editing = item.wrappedValue
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
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
            if let word = existing[item.entry.dedupeKey] {
                word.update(from: item.entry)
            } else {
                context.insert(Word(entry: item.entry))
            }
            count += 1
        }
        try? context.save()
        onSaved(count)
        dismiss()
    }
}
