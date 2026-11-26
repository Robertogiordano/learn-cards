import Foundation
import LearnCore

/// Verb sets, random or hand-picked, kept in UserDefaults and included in backups.
@MainActor
final class VerbSetStore: ObservableObject {
    static let shared = VerbSetStore()

    private static let key = "verbSets"

    @Published private(set) var sets: [VerbSet]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode([VerbSet].self, from: data) {
            sets = stored
        } else {
            sets = []
        }
    }

    var nextName: String { VerbSetPicker.nextName(existing: sets.map(\.name)) }

    func set(_ id: UUID) -> VerbSet? { sets.first { $0.id == id } }

    /// `name` falls back to the next "Verb set N" when nil or empty.
    @discardableResult
    func create(name: String? = nil, verbIDs: [UUID]) -> VerbSet {
        let given = name?.trimmed ?? ""
        let set = VerbSet(name: given.isEmpty ? nextName : given, verbIDs: verbIDs)
        sets.append(set)
        save()
        return set
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = sets.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        sets[index].name = name
        save()
    }

    func setVerbs(_ id: UUID, to verbIDs: [UUID]) {
        guard let index = sets.firstIndex(where: { $0.id == id }) else { return }
        sets[index].verbIDs = verbIDs
        save()
    }

    func delete(_ id: UUID) {
        sets.removeAll { $0.id == id }
        save()
    }

    /// From a backup.
    func replace(with sets: [VerbSet]) {
        self.sets = sets
        save()
    }

    func merge(_ incoming: [VerbSet]) {
        replace(with: VerbSetMerger.merge(existing: sets, incoming: incoming))
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
