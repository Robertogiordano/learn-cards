import Foundation
import LearnCore
import SwiftUI

enum SettingsKey {
    static let model = "openRouterModel"
    static let area = "studyArea"
    static let excludedThemes = "excludedThemes"
    static let studyMode = "studyMode"
    static let sessionSize = "sessionSize"
    static let speakingInMixed = "speakingInMixed"
    static let autoSpeak = "autoSpeak"
    static let lastExport = "lastExportDate"
}

struct ModelOption: Identifiable {
    let id: String
    let name: String
    let note: String
}

enum OpenRouterModels {
    static let defaultModel = "google/gemini-2.5-flash"

    static let presets = [
        ModelOption(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash", note: "Consigliato · ~0,5 cent a foto"),
        ModelOption(id: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash-Lite", note: "Più economico · meno preciso su articoli e plurali"),
        ModelOption(id: "openai/gpt-4.1-mini", name: "GPT-4.1 mini", note: "Alternativa · costo simile a Flash"),
    ]
}

/// The exercise chosen on the study screen: one kind, or a random mix of the area's kinds.
enum StudyMode: String, CaseIterable, Identifiable {
    case mixed, multipleChoice, typeGerman, typeEnglish, speakGerman

    var id: String { rawValue }

    var kind: ExerciseKind? { ExerciseKind(rawValue: rawValue) }

    static func available(in area: StudyArea) -> [StudyMode] {
        [.mixed] + area.kinds.compactMap { StudyMode(rawValue: $0.rawValue) }
    }

    func title(in area: StudyArea) -> String {
        switch self {
        case .mixed: return "Misto"
        case .multipleChoice: return "Scelta multipla"
        case .typeGerman: return area == .translation ? "Scrivi in tedesco (EN → DE)" : "Scrivi in tedesco"
        case .typeEnglish: return "Scrivi in inglese (DE → EN)"
        case .speakGerman: return "Pronuncia in tedesco"
        }
    }

    var systemImage: String {
        switch self {
        case .mixed: return "shuffle"
        case .multipleChoice: return "square.grid.2x2"
        case .typeGerman: return "keyboard"
        case .typeEnglish: return "character.cursor.ibeam"
        case .speakGerman: return "mic"
        }
    }
}

extension Exercise {
    var instruction: String {
        switch (area, kind) {
        case (.translation, .multipleChoice): return "Scegli la traduzione tedesca"
        case (.translation, .typeEnglish): return "Scrivi in inglese"
        case (.translation, .speakGerman): return "Di' in tedesco"
        case (.translation, _): return "Scrivi in tedesco"
        case (.article, .multipleChoice): return "Scegli gli articoli giusti"
        case (.article, .speakGerman): return "Di' con l'articolo determinativo e indeterminativo"
        case (.article, _): return "Scrivi l'articolo determinativo e indeterminativo"
        case (.plural, .multipleChoice): return "Scegli il plurale"
        case (.plural, .speakGerman): return "Di' il plurale"
        case (.plural, _): return "Scrivi il plurale"
        }
    }
}

/// Themes the learner switched off on the study screen, stored as JSON in AppStorage.
/// Storing the excluded ones means themes created later are included by default.
enum ThemeSelection {
    static func decode(_ raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8),
              let themes = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(themes)
    }

    static func encode(_ themes: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(themes.sorted()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Binding where Value == Bool {
    /// True while the optional holds a value; setting false clears it.
    init<Wrapped>(isPresent optional: Binding<Wrapped?>) {
        self.init(
            get: { optional.wrappedValue != nil },
            set: { if !$0 { optional.wrappedValue = nil } }
        )
    }
}
