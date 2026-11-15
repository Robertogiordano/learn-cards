import Foundation

/// Photos sent in the grammar chats, as JPEG files in Application Support. They stay on the
/// phone only (not in backups), so the chat messages just keep their file names.
enum GrammarChatImageStore {
    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("grammarChatImages", isDirectory: true)
    }

    /// Saves the JPEG and returns its file name.
    static func save(_ jpeg: Data) throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".jpg"
        try jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func data(_ name: String) -> Data? {
        try? Data(contentsOf: folder.appendingPathComponent(name))
    }

    static func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }
}
