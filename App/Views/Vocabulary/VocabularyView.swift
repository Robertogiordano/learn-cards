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

/// The Vocabolario tab: words or phrases.
struct VocabularyView: View {
    @AppStorage(SettingsKey.vocabularyKind) private var kindRaw = ImportKind.words.rawValue

    var body: some View {
        NavigationStack {
            Group {
                switch ImportKind(rawValue: kindRaw) ?? .words {
                case .words: WordsListView()
                case .phrases: PhrasesListView()
                case .verbs: VerbsListView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mostra", selection: $kindRaw) {
                        ForEach(ImportKind.allCases) { kind in
                            Text(kind.title).tag(kind.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            }
        }
    }
}

struct WordsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Word.createdAt, order: .reverse) private var words: [Word]
    @State private var search = ""
    @State private var sort = VocabularySort.recent
    @State private var editing: Word?
    @State private var isAdding = false
    @State private var themeFilter: String?

    private var visibleWords: [Word] {
        let query = search.trimmed.lowercased()
        let themed = themeFilter.map { theme in words.filter { $0.category == theme } } ?? words
        let filtered = query.isEmpty ? themed : themed.filter { word in
            word.german.lowercased().contains(query)
                || word.category.lowercased().contains(query)
                || word.english.contains { $0.lowercased().contains(query) }
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

    private var dueCount: Int { words.filter(\.isDueAnywhere).count }

    /// Visible words grouped by theme, in the order of `Array<Word>.categories`.
    private var sections: [ThemeSection] {
        let visible = visibleWords
        let grouped = Dictionary(grouping: visible, by: { $0.category })
        return visible.categories.map { ThemeSection(theme: $0, words: grouped[$0] ?? []) }
    }

    var body: some View {
        Group {
            List {
                if !words.isEmpty {
                    Text("\(words.count) parole in \(words.categories.count) temi · \(dueCount) da ripassare")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(sections) { section in
                    Section {
                        ForEach(section.words) { word in
                            Button { editing = word } label: { WordRow(word: word) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in delete(offsets.map { section.words[$0] }) }
                    } header: {
                        Text("\(section.theme) · \(section.words.count)")
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
                        Picker("Tema", selection: $themeFilter) {
                            Text("Tutti i temi").tag(String?.none)
                            ForEach(words.categories, id: \.self) { theme in
                                Text(theme).tag(String?.some(theme))
                            }
                        }
                    } label: {
                        Label("Ordina e filtra", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: { Label("Aggiungi", systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { word in
                WordEditView(title: "Modifica", entry: word.entry, themes: words.categories) { updated in
                    word.update(from: updated)
                    try? context.save()
                }
            }
            .sheet(isPresented: $isAdding) {
                WordEditView(title: "Nuova parola", entry: VocabEntry(german: "", english: []), themes: words.categories) { entry in
                    context.insert(Word(entry: entry))
                    try? context.save()
                }
            }
        }
    }

    private func delete(_ targets: [Word]) {
        for word in targets {
            context.delete(word)
        }
        try? context.save()
    }
}

struct ThemeSection: Identifiable {
    let theme: String
    let words: [Word]

    var id: String { theme }
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
            if word.isDueAnywhere {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Da ripassare")
            }
        }
        .contentShape(Rectangle())
    }
}
