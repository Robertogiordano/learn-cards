import Foundation
import LearnCore
import SwiftUI
import UIKit

enum SettingsKey {
    static let model = "openRouterModel"
    static let area = "studyArea"
    static let excludedThemes = "excludedThemes"
    static let studyMode = "studyMode"
    static let sessionSize = "sessionSize"
    static let lessonNewWords = "lessonNewWords"
    static let bonusSize = "bonusSize"
    static let numbersLevel = "numbersLevel"
    static let importKind = "importKind"
    static let vocabularyKind = "vocabularyKind"
    static let speakingInMixed = "speakingInMixed"
    static let autoSpeak = "autoSpeak"
    /// Emoji on the exercise cards; toggled from the card itself or from Settings.
    static let showEmoji = "showEmoji"
    static let lastExport = "lastExportDate"
    static let dailyGoalMinutes = "dailyGoalMinutes"
    static let reminderEnabled = "reminderEnabled"
    /// Minutes after midnight.
    static let reminderMinutes = "reminderMinutes"
    /// Importing phrases also extracts words / verbs from the same photo.
    static let phraseImportWords = "phraseImportWords"
    static let phraseImportVerbs = "phraseImportVerbs"
    /// The word review also creates a word set from the extracted words.
    static let reviewCreatesSet = "reviewCreatesSet"
}

struct ModelOption: Identifiable {
    let id: String
    let name: String
    let note: String
}

enum OpenRouterModels {
    static let defaultModel = "google/gemini-2.5-flash"

    static let presets = [
        ModelOption(id: "google/gemini-2.5-flash", name: "Gemini 2.5 Flash", note: "Recommended · ~0.5 cents per photo"),
        ModelOption(id: "google/gemini-2.5-flash-lite", name: "Gemini 2.5 Flash-Lite", note: "Cheaper · less accurate on articles and plurals"),
        ModelOption(id: "openai/gpt-4.1-mini", name: "GPT-4.1 mini", note: "Alternative · similar cost to Flash"),
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
        case .mixed: return "Mixed"
        case .multipleChoice: return "Multiple choice"
        case .typeGerman: return area == .translation ? "Type in German (EN → DE)" : "Type in German"
        case .typeEnglish: return "Type in English (DE → EN)"
        case .speakGerman: return "Say it in German"
        }
    }

    /// Compact title for tiles.
    func shortTitle(in area: StudyArea) -> String {
        switch self {
        case .mixed: return "Mixed"
        case .multipleChoice: return "Multiple choice"
        case .typeGerman: return area == .translation ? "Type EN → DE" : "Type"
        case .typeEnglish: return "Type DE → EN"
        case .speakGerman: return "Speak"
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
        case (.translation, .multipleChoice): return "Choose the German translation"
        case (.translation, .typeEnglish): return "Type in English"
        case (.translation, .speakGerman): return "Say it in German"
        case (.translation, _): return "Type in German"
        case (.article, .multipleChoice): return "Choose the right articles"
        case (.article, .speakGerman): return "Say it with the definite and indefinite article"
        case (.article, _): return "Type it with the definite and indefinite article"
        case (.plural, .multipleChoice): return "Choose the plural"
        case (.plural, .speakGerman): return "Say the plural"
        case (.plural, _): return "Type the plural"
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

extension Color {
    /// Card background that ties a noun to its gender in translation exercises:
    /// blue for der, pink for die, grey for das (darker tones in dark mode).
    static func gender(_ article: Article) -> Color {
        let hex = genderHex(article)
        return Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? hex.dark : hex.light)
        })
    }

    private static func genderHex(_ article: Article) -> (light: UInt32, dark: UInt32) {
        switch article {
        case .der: return (0xCFE5FF, 0x1F3A5C)
        case .die: return (0xFFD9E8, 0x5C2643)
        case .das: return (0xD5D7DD, 0x4A4C55)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
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
