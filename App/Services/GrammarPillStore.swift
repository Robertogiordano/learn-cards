import Foundation
import LearnCore

/// Grammar pills, kept as a JSON file in Application Support (lessons are too big for
/// UserDefaults) and included in backups.
@MainActor
final class GrammarPillStore: ObservableObject {
    static let shared = GrammarPillStore()

    @Published private(set) var pills: [GrammarPill]

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("grammarPills.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode([GrammarPill].self, from: data) {
            pills = stored
        } else {
            pills = []
        }
    }

    func pill(_ id: UUID) -> GrammarPill? {
        pills.first { $0.id == id }
    }

    func add(_ pill: GrammarPill) {
        pills.insert(pill, at: 0)
        save()
    }

    func update(_ id: UUID, _ change: (inout GrammarPill) -> Void) {
        guard let index = pills.firstIndex(where: { $0.id == id }) else { return }
        change(&pills[index])
        save()
    }

    func delete(_ id: UUID) {
        pills.removeAll { $0.id == id }
        save()
    }

    /// From a backup.
    func replace(with pills: [GrammarPill]) {
        self.pills = pills
        save()
    }

    /// Adds the pills not present yet; for the same pill keeps the one practised most recently.
    func merge(_ incoming: [GrammarPill]) {
        var merged = pills
        for pill in incoming {
            if let index = merged.firstIndex(where: { $0.id == pill.id }) {
                let mine = merged[index].lastPracticed ?? merged[index].createdAt
                let theirs = pill.lastPracticed ?? pill.createdAt
                if theirs > mine { merged[index] = pill }
            } else {
                merged.append(pill)
            }
        }
        replace(with: merged)
    }

    private func save() {
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(pills).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Could not save the grammar pills: \(error)")
        }
    }
}
