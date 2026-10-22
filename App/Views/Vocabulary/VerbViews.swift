import LearnCore
import SwiftData
import SwiftUI

/// The six forms side by side: "ich fahre · du fährst …".
struct ConjugationGrid: View {
    let verb: VerbEntry
    var highlight: Person?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
            ForEach([0, 3], id: \.self) { offset in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        if let person = Person(rawValue: offset + column) {
                            cell(person)
                        }
                    }
                }
            }
        }
        .font(.footnote)
    }

    private func cell(_ person: Person) -> some View {
        HStack(spacing: 3) {
            Text(person.pronoun)
                .foregroundStyle(.secondary)
            Text(verb.form(for: person))
                .fontWeight(person == highlight ? .bold : .regular)
        }
    }
}

/// Infinitive, translation and the table.
struct VerbSummary: View {
    let verb: VerbEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(verb.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(verb.infinitive)
                        .font(.headline)
                    Text(verb.english)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ConjugationGrid(verb: verb)
                if let note = verb.note {
                    Text(note)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Edits a verb and its six forms.
struct VerbEditView: View {
    let title: String
    let onSave: (VerbEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: VerbEntry
    @State private var noteText: String

    init(title: String, entry: VerbEntry, onSave: @escaping (VerbEntry) -> Void) {
        self.title = title
        self.onSave = onSave
        var entry = entry
        while entry.forms.count < Person.allCases.count { entry.forms.append("") }
        _draft = State(initialValue: entry)
        _noteText = State(initialValue: entry.note ?? "")
    }

    private var isValid: Bool {
        !draft.infinitive.trimmed.isEmpty && !draft.english.trimmed.isEmpty
            && draft.forms.allSatisfy { !$0.trimmed.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Verbo") {
                    TextField("Infinito, es. fahren", text: $draft.infinitive)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Inglese", text: $draft.english)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    ForEach(Person.allCases, id: \.self) { person in
                        HStack {
                            Text(person.label)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            TextField(person.label, text: $draft.forms[person.rawValue])
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                } header: {
                    Text("Presente")
                } footer: {
                    Text("Separabili con il prefisso in fondo («stehe auf»), riflessivi con il pronome («wasche mich»).")
                }
                Section("Altro") {
                    Picker("Gruppo", selection: $draft.group) {
                        ForEach(VerbGroup.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Nota", text: $noteText, axis: .vertical)
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
        entry.infinitive = draft.infinitive.trimmed
        entry.english = draft.english.trimmed
        entry.forms = draft.forms.map(\.trimmed)
        entry.note = noteText.trimmed.isEmpty ? nil : noteText.trimmed
        entry.emoji = entry.emoji.trimmed.first.map(String.init) ?? "🏃"
        onSave(entry)
        dismiss()
    }
}

/// Checks the extracted verbs and their tables before saving.
struct ReviewVerbsView: View {
    /// Verbs on the photo that were already saved and were not conjugated again.
    let skipped: [String]
    let onSaved: (Int) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existingVerbs: [Verb]
    @State private var items: [ReviewVerbItem]
    @State private var editing: ReviewVerbItem?
    @State private var didMarkDuplicates = false

    init(verbs: [VerbEntry], skipped: [String] = [], onSaved: @escaping (Int) -> Void) {
        self.skipped = skipped
        self.onSaved = onSaved
        _items = State(initialValue: verbs.map { ReviewVerbItem(entry: $0, isSelected: true) })
    }

    private var existingByKey: [String: Verb] {
        Dictionary(existingVerbs.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var selectedCount: Int { items.filter { $0.isSelected }.count }

    var body: some View {
        NavigationStack {
            List {
                if !skipped.isEmpty {
                    Section {
                        Label("\(skipped.count) già nel vocabolario, non riconiugati: \(skipped.joined(separator: ", "))",
                              systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(items) { item in
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

                        VStack(alignment: .leading, spacing: 4) {
                            VerbSummary(verb: item.entry)
                            HStack(spacing: 6) {
                                Text(item.entry.group.label)
                                if existingByKey[item.entry.dedupeKey] != nil {
                                    Text("· già salvato").foregroundStyle(.orange)
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Button {
                            editing = item
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { items.remove(atOffsets: $0) }
            }
            .navigationTitle(items.count == 1 ? "1 verbo trovato" : "\(items.count) verbi trovati")
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
                VerbEditView(title: "Modifica verbo", entry: item.entry) { updated in
                    if let index = items.firstIndex(where: { $0.id == item.id }) {
                        items[index].entry = updated
                    }
                }
            }
            .onAppear(perform: deselectDuplicates)
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
            if let verb = existing[item.entry.dedupeKey] {
                verb.update(from: item.entry)
            } else {
                context.insert(Verb(entry: item.entry))
            }
            count += 1
        }
        try? context.save()
        onSaved(count)
        dismiss()
    }
}

struct ReviewVerbItem: Identifiable {
    var entry: VerbEntry
    var isSelected: Bool

    var id: UUID { entry.id }
}

/// Saved verbs grouped by group: search, edit, delete, add by hand.
struct VerbsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Verb.infinitive) private var verbs: [Verb]
    @State private var search = ""
    @State private var editing: Verb?
    @State private var isAdding = false

    private var visible: [Verb] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return verbs }
        return verbs.filter { verb in
            verb.infinitive.lowercased().contains(query) || verb.english.lowercased().contains(query)
                || verb.forms.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        let visible = self.visible
        return List {
            if !verbs.isEmpty {
                Text(verbs.count == 1 ? "1 verbo" : "\(verbs.count) verbi")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(visible.groups, id: \.self) { group in
                let items = visible.filter { $0.group == group }
                Section {
                    ForEach(items) { verb in
                        Button { editing = verb } label: {
                            VerbSummary(verb: verb.entry)
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
                    Text("\(group.label) · \(items.count)")
                }
            }
        }
        .overlay {
            if verbs.isEmpty {
                ContentUnavailableView(
                    "Nessun verbo",
                    systemImage: "text.word.spacing",
                    description: Text("Nella scheda Aggiungi scegli «Verbi» e fotografa una pagina, oppure aggiungine uno con +.")
                )
            }
        }
        .searchable(text: $search, prompt: "Cerca nei verbi")
        .navigationTitle("Verbi")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isAdding = true } label: { Label("Aggiungi", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { verb in
            VerbEditView(title: "Modifica verbo", entry: verb.entry) { updated in
                verb.update(from: updated)
                try? context.save()
            }
        }
        .sheet(isPresented: $isAdding) {
            VerbEditView(title: "Nuovo verbo", entry: VerbEntry(infinitive: "", english: "", forms: [])) { entry in
                if let existing = verbs.first(where: { $0.dedupeKey == entry.dedupeKey }) {
                    existing.update(from: entry)
                } else {
                    context.insert(Verb(entry: entry))
                }
                try? context.save()
            }
        }
    }
}
