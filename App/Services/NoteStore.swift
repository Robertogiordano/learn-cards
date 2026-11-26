import Foundation
import LearnCore

/// The learner's own notes, kept as a JSON file in Application Support and included in backups.
@MainActor
final class NoteStore: ObservableObject {
    static let shared = NoteStore()

    /// Most recently edited first.
    @Published private(set) var notes: [StudyNote]

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("notes.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let stored = try? JSONDecoder().decode([StudyNote].self, from: data) {
            notes = stored
        } else {
            notes = []
        }
    }

    func note(_ id: UUID) -> StudyNote? {
        notes.first { $0.id == id }
    }

    /// Inserts a new note or replaces the one with the same id, moving it to the top.
    func save(_ note: StudyNote) {
        var note = note
        note.updatedAt = .now
        notes.removeAll { $0.id == note.id }
        notes.insert(note, at: 0)
        persist()
    }

    func delete(_ id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    /// From a backup.
    func replace(with notes: [StudyNote]) {
        self.notes = notes.sorted { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func merge(_ incoming: [StudyNote]) {
        replace(with: NoteMerger.merge(existing: notes, incoming: incoming))
    }

    private func persist() {
        do {
            let url = Self.fileURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(notes).write(to: url, options: .atomic)
        } catch {
            assertionFailure("Could not save the notes: \(error)")
        }
    }
}
