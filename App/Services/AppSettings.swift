import Foundation
import LearnCore
import SwiftUI

enum SettingsKey {
    static let model = "openRouterModel"
    static let level = "studyLevel"
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

/// The exercise chosen on the study screen: one kind, or a random mix.
enum StudyMode: String, CaseIterable, Identifiable {
    case mixed, multipleChoice, typeGerman, typeEnglish, speakGerman

    var id: String { rawValue }

    var kind: ExerciseKind? { ExerciseKind(rawValue: rawValue) }

    var title: String {
        switch self {
        case .mixed: return "Misto"
        case .multipleChoice: return "Scelta multipla (EN → DE)"
        case .typeGerman: return "Scrivi in tedesco (EN → DE)"
        case .typeEnglish: return "Scrivi in inglese (DE → EN)"
        case .speakGerman: return "Pronuncia in tedesco (EN → DE)"
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
        var suffix = ""
        if requiresArticle { suffix += requiresPlural ? ", con articolo e plurale" : ", con l'articolo" }
        switch kind {
        case .multipleChoice: return "Scegli la traduzione tedesca"
        case .typeGerman: return "Scrivi in tedesco" + suffix
        case .typeEnglish: return "Scrivi in inglese"
        case .speakGerman: return "Di' in tedesco" + suffix
        }
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
