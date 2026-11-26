import LearnCore
import SwiftData
import SwiftUI

/// Row of the verb sets on the path.
struct VerbSetsRow: View {
    @ObservedObject private var store = VerbSetStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text("🧩")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Verb sets")
                    .font(.headline)
                Text(store.sets.isEmpty
                     ? "Train a fixed group of verbs, random or chosen"
                     : store.sets.count == 1 ? "1 set" : "\(store.sets.count) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Groups of verbs that stay the same once created, each trained like the verb section.
struct VerbSetsView: View {
    @Query private var verbs: [Verb]
    @ObservedObject private var store = VerbSetStore.shared
    @State private var isChoosingSize = false
    @State private var isPicking = false
    @State private var renaming: VerbSet?
    @State private var newName = ""

    var body: some View {
        let byID = Dictionary(verbs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return List {
            Section {
                Button {
                    isChoosingSize = true
                } label: {
                    Label("New random set", systemImage: "dice")
                        .font(.headline)
                }
                .disabled(verbs.isEmpty)
                Button {
                    isPicking = true
                } label: {
                    Label("Choose the verbs", systemImage: "checklist")
                        .font(.headline)
                }
                .disabled(verbs.isEmpty)
            } footer: {
                Text("A random set picks verbs from all of yours, favouring new and weak ones; or choose them yourself. Then the set stays the same, so you can train it until it reaches 100%. You can also create a set while importing verbs from a photo.")
            }

            if store.sets.isEmpty {
                ContentUnavailableView(
                    "No verb sets yet",
                    systemImage: "square.stack",
                    description: Text(verbs.isEmpty
                                      ? "Add some verbs first from the Add tab."
                                      : "Create a random set or choose the verbs yourself.")
                )
            } else {
                Section("Your sets") {
                    ForEach(store.sets.reversed()) { set in
                        let setVerbs = set.verbIDs.compactMap { byID[$0] }
                        NavigationLink {
                            VerbsView(setID: set.id)
                        } label: {
                            row(set, verbs: setVerbs)
                        }
                        .contextMenu {
                            Button {
                                newName = set.name
                                renaming = set
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                store.delete(set.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                store.delete(set.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                newName = set.name
                                renaming = set
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Verb sets")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("How many verbs?", isPresented: $isChoosingSize, titleVisibility: .visible) {
            ForEach(VerbSetPicker.sizes, id: \.self) { size in
                Button(size == VerbSetPicker.defaultSize ? "\(size) verbs (default)" : "\(size) verbs") {
                    store.create(verbIDs: VerbSetPicker.pick(verbs.map(\.setCandidate), count: size))
                }
            }
        }
        .sheet(isPresented: $isPicking) {
            VerbSetEditorView(title: "New verb set", name: store.nextName, selected: []) { name, ids in
                store.create(name: name, verbIDs: ids)
            }
        }
        .alert("Rename set", isPresented: Binding(isPresent: $renaming)) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let renaming { store.rename(renaming.id, to: newName.trimmed) }
            }
        }
    }

    private func row(_ set: VerbSet, verbs: [Verb]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.headline)
                Text(verbs.isEmpty ? "No verbs" : verbs.map(\.infinitive).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !verbs.isEmpty {
                ProgressRing(value: VerbExercises.mastery(verbs.map(\.kindStreaks)), color: .verbs)
                    .frame(width: 38, height: 38)
            }
        }
    }
}

/// Picks the verbs of a set by hand, grouped like the verb list; `name` nil hides the name field.
struct VerbSetEditorView: View {
    let title: String
    let onSave: (String, [UUID]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Verb.infinitive) private var verbs: [Verb]
    @State private var name: String
    @State private var selected: Set<UUID>
    @State private var search = ""
    private let showsName: Bool

    init(title: String, name: String?, selected: Set<UUID>, onSave: @escaping (String, [UUID]) -> Void) {
        self.title = title
        self.onSave = onSave
        showsName = name != nil
        _name = State(initialValue: name ?? "")
        _selected = State(initialValue: selected)
    }

    private var visible: [Verb] {
        let query = search.trimmed.lowercased()
        guard !query.isEmpty else { return verbs }
        return verbs.filter {
            $0.infinitive.lowercased().contains(query) || $0.english.lowercased().contains(query)
        }
    }

    var body: some View {
        let visible = self.visible
        NavigationStack {
            List {
                if showsName {
                    Section {
                        TextField("Set name", text: $name)
                    }
                }
                ForEach(visible.groups, id: \.self) { group in
                    let items = visible.filter { $0.section == group }
                    Section {
                        ForEach(items) { verb in
                            Button {
                                if !selected.insert(verb.id).inserted { selected.remove(verb.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(verb.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(Color.accentColor)
                                    Text(verb.emoji)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verb.infinitive)
                                            .font(.headline)
                                        Text(verb.english)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(group.label)
                            Spacer()
                            let ids = Set(items.map(\.id))
                            Button(ids.isSubset(of: selected) ? "None" : "All") {
                                if ids.isSubset(of: selected) {
                                    selected.subtract(ids)
                                } else {
                                    selected.formUnion(ids)
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search verbs")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save (\(selected.count))") {
                        // Keep the verbs in alphabetical order.
                        onSave(name.trimmed, verbs.map(\.id).filter(selected.contains))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
            }
        }
    }
}

extension Verb {
    var setCandidate: VerbSetCandidate {
        VerbSetCandidate(id: id, isNew: srs.isNew, kindStreaks: kindStreaks)
    }
}
