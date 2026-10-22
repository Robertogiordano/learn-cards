import Foundation

/// The six persons of the German present tense.
public enum Person: Int, CaseIterable, Codable, Hashable, Sendable {
    case ich, du, erSieEs, wir, ihr, sieSie

    public var label: String {
        switch self {
        case .ich: return "ich"
        case .du: return "du"
        case .erSieEs: return "er/sie/es"
        case .wir: return "wir"
        case .ihr: return "ihr"
        case .sieSie: return "sie/Sie"
        }
    }

    /// The pronoun to say or write before the form ("er fährt").
    public var pronoun: String {
        switch self {
        case .erSieEs: return "er"
        case .sieSie: return "sie"
        default: return label
        }
    }

    /// Pronouns a learner may put in front of the form for this person.
    var acceptedPronouns: Set<String> {
        switch self {
        case .ich: return ["ich"]
        case .du: return ["du"]
        case .erSieEs: return ["er", "sie", "es", "man"]
        case .wir: return ["wir"]
        case .ihr: return ["ihr"]
        case .sieSie: return ["sie"]
        }
    }
}

public enum VerbGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case regular, stemChanging, irregular, modal, separable, reflexive

    public var label: String {
        switch self {
        case .regular: return "Regolari"
        case .stemChanging: return "Cambio vocalico"
        case .irregular: return "Irregolari"
        case .modal: return "Modali"
        case .separable: return "Separabili"
        case .reflexive: return "Riflessivi"
        }
    }
}

/// A verb with its present tense, independent of how it is stored.
public struct VerbEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var infinitive: String
    public var english: String
    /// Present tense, one form per person in `Person` order, as written after the pronoun:
    /// "fährst", "stehe auf", "wasche mich".
    public var forms: [String]
    public var group: VerbGroup
    /// What to watch out for ("e → i in du and er", "separable: auf goes to the end").
    public var note: String?
    public var emoji: String

    public init(id: UUID = UUID(), infinitive: String, english: String, forms: [String],
                group: VerbGroup = .regular, note: String? = nil, emoji: String = "🏃") {
        self.id = id
        self.infinitive = infinitive
        self.english = english
        self.forms = forms
        self.group = group
        self.note = note
        self.emoji = emoji
    }

    public func form(for person: Person) -> String {
        person.rawValue < forms.count ? forms[person.rawValue] : ""
    }

    /// Persons sharing a form ("macht": er/sie/es and ihr).
    public func persons(with form: String) -> [Person] {
        let key = PhraseChecker.key(form)
        return Person.allCases.filter { PhraseChecker.key(self.form(for: $0)) == key }
    }

    public var isComplete: Bool {
        forms.count == Person.allCases.count && forms.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public var dedupeKey: String { PhraseChecker.key(infinitive) }
}

public enum VerbExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Person + infinitive, pick the form among four.
    case chooseForm
    /// Person + infinitive, type the form.
    case typeForm
    /// Type all six forms.
    case fullTable
    /// A form is shown, pick the person.
    case whichPerson
    /// Person + infinitive, say pronoun and form.
    case speak
    /// English prompt, pick the infinitive among four verbs.
    case translateChoice
    /// English prompt, type the infinitive.
    case translateGerman
    /// Infinitive shown, type the English meaning.
    case translateEnglish
    /// English prompt, say the infinitive.
    case translateSpeak

    public var title: String {
        switch self {
        case .chooseForm: return "Scegli la forma"
        case .typeForm: return "Scrivi la forma"
        case .fullTable: return "Tabella completa"
        case .whichPerson: return "Che persona è?"
        case .speak: return "Pronuncia"
        case .translateChoice: return "Scegli il verbo"
        case .translateGerman: return "Scrivi EN → DE"
        case .translateEnglish: return "Scrivi DE → EN"
        case .translateSpeak: return "Pronuncia il verbo"
        }
    }

    /// Meaning games, as for words; the others train the present tense.
    public var isTranslation: Bool {
        switch self {
        case .translateChoice, .translateGerman, .translateEnglish, .translateSpeak: return true
        default: return false
        }
    }

    public var isSpeaking: Bool { self == .speak || self == .translateSpeak }

    public static var translationKinds: [VerbExerciseKind] { allCases.filter(\.isTranslation) }
    public static var conjugationKinds: [VerbExerciseKind] { allCases.filter { !$0.isTranslation } }
}

public enum VerbExercises {
    /// Answer for one person: the form, with or without the pronoun in front.
    public static func check(_ given: String, verb: VerbEntry, person: Person) -> Verdict {
        var words = PhraseChecker.tokens(given)
        if words.count > 1, person.acceptedPronouns.contains(words[0]) {
            words.removeFirst()
        }
        return PhraseChecker.check(words.joined(separator: " "), accepted: [verb.form(for: person)])
    }

    /// The whole table: the weakest of the six answers.
    public static func checkTable(_ answers: [String], verb: VerbEntry) -> Verdict {
        Person.allCases.map { person in
            person.rawValue < answers.count ? check(answers[person.rawValue], verb: verb, person: person) : .wrong
        }.min() ?? .wrong
    }

    /// Spoken "du fährst": the pronoun may be there or not, the best transcription wins.
    public static func checkSpoken(_ transcripts: [String], verb: VerbEntry, person: Person) -> Verdict {
        transcripts.map { check($0, verb: verb, person: person) }.max() ?? .wrong
    }

    /// A person picked for a shown form: right if that person uses the same form.
    public static func checkPerson(_ chosen: Person, form: String, verb: VerbEntry) -> Verdict {
        verb.persons(with: form).contains(chosen) ? .correct : .wrong
    }

    /// Four options: the right form, plausible wrong endings ("fahrst" for "fährst")
    /// and the verb's other forms.
    public static func options<R: RandomNumberGenerator>(for verb: VerbEntry, person: Person, using rng: inout R) -> [String] {
        let correct = verb.form(for: person)
        let correctKey = PhraseChecker.key(correct)
        let parts = correct.split(separator: " ", maxSplits: 1).map(String.init)
        let tail = parts.count > 1 ? " " + parts[1] : ""

        var stem = verb.infinitive.split(separator: " ").last.map(String.init) ?? verb.infinitive
        if let prefixEnd = tail.isEmpty ? nil : stem.range(of: parts[1].trimmingCharacters(in: .whitespaces)),
           prefixEnd.lowerBound == stem.startIndex {
            stem = String(stem[prefixEnd.upperBound...])
        }
        if stem.hasSuffix("en") { stem.removeLast(2) } else if stem.hasSuffix("n") { stem.removeLast() }
        let fakes = ["e", "st", "t", "en", "est"].map { stem + $0 + tail }

        var result: [String] = []
        var keys: Set<String> = [correctKey]
        for candidate in fakes.shuffled(using: &rng) + verb.forms.shuffled(using: &rng)
        where !candidate.isEmpty && keys.insert(PhraseChecker.key(candidate)).inserted {
            result.append(candidate)
        }
        var options = Array(result.prefix(3)) + [correct]
        options.shuffle(using: &rng)
        return options
    }

    /// From recognising to producing: choose or recognise the person first, then type,
    /// then the full table or speaking.
    /// Meaning first, then the present tense: choosing at level 0, typing at 1,
    /// the full table and speaking later.
    public static func kind<R: RandomNumberGenerator>(level: Int, allowSpeaking: Bool, using rng: inout R) -> VerbExerciseKind {
        let candidates: [VerbExerciseKind]
        switch level {
        case ...0: candidates = [.translateChoice, .chooseForm]
        case 1: candidates = [.translateGerman, .translateEnglish, .typeForm, .whichPerson]
        default:
            candidates = [.fullTable, .typeForm, .translateGerman] + (allowSpeaking ? [.speak, .translateSpeak] : [])
        }
        return candidates.randomElement(using: &rng) ?? .typeForm
    }

    // MARK: - Translation games

    /// The infinitive in German; "sich" in front of a reflexive verb may be left out (or added).
    public static func checkTranslation(_ given: String, verb: VerbEntry) -> Verdict {
        compareGerman(withoutSich(given), withoutSich(verb.infinitive))
    }

    /// The meaning in English: any of the alternatives, "to" optional, one typo is almost.
    public static func checkEnglish(_ given: String, verb: VerbEntry) -> Verdict {
        let accepted = verb.english.split(whereSeparator: { $0 == "/" || $0 == "," }).map(String.init)
        return AnswerChecker.compareEnglish(given, accepted: accepted.isEmpty ? [verb.english] : accepted)
    }

    /// The infinitive said aloud: the best transcription wins.
    public static func checkSpokenInfinitive(_ transcripts: [String], verb: VerbEntry) -> Verdict {
        transcripts.map { checkTranslation($0, verb: verb) }.max() ?? .wrong
    }

    /// Four infinitives: the right one and other saved verbs, same group first.
    /// nil when there are not enough verbs for a real choice.
    public static func translationOptions<R: RandomNumberGenerator>(
        for verb: VerbEntry,
        pool: [VerbEntry],
        using rng: inout R
    ) -> [String]? {
        let others = pool.filter { $0.dedupeKey != verb.dedupeKey }.shuffled(using: &rng)
        let ordered = others.filter { $0.group == verb.group } + others.filter { $0.group != verb.group }
        var keys: Set<String> = [verb.dedupeKey]
        var distractors: [String] = []
        for other in ordered where distractors.count < 3 && keys.insert(other.dedupeKey).inserted {
            distractors.append(other.infinitive)
        }
        guard !distractors.isEmpty else { return nil }
        var options = distractors + [verb.infinitive]
        options.shuffle(using: &rng)
        return options
    }

    private static func withoutSich(_ text: String) -> String {
        let words = AnswerChecker.normalize(text).split(separator: " ")
        return (words.first == "sich" ? words.dropFirst() : words[...]).joined(separator: " ")
    }

    private static func compareGerman(_ given: String, _ expected: String) -> Verdict {
        PhraseChecker.check(given, accepted: [expected])
    }

    /// Per kind: average progress over the verbs (every kind applies to every verb).
    public static func kindMastery(_ streaks: [[VerbExerciseKind: Int]]) -> [VerbExerciseKind: Double] {
        guard !streaks.isEmpty else { return [:] }
        var result: [VerbExerciseKind: Double] = [:]
        for kind in VerbExerciseKind.allCases {
            let total = streaks.map { PathPlanner.progress(level: $0[kind] ?? 0) }.reduce(0, +)
            result[kind] = total / Double(streaks.count)
        }
        return result
    }

    /// Average over all kinds, or over the given ones (translation / conjugation).
    public static func mastery(_ streaks: [[VerbExerciseKind: Int]], kinds subset: [VerbExerciseKind]? = nil) -> Double {
        let all = kindMastery(streaks)
        let values = (subset ?? VerbExerciseKind.allCases).compactMap { all[$0] }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Extraction

/// Step 1 of a verb import: only the infinitives on the photo, a short and fast answer.
public enum VerbListPrompt {
    public static func system() -> String {
        """
        You help a learner of German. You receive a photo of a page from a German course: verb lists, \
        conjugation tables, texts or exercises.

        List the German verbs worth learning, as infinitives (also for verbs that only appear conjugated: \
        "fährst" → "fahren", "stehe auf" → "aufstehen"). Reflexive verbs with "sich" ("sich waschen"). \
        Correct obvious OCR mistakes. Return each verb once and nothing else.

        Answer with JSON only, shaped as {"infinitives": ["fahren", "aufstehen"]}.
        """
    }

    public static let userInstruction = "List the German verbs on this page as infinitives."

    public static var responseSchema: [String: Any] {
        let infinitives: [String: Any] = ["type": "array", "items": ["type": "string"]]
        let properties: [String: Any] = ["infinitives": infinitives]
        return ["type": "object", "properties": properties, "required": ["infinitives"], "additionalProperties": false]
    }

    /// Cleaned infinitives without duplicates; accepts the wrapped object or a bare array.
    public static func parse(_ content: String) throws -> [String] {
        guard let start = content.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = content.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        let data = Data(String(content[start...end]).utf8)
        let decoder = JSONDecoder()
        let raws: [String]
        if let wrapped = try? decoder.decode([String: [String]].self, from: data), let list = wrapped["infinitives"] {
            raws = list
        } else if let bare = try? decoder.decode([String].self, from: data) {
            raws = bare
        } else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        var seen = Set<String>()
        return raws
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(PhraseChecker.key($0)).inserted }
    }
}

/// Which infinitives still need to be conjugated.
public enum VerbExtractionPlan {
    /// The infinitives not already among `existingKeys` (verb dedupe keys), in order.
    public static func missing(_ infinitives: [String], existingKeys: Set<String>) -> [String] {
        infinitives.filter { !existingKeys.contains(PhraseChecker.key($0)) }
    }
}

/// Step 2 of a verb import: the present tense of the new infinitives only, without the photo.
public enum VerbExtractionPrompt {
    public static func system() -> String {
        """
        You help an English-speaking learner conjugate German verbs. You receive a list of German \
        infinitives. Return every verb of the list, once, keeping its infinitive.

        For each verb return:
        - infinitive: as given, e.g. "fahren", "aufstehen", "sich waschen".
        - english: the most common English translation, without "to".
        - forms: the present tense (Präsens) exactly as written after the pronoun, in this order: \
        ich, du, er/sie/es, wir, ihr, sie/Sie. Separable verbs with the prefix at the end \
        ("stehe auf"), reflexive verbs with the reflexive pronoun ("wasche mich", "wäschst dich").
        - group: one of "modal", "separable", "reflexive", "irregular", "stemChanging", "regular" \
        (choose the first that applies in this order; sein, haben and werden are "irregular", \
        verbs changing vowel in du/er like fahren or sprechen are "stemChanging").
        - note: in Italian, at most 8 words on what to watch out for (e.g. "a → ä con du ed er"), null if regular.
        - emoji: exactly ONE emoji that evokes the verb.

        Answer with JSON only, shaped as {"verbs": [ ... ]}.
        """
    }

    public static func userInstruction(for infinitives: [String]) -> String {
        "Conjugate in the present tense: " + infinitives.joined(separator: ", ")
    }

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let forms: [String: Any] = ["type": "array", "items": string, "minItems": 6, "maxItems": 6]
        let group: [String: Any] = ["type": "string", "enum": VerbGroup.allCases.map(\.rawValue)]
        let properties: [String: Any] = [
            "infinitive": string, "english": string, "forms": forms, "group": group,
            "note": nullableString, "emoji": string,
        ]
        let verb: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["infinitive", "english", "forms", "group", "note", "emoji"],
            "additionalProperties": false,
        ]
        let verbs: [String: Any] = ["type": "array", "items": verb]
        let rootProperties: [String: Any] = ["verbs": verbs]
        return ["type": "object", "properties": rootProperties, "required": ["verbs"], "additionalProperties": false]
    }
}

public enum VerbExtractionParser {
    public static func parse(_ content: String) throws -> [VerbEntry] {
        guard let start = content.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = content.lastIndex(where: { $0 == "}" || $0 == "]" }),
              start < end else {
            throw ExtractionParser.ParseError.noJSON
        }
        let data = Data(String(content[start...end]).utf8)
        let decoder = JSONDecoder()
        let raws: [RawVerb]
        if let wrapped = try? decoder.decode(RawVerbs.self, from: data) {
            raws = wrapped.verbs
        } else if let bare = try? decoder.decode([RawVerb].self, from: data) {
            raws = bare
        } else {
            throw ExtractionParser.ParseError.invalidJSON
        }
        var seen = Set<String>()
        return raws.compactMap(entry(from:)).filter { seen.insert($0.dedupeKey).inserted }
    }

    private static func entry(from raw: RawVerb) -> VerbEntry? {
        let infinitive = clean(raw.infinitive)
        let english = clean(raw.english)
        let forms = raw.forms.map { clean($0) }
        guard !infinitive.isEmpty, !english.isEmpty, forms.count == Person.allCases.count,
              forms.allSatisfy({ !$0.isEmpty }) else { return nil }
        let note = clean(raw.note)
        return VerbEntry(
            infinitive: infinitive,
            english: english.hasPrefix("to ") ? String(english.dropFirst(3)) : english,
            forms: forms,
            group: VerbGroup(rawValue: clean(raw.group)) ?? .regular,
            note: note.isEmpty ? nil : note,
            emoji: clean(raw.emoji).first.map(String.init) ?? "🏃"
        )
    }

    private static func clean(_ text: String?) -> String {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RawVerbs: Decodable {
    let verbs: [RawVerb]
}

private struct RawVerb: Decodable {
    let infinitive: String?
    let english: String?
    let forms: [String]
    let group: String?
    let note: String?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case infinitive, english, forms, group, note, emoji
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        infinitive = string(.infinitive)
        english = string(.english)
        group = string(.group)
        note = string(.note)
        emoji = string(.emoji)
        if let list = try? container.decode([String].self, forKey: .forms) {
            forms = list
        } else if let table = try? container.decode([String: String].self, forKey: .forms) {
            // {"ich": "fahre", "du": "fährst", ...}
            let keys = [["ich"], ["du"], ["er", "er/sie/es"], ["wir"], ["ihr"], ["sie", "sie/Sie", "Sie"]]
            forms = keys.map { options in options.lazy.compactMap { table[$0] }.first ?? "" }
        } else {
            forms = []
        }
    }
}

// MARK: - Backup

public struct BackupVerb: Codable, Hashable, Sendable {
    public var id: UUID
    public var infinitive: String
    public var english: String
    public var forms: [String]
    public var group: VerbGroup
    public var note: String?
    public var emoji: String
    public var createdAt: Date
    public var updatedAt: Date
    public var srs: SRSState
    public var streak: Int
    /// Right answers in a row per kind of exercise (keyed by its raw value).
    public var kindStreaks: [String: Int]

    public init(entry: VerbEntry, createdAt: Date, updatedAt: Date, srs: SRSState,
                streak: Int = 0, kindStreaks: [VerbExerciseKind: Int] = [:]) {
        id = entry.id
        infinitive = entry.infinitive
        english = entry.english
        forms = entry.forms
        group = entry.group
        note = entry.note
        emoji = entry.emoji
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.streak = streak
        self.kindStreaks = Dictionary(uniqueKeysWithValues: kindStreaks.map { ($0.key.rawValue, $0.value) })
    }

    public var entry: VerbEntry {
        VerbEntry(id: id, infinitive: infinitive, english: english, forms: forms, group: group, note: note, emoji: emoji)
    }

    public var streaksByKind: [VerbExerciseKind: Int] {
        var result: [VerbExerciseKind: Int] = [:]
        for (key, value) in kindStreaks {
            if let kind = VerbExerciseKind(rawValue: key) { result[kind] = value }
        }
        return result
    }

    public var dedupeKey: String { PhraseChecker.key(infinitive) }

    public var lastActivity: Date { max(updatedAt, srs.lastReviewed ?? .distantPast) }
}

public struct VerbMergeResult: Sendable {
    public var inserts: [BackupVerb]
    public var updates: [BackupVerb]
    public var skipped: Int
}

public enum BackupVerbMerger {
    /// Matches by id first, then by infinitive; the copy with the latest activity wins.
    public static func merge(existing: [BackupVerb], incoming: [BackupVerb]) -> VerbMergeResult {
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byKey = Dictionary(existing.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
        var result = VerbMergeResult(inserts: [], updates: [], skipped: 0)
        var seenKeys = Set<String>()
        for var verb in incoming {
            guard seenKeys.insert(verb.dedupeKey).inserted else {
                result.skipped += 1
                continue
            }
            if let match = byID[verb.id] ?? byKey[verb.dedupeKey] {
                if verb.lastActivity > match.lastActivity {
                    verb.id = match.id
                    result.updates.append(verb)
                } else {
                    result.skipped += 1
                }
            } else {
                result.inserts.append(verb)
            }
        }
        return result
    }
}
