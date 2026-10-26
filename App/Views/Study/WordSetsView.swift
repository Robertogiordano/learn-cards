import LearnCore
import SwiftData
import SwiftUI

/// Row of the word sets on the path.
struct WordSetsRow: View {
    @ObservedObject private var store = WordSetStore.shared

    var body: some View {
        HStack(spacing: 12) {
            Text("🎲")
                .font(.title)
            VStack(alignment: .leading, spacing: 2) {
                Text("Word sets")
                    .font(.headline)
                Text(store.sets.isEmpty
                     ? "Train a fixed group of random words"
                     : store.sets.count == 1 ? "1 set" : "\(store.sets.count) sets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Random sets of words that stay the same once created, each trained like a theme.
struct WordSetsView: View {
    @Query private var words: [Word]
    @ObservedObject private var store = WordSetStore.shared
    @State private var isChoosingSize = false
    @State private var renaming: WordSet?
    @State private var newName = ""

    var body: some View {
        let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return List {
            Section {
                Button {
                    isChoosingSize = true
                } label: {
                    Label("New random set", systemImage: "dice")
                        .font(.headline)
                }
                .disabled(words.isEmpty)
            } footer: {
                Text("A new set picks words at random from your whole vocabulary, favouring new and weak ones. Then it stays the same, so you can train it like a theme until every star lights up.")
            }

            if store.sets.isEmpty {
                ContentUnavailableView(
                    "No sets yet",
                    systemImage: "dice",
                    description: Text(words.isEmpty
                                      ? "Add some words first from the Add tab."
                                      : "Tap “New random set” to create your first one.")
                )
            } else {
                Section("Your sets") {
                    ForEach(store.sets.reversed()) { set in
                        let setWords = set.wordIDs.compactMap { byID[$0] }
                        NavigationLink {
                            ThemeDetailView(set: set)
                        } label: {
                            row(set, words: setWords)
                        }
                        .disabled(setWords.isEmpty)
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
                    }
                }
            }
        }
        .navigationTitle("Word sets")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("How many words?", isPresented: $isChoosingSize, titleVisibility: .visible) {
            ForEach(WordSetPicker.sizes, id: \.self) { size in
                Button(size == WordSetPicker.defaultSize ? "\(size) words (default)" : "\(size) words") {
                    store.create(wordIDs: WordSetPicker.pick(words.map(\.pathWord), count: size))
                }
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

    @ViewBuilder
    private func row(_ set: WordSet, words: [Word]) -> some View {
        // Words of every theme, counted as one group named after the set.
        let progress = PathPlanner.themeProgress(words.map { word in
            var pathWord = word.pathWord
            pathWord.category = set.name
            return pathWord
        }).first
        if let progress {
            ThemeRow(progress: progress, emoji: "🎲")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(set.name)
                    .font(.headline)
                Text("No words left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
