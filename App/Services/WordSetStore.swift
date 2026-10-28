import Foundation
import LearnCore

/// Random word sets, kept in UserDefaults and included in backups.
@MainActor
final class WordSetStore: ObservableObject {
    static let shared = WordSetStore()

    private static let key = "wordSets"

    @Published private(set) var sets: [WordSet]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([WordSet].self, from: data) {
            sets = stored
        } else {
            sets = []
        }
    }

    /// `name` falls back to the next "Set N" when nil or empty.
    @discardableResult
    func create(name: String? = nil, wordIDs: [UUID]) -> WordSet {
        let given = name?.trimmed ?? ""
        let set = WordSet(name: given.isEmpty ? WordSetPicker.nextName(existing: sets.map(\.name)) : given,
                          wordIDs: wordIDs)
        sets.append(set)
        save()
        return set
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = sets.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        sets[index].name = name
        save()
    }

    func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
        save()
    }

    /// From a backup.
    func replace(with sets: [WordSet]) {
        self.sets = sets
        save()
    }

    func merge(_ incoming: [WordSet]) {
        replace(with: WordSetMerger.merge(existing: sets, incoming: incoming))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
