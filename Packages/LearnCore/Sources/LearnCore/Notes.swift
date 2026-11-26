import Foundation

/// A note of the learner's own, e.g. "es gibt = ci sono", that the model can tidy up and explain.
public struct StudyNote: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// What the note is about, usually a German expression ("es gibt").
    public var title: String
    /// The learner's own words.
    public var text: String
    /// The model's explanation of why it works that way; nil until asked.
    public var explanation: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), title: String = "", text: String = "", explanation: String? = nil,
                createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id
        self.title = title
        self.text = text
        self.explanation = explanation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { title.trimmed.isEmpty && text.trimmed.isEmpty }

    /// The title, or the first line of the text when there is none.
    public var displayTitle: String {
        let title = title.trimmed
        if !title.isEmpty { return title }
        return text.trimmed.split(separator: "\n").first.map(String.init) ?? ""
    }
}

public enum NoteMerger {
    /// Adds the notes not present yet; for the same note keeps the one edited most recently.
    public static func merge(existing: [StudyNote], incoming: [StudyNote]) -> [StudyNote] {
        var result = existing
        for note in incoming {
            if let index = result.firstIndex(where: { $0.id == note.id }) {
                if note.updatedAt > result[index].updatedAt { result[index] = note }
            } else {
                result.append(note)
            }
        }
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// What the model gives back for a note.
public struct NoteImprovement: Equatable, Sendable {
    public var title: String
    public var text: String
    public var explanation: String

    public init(title: String, text: String, explanation: String) {
        self.title = title
        self.text = text
        self.explanation = explanation
    }
}

/// Tidies up a learner's note and explains the German behind it (text only).
public enum NoteImprovePrompt {
    public static func system() -> String {
        """
        You are a patient German tutor in a learning app. The learner (beginner, around A1-A2, native \
        language probably Italian, app in English) wrote a short study note, for example \
        "es gibt = ci sono". Improve it and explain it.

        Return:
        - title: the German expression or rule the note is about, correctly spelled \
        (e.g. "es gibt + Akkusativ"). Keep the learner's title if it is already right.
        - text: the learner's note rewritten clearly and correctly, short (1-3 lines), keeping their \
        idea and their style. If the note is wrong, correct it. If it is empty, write it from the title.
        - explanation: why it works that way, like a friend who knows grammar. Explain what a word-by-word \
        translation would give and why that is wrong (e.g. "es gibt" is not "lui dà": "es" is an \
        impersonal subject and "geben" here means "to exist"). Then the rule to remember and 2-3 simple \
        everyday example sentences in German with their translation. Use **bold** for the key forms. \
        Short: at most about 120 words. No headings, no tables.

        Write the text and the explanation in the language of the note (Italian or English); German \
        examples stay in German. Every German sentence must be correct. If you are not sure about \
        something, say so.

        Answer with JSON only, shaped as {"title": "...", "text": "...", "explanation": "..."}.
        """
    }

    public static func userInstruction(for note: StudyNote) -> String {
        var lines: [String] = []
        let title = note.title.trimmed
        let text = note.text.trimmed
        if !title.isEmpty { lines.append("Title: \(title)") }
        lines.append(text.isEmpty ? "Note: (empty)" : "Note:\n\(text)")
        return lines.joined(separator: "\n")
    }

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let properties: [String: Any] = ["title": string, "text": string, "explanation": string]
        return [
            "type": "object",
            "properties": properties,
            "required": ["title", "text", "explanation"],
            "additionalProperties": false,
        ]
    }

    public static func parse(_ content: String) throws -> NoteImprovement {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        guard let raw = try? JSONDecoder().decode(RawNote.self, from: Data(String(content[start...end]).utf8)) else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        let explanation = (raw.explanation ?? "").trimmed
        guard !explanation.isEmpty else { throw ExtractionParser.ParseError.invalidJSON }
        return NoteImprovement(title: (raw.title ?? "").trimmed, text: (raw.text ?? "").trimmed,
                               explanation: explanation)
    }
}

private struct RawNote: Decodable {
    let title: String?
    let text: String?
    let explanation: String?
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
