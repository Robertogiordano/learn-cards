import Foundation

/// What the AI coach receives: a compact picture of the learner, never photos or full lists.
public struct CoachSummary: Codable, Sendable {
    public struct Group: Codable, Sendable {
        public var name: String
        public var items: Int
        /// Percent per exercise family, e.g. ["translation": 40, "article": 10].
        public var mastery: [String: Int]

        public init(name: String, items: Int, mastery: [String: Int]) {
            self.name = name
            self.items = items
            self.mastery = mastery
        }
    }

    public struct Mistake: Codable, Sendable {
        public var exercise: String
        public var prompt: String
        public var given: String
        public var expected: String
        public var theme: String?

        public init(_ record: ErrorRecord) {
            exercise = record.exercise
            prompt = record.prompt
            given = record.given
            expected = record.expected
            theme = record.theme
        }
    }

    public var goalMinutes: Int
    public var request: String
    public var wordThemes: [Group]
    public var phraseCategories: [Group]
    public var verbGroups: [Group]
    /// Percent per number level, "1"..."4".
    public var numberLevels: [String: Int]
    public var recentMistakes: [Mistake]

    public init(goalMinutes: Int, request: String, wordThemes: [Group], phraseCategories: [Group],
                verbGroups: [Group], numberLevels: [String: Int], recentMistakes: [Mistake]) {
        self.goalMinutes = goalMinutes
        self.request = request
        self.wordThemes = wordThemes
        self.phraseCategories = phraseCategories
        self.verbGroups = verbGroups
        self.numberLevels = numberLevels
        self.recentMistakes = recentMistakes
    }

    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// The coach's answer: a short message and blocks of exercises chosen among the learner's data.
public struct CoachPlan: Codable, Sendable {
    public struct Block: Codable, Sendable {
        /// "words", "phrases", "verbs", "compounds" or "numbers".
        public var type: String
        /// Word themes, phrase categories or verb groups (labels as given); empty = any.
        public var groups: [String]
        /// For words: "translation", "article", "plural"; empty = any.
        public var areas: [String]
        /// "errors", "due", "new", "weak" or "all".
        public var focus: String
        /// A kind of exercise of that type, or "auto".
        public var exercise: String
        public var count: Int
        /// For numbers: 1...4.
        public var level: Int?

        public init(type: String, groups: [String] = [], areas: [String] = [], focus: String = "all",
                    exercise: String = "auto", count: Int, level: Int? = nil) {
            self.type = type
            self.groups = groups
            self.areas = areas
            self.focus = focus
            self.exercise = exercise
            self.count = count
            self.level = level
        }
    }

    public var message: String
    public var blocks: [Block]
}

public enum CoachPrompt {
    public static func system() -> String {
        let wordKinds = ExerciseKind.allCases.map(\.rawValue).joined(separator: ", ")
        let phraseKinds = PhraseExerciseKind.allCases.map(\.rawValue).joined(separator: ", ")
        let verbKinds = VerbExerciseKind.allCases.map(\.rawValue).joined(separator: ", ")
        let numberKinds = NumberExerciseKind.allCases.map(\.rawValue).joined(separator: ", ")
        let compoundKinds = CompoundExerciseKind.allCases.filter { $0 != .matchPairs }.map(\.rawValue)
            .joined(separator: ", ")
        return """
        You are a German teacher preparing today's lesson for an English-speaking learner who studies with \
        flashcards. You receive a JSON summary of the learner: daily goal in minutes, their request \
        for today (may be empty), mastery per word theme, phrase category, verb group and number \
        level, and their recent mistakes.

        Build a lesson that fits the daily goal (about 5 short questions per minute; phrases and \
        verbs take twice as long) only out of the learner's existing material. Follow the request \
        when there is one; otherwise work on the recent mistakes first, then weak groups, then due \
        reviews, with a few new items. Use only group names that appear in the summary.

        Answer with JSON only:
        {"message": "...", "blocks": [{"type": "...", "groups": [...], "areas": [...], "focus": "...", \
        "exercise": "...", "count": n, "level": n|null}]}
        - message: 2-3 sentences in English, warm and concrete: what we work on today and why \
        (mention the typical mistake if there is one).
        - type: "words", "phrases", "verbs", "compounds" (games joining the parts of compound \
        words, from the "\(VocabEntry.compoundCategory)" theme) or "numbers".
        - groups: word themes, phrase categories or verb groups from the summary; [] for any.
        - areas: only for words: "translation", "article", "plural"; [] for any.
        - focus: "errors", "due", "new", "weak" or "all".
        - exercise: "auto", or for words one of: \(wordKinds); for phrases: \(phraseKinds); \
        for verbs: \(verbKinds); for compounds: \(compoundKinds); for numbers: \(numberKinds).
        - count: questions in the block (1-20).
        - level: only for numbers, 1-4.
        Use 2 to 6 blocks.
        """
    }

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let strings: [String: Any] = ["type": "array", "items": string]
        let integer: [String: Any] = ["type": "integer"]
        let nullableInteger: [String: Any] = ["type": ["integer", "null"]]
        let properties: [String: Any] = [
            "type": string, "groups": strings, "areas": strings, "focus": string,
            "exercise": string, "count": integer, "level": nullableInteger,
        ]
        let block: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["type", "groups", "areas", "focus", "exercise", "count", "level"],
            "additionalProperties": false,
        ]
        let blocks: [String: Any] = ["type": "array", "items": block]
        let rootProperties: [String: Any] = ["message": string, "blocks": blocks]
        return ["type": "object", "properties": rootProperties, "required": ["message", "blocks"],
                "additionalProperties": false]
    }

    public static func parse(_ content: String) throws -> CoachPlan {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        guard let plan = try? JSONDecoder().decode(CoachPlan.self, from: Data(String(content[start...end]).utf8)) else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        return plan
    }
}

/// Turns the coach's blocks into concrete questions, using only what exists.
public enum CoachResolver {
    public static let maximumPerBlock = 20

    public static func resolve<R: RandomNumberGenerator>(
        _ plan: CoachPlan,
        candidates: [LessonCandidate],
        using rng: inout R
    ) -> [LessonItem] {
        var items: [LessonItem] = []
        var used = Set<String>()
        for block in plan.blocks {
            let count = min(max(block.count, 0), maximumPerBlock)
            guard count > 0 else { continue }

            if block.type == "numbers" {
                let level = min(max(block.level ?? 1, 1), NumberLevel.allCases.count)
                let kind = NumberExerciseKind(rawValue: block.exercise)?.rawValue
                items += (0..<count).map { _ in
                    LessonItem(domain: .number, kind: kind, numberLevel: level, reason: .practice)
                }
                continue
            }

            guard let domain = domain(for: block.type) else { continue }
            let groups = Set(block.groups.map { $0.lowercased() })
            let areas = Set(block.areas.compactMap(StudyArea.init(rawValue:)))
            var pool = candidates.filter { candidate in
                candidate.item.domain == domain
                    && (groups.isEmpty || groups.contains((candidate.theme ?? "").lowercased()))
                    && (areas.isEmpty || candidate.item.area.map { areas.contains($0) } == true)
            }
            switch block.focus {
            case "errors": pool = pool.filter { $0.recentErrors > 0 }.sorted { $0.recentErrors > $1.recentErrors }
            case "due": pool = pool.filter { $0.isDue && !$0.isNew }.shuffled(using: &rng)
            case "new": pool = pool.filter(\.isNew).shuffled(using: &rng)
            case "weak": pool = pool.filter { !$0.isNew }.sorted { $0.mastery < $1.mastery }
            default: pool.shuffle(using: &rng)
            }
            let kind = validKind(block.exercise, for: domain, area: areas.count == 1 ? areas.first : nil)
            var taken = 0
            for candidate in pool where taken < count && used.insert(candidate.item.identity).inserted {
                var item = candidate.item
                item.kind = kind
                item.reason = block.focus == "errors" ? .error : .focus
                items.append(item)
                taken += 1
            }
        }
        return items
    }

    private static func domain(for type: String) -> LessonItem.Domain? {
        switch type {
        case "words": return .word
        case "phrases": return .phrase
        case "verbs": return .verb
        case "compounds": return .compound
        default: return nil
        }
    }

    /// The forced kind only when it exists for that domain (and for the area, for words).
    private static func validKind(_ raw: String, for domain: LessonItem.Domain, area: StudyArea?) -> String? {
        switch domain {
        case .word:
            guard let kind = ExerciseKind(rawValue: raw) else { return nil }
            if let area, !area.kinds.contains(kind) { return nil }
            return kind.rawValue
        case .phrase: return PhraseExerciseKind(rawValue: raw)?.rawValue
        case .verb: return VerbExerciseKind(rawValue: raw)?.rawValue
        case .number: return NumberExerciseKind(rawValue: raw)?.rawValue
        case .compound:
            // A lesson asks one compound at a time: matching needs several.
            guard let kind = CompoundExerciseKind(rawValue: raw), kind != .matchPairs else { return nil }
            return kind.rawValue
        }
    }
}
