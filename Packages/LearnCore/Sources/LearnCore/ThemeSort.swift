import Foundation

/// How theme lists (the path's theme map, the vocabulary) are ordered.
public enum ThemeSort: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    /// The default: themes with new words first, then A–Z.
    case standard
    /// A–Z.
    case alphabetical
    /// The theme with the most recently added or edited word first.
    case lastUpdated
    /// The theme with the most words first.
    case wordCount

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .standard: return "New words first"
        case .alphabetical: return "A–Z"
        case .lastUpdated: return "Last updated"
        case .wordCount: return "Most words"
        }
    }

    public var systemImage: String {
        switch self {
        case .standard: return "sparkles"
        case .alphabetical: return "textformat"
        case .lastUpdated: return "clock.arrow.circlepath"
        case .wordCount: return "number"
        }
    }
}

/// What ordering needs to know about one theme.
public struct ThemeStats: Hashable, Sendable {
    public var theme: String
    public var wordCount: Int
    /// Words never studied.
    public var newCount: Int
    /// The latest a word of the theme was added or edited.
    public var lastUpdated: Date

    public init(theme: String, wordCount: Int, newCount: Int = 0, lastUpdated: Date) {
        self.theme = theme
        self.wordCount = wordCount
        self.newCount = newCount
        self.lastUpdated = lastUpdated
    }
}

public enum ThemeOrdering {
    /// Themes in the chosen order. "Misc" stays last except when sorting by date or size;
    /// ties fall back to A–Z so the order is stable.
    public static func sorted(_ stats: [ThemeStats], by sort: ThemeSort) -> [ThemeStats] {
        stats.sorted { lhs, rhs in
            switch sort {
            case .standard:
                if (lhs.newCount > 0) != (rhs.newCount > 0) { return lhs.newCount > 0 }
                if let misc = miscLast(lhs, rhs) { return misc }
            case .alphabetical:
                if let misc = miscLast(lhs, rhs) { return misc }
            case .lastUpdated:
                if lhs.lastUpdated != rhs.lastUpdated { return lhs.lastUpdated > rhs.lastUpdated }
            case .wordCount:
                if lhs.wordCount != rhs.wordCount { return lhs.wordCount > rhs.wordCount }
            }
            return alphabetical(lhs.theme, rhs.theme)
        }
    }

    /// The theme names only.
    public static func themes(_ stats: [ThemeStats], by sort: ThemeSort) -> [String] {
        sorted(stats, by: sort).map(\.theme)
    }

    private static func miscLast(_ lhs: ThemeStats, _ rhs: ThemeStats) -> Bool? {
        if lhs.theme == rhs.theme { return nil }
        if lhs.theme == VocabEntry.defaultCategory { return false }
        if rhs.theme == VocabEntry.defaultCategory { return true }
        return nil
    }

    private static func alphabetical(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
}
