import LearnCore
import SwiftData
import SwiftUI

enum VocabularySort: String, CaseIterable, Identifiable {
    case recent, alphabetical, hardest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Più recenti"
        case .alphabetical: return "Alfabetico"
        case .hardest: return "Più sbagliate"
        }
    }
}

struct VocabularyView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @State private var search = ""
    @State private var sort = VocabularySort.recent
    @State private var editing: Word?
    @State private var isAdding = false

    private var visibleWords: [Word] {
        let query = search.trimmed.lowercased()
        let filtered = query.isEmpty ? words : words.filter { word in
            word.german.lowercased().contains(query) || word.english.contains { $0.lowercased().contains(query) }
        }
        switch sort {
        case .recent:
            return filtered
        case .alphabetical:
            return filtered.sorted { $0.german.localizedCaseInsensitiveCompare($1.german) == .orderedAscending }
        case .hardest:
            return filtered.sorted { ($0.lapses, $0.timesWrong) > ($1.lapses, $1.timesWrong) }
        }
    }

    private var dueCount: Int { words.filter(\.isDue).count }

    var body: some View {
        NavigationStack {
            List {
                if !words.isEmpty {
                    Section {
                        ForEach(visibleWords) { word in
                            Button { editing = word } label: { WordRow(word: word) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    } header: {
                        Text("\(words.count) parole · \(dueCount) da ripassare")
                    }
                }
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Nessuna parola",
                        systemImage: "books.vertical",
                        description: Text("Fotografa una pagina dalla scheda Aggiungi, oppure inserisci una parola a mano con +.")
                    )
                }
            }
            .searchable(text: $search, prompt: "Cerca in tedesco o inglese")
            .navigationTitle("Vocabolario")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Ordina", selection: $sort) {
                            ForEach(VocabularySort.allCases) { Text($0.title).tag($0) }
                        }
                    } label: {
                        Label("Ordina", systemImage: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Label("Aggiungi", systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { word in
                WordEditView(title: "Modifica", entry: word.entry) { updated in
                    word.update(from: updated)
                    try? context.save()
                }
            }
            .sheet(isPresented: $isAdding) {
                WordEditView(title: "Nuova parola", entry: VocabEntry(german: "", english: [])) { entry in
                    context.insert(Word(entry: entry))
                    try? context.save()
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let targets = offsets.map { visibleWords[$0] }
        for word in targets {
            context.delete(word)
        }
        try? context.save()
    }
}

struct WordRow: View {
    let word: Word

    var body: some View {
        HStack(spacing: 12) {
            Text(word.emoji)
                .font(.largeTitle)
            VStack(alignment: .leading, spacing: 2) {
                Text(word.entry.fullGerman)
                    .font(.headline)
                Text(word.english.joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if word.isDue {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Da ripassare")
            }
        }
        .contentShape(Rectangle())
    }
}
