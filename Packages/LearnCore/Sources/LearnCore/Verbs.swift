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

/// The tenses a verb is conjugated in.
public enum VerbTense: String, CaseIterable, Codable, Hashable, Sendable {
    /// Präsens: "ich fahre".
    case present
    /// Präteritum: "ich fuhr".
    case preterite

    public var label: String {
        switch self {
        case .present: return "Present"
        case .preterite: return "Preterite"
        }
    }

    /// The German name, as in the course books.
    public var germanName: String {
        switch self {
        case .present: return "Präsens"
        case .preterite: return "Präteritum"
        }
    }
}

public enum VerbGroup: String, CaseIterable, Codable, Hashable, Sendable {
    case regular, stemChanging, irregular, modal, separable, reflexive

    public var label: String {
        switch self {
        case .regular: return "Regular"
        case .stemChanging: return "Stem-changing"
        case .irregular: return "Irregular"
        case .modal: return "Modal"
        case .separable: return "Separable"
        case .reflexive: return "Reflexive"
        }
    }

    /// Groups describing the base verb; separable is a separate flag (`VerbEntry.separablePrefix`).
    public static var baseGroups: [VerbGroup] { allCases.filter { $0 != .separable } }
}

public enum SeparableVerbs {
    /// Trimmed, lowercased prefix, nil when empty.
    public static func clean(_ prefix: String?) -> String? {
        let trimmed = (prefix ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The prefix read off the table: "stehe auf" for "aufstehen" gives "auf".
    /// For verbs saved before the prefix was stored.
    public static func inferPrefix(infinitive: String, forms: [String]) -> String? {
        let base = infinitive.lowercased().split(separator: " ").last.map(String.init) ?? ""
        guard let first = forms.first,
              let last = first.lowercased().split(separator: " ").last.map(String.init),
              first.split(separator: " ").count > 1,
              base.hasPrefix(last), base.count > last.count else { return nil }
        return last
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
    /// Preterite (Präteritum), one form per person in `Person` order, as written after the pronoun:
    /// "fuhr", "fuhrst", "stand auf". Empty when not known yet.
    public var preterite: [String]
    public var group: VerbGroup
    /// What to watch out for ("e → i in du and er", "separable: auf goes to the end").
    public var note: String?
    public var emoji: String
    /// The prefix that goes to the end ("auf" in "aufstehen"), nil when the verb is not separable.
    /// Separable is independent of the group: "anfangen" is separable and stem-changing.
    public var separablePrefix: String?

    public init(id: UUID = UUID(), infinitive: String, english: String, forms: [String],
                preterite: [String] = [], group: VerbGroup = .regular, note: String? = nil, emoji: String = "🏃",
                separablePrefix: String? = nil) {
        self.id = id
        self.infinitive = infinitive
        self.english = english
        self.forms = forms
        self.preterite = preterite
        self.group = group
        self.note = note
        self.emoji = emoji
        self.separablePrefix = SeparableVerbs.clean(separablePrefix)
    }

    public var isSeparable: Bool { separablePrefix != nil || group == .separable }

    /// Where the verb is listed: separable verbs have their own section, whatever their group.
    public var section: VerbGroup { isSeparable ? .separable : group }

    /// The six forms of a tense (empty when the preterite is not known).
    public func forms(in tense: VerbTense) -> [String] {
        switch tense {
        case .present: return forms
        case .preterite: return preterite
        }
    }

    public func form(for person: Person, tense: VerbTense = .present) -> String {
        let list = forms(in: tense)
        return person.rawValue < list.count ? list[person.rawValue] : ""
    }

    /// Persons sharing a form ("macht": er/sie/es and ihr; "fuhr": ich and er/sie/es).
    public func persons(with form: String, tense: VerbTense = .present) -> [Person] {
        let key = PhraseChecker.key(form)
        return Person.allCases.filter { PhraseChecker.key(self.form(for: $0, tense: tense)) == key }
    }

    public var isComplete: Bool { isComplete(.present) }

    /// All six forms of the tense are filled in.
    public func isComplete(_ tense: VerbTense) -> Bool {
        let list = forms(in: tense)
        return list.count == Person.allCases.count && list.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The preterite is there: its exercises apply to this verb.
    public var hasPreterite: Bool { isComplete(.preterite) }

    /// Whether an exercise can be asked about this verb.
    public func supports(_ kind: VerbExerciseKind) -> Bool {
        kind.tense.map(isComplete) ?? true
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
    /// The same five conjugation games in the preterite.
    case chooseFormPreterite
    case typeFormPreterite
    case fullTablePreterite
    case whichPersonPreterite
    case speakPreterite

    public var title: String {
        switch base {
        case .chooseForm: return "Choose the form"
        case .typeForm: return "Type the form"
        case .fullTable: return "Full table"
        case .whichPerson: return "Which person?"
        case .speak: return "Speak"
        case .translateChoice: return "Choose the verb"
        case .translateGerman: return "Type EN → DE"
        case .translateEnglish: return "Type DE → EN"
        default: return "Say the verb"
        }
    }

    /// The tense trained; nil for the meaning games.
    public var tense: VerbTense? {
        switch self {
        case .translateChoice, .translateGerman, .translateEnglish, .translateSpeak: return nil
        case .chooseFormPreterite, .typeFormPreterite, .fullTablePreterite, .whichPersonPreterite, .speakPreterite:
            return .preterite
        default: return .present
        }
    }

    /// The game this kind plays, whatever the tense: `.typeFormPreterite` plays `.typeForm`.
    public var base: VerbExerciseKind {
        switch self {
        case .chooseFormPreterite: return .chooseForm
        case .typeFormPreterite: return .typeForm
        case .fullTablePreterite: return .fullTable
        case .whichPersonPreterite: return .whichPerson
        case .speakPreterite: return .speak
        default: return self
        }
    }

    /// The same game in another tense (meaning games stay as they are).
    public func inTense(_ tense: VerbTense) -> VerbExerciseKind {
        guard self.tense != nil else { return self }
        return VerbExerciseKind.allCases.first { $0.base == base && $0.tense == tense } ?? self
    }

    /// Meaning games, as for words; the others train a tense.
    public var isTranslation: Bool { tense == nil }

    public var isSpeaking: Bool { base == .speak || base == .translateSpeak }

    /// Recognition rather than production: graded like multiple choice.
    public var isRecognition: Bool { [.chooseForm, .whichPerson, .translateChoice].contains(base) }

    public static var translationKinds: [VerbExerciseKind] { allCases.filter(\.isTranslation) }
    /// Every conjugation game, all tenses.
    public static var conjugationKinds: [VerbExerciseKind] { allCases.filter { !$0.isTranslation } }

    /// The conjugation games of one tense.
    public static func conjugationKinds(_ tense: VerbTense) -> [VerbExerciseKind] {
        allCases.filter { $0.tense == tense }
    }
}

public enum VerbExercises {
    /// Answer for one person: the form, with or without the pronoun in front.
    public static func check(_ given: String, verb: VerbEntry, person: Person, tense: VerbTense = .present) -> Verdict {
        var words = PhraseChecker.tokens(given)
        if words.count > 1, person.acceptedPronouns.contains(words[0]) {
            words.removeFirst()
        }
        return PhraseChecker.check(words.joined(separator: " "), accepted: [verb.form(for: person, tense: tense)])
    }

    /// The whole table: the weakest of the six answers.
    public static func checkTable(_ answers: [String], verb: VerbEntry, tense: VerbTense = .present) -> Verdict {
        Person.allCases.map { person in
            person.rawValue < answers.count
                ? check(answers[person.rawValue], verb: verb, person: person, tense: tense) : .wrong
        }.min() ?? .wrong
    }

    /// Spoken "du fährst": the pronoun may be there or not, the best transcription wins.
    public static func checkSpoken(_ transcripts: [String], verb: VerbEntry, person: Person,
                                   tense: VerbTense = .present) -> Verdict {
        transcripts.map { check($0, verb: verb, person: person, tense: tense) }.max() ?? .wrong
    }

    /// A person picked for a shown form: right if that person uses the same form.
    public static func checkPerson(_ chosen: Person, form: String, verb: VerbEntry,
                                   tense: VerbTense = .present) -> Verdict {
        verb.persons(with: form, tense: tense).contains(chosen) ? .correct : .wrong
    }

    /// Four options: the right form, plausible wrong endings ("fahrst" for "fährst",
    /// "fahrte" for "fuhr") and the verb's other forms, in either tense.
    public static func options<R: RandomNumberGenerator>(for verb: VerbEntry, person: Person,
                                                         tense: VerbTense = .present,
                                                         using rng: inout R) -> [String] {
        let correct = verb.form(for: person, tense: tense)
        let correctKey = PhraseChecker.key(correct)
        let parts = correct.split(separator: " ", maxSplits: 1).map(String.init)
        let tail = parts.count > 1 ? " " + parts[1] : ""

        var stem = verb.infinitive.split(separator: " ").last.map(String.init) ?? verb.infinitive
        if let prefixEnd = tail.isEmpty ? nil : stem.range(of: parts[1].trimmingCharacters(in: .whitespaces)),
           prefixEnd.lowerBound == stem.startIndex {
            stem = String(stem[prefixEnd.upperBound...])
        }
        if stem.hasSuffix("en") { stem.removeLast(2) } else if stem.hasSuffix("n") { stem.removeLast() }
        let endings: [String]
        switch tense {
        case .present: endings = ["e", "st", "t", "en", "est"]
        case .preterite: endings = ["te", "test", "ten", "tet", "t"]
        }
        let fakes = endings.map { stem + $0 + tail }
        // The other tense is a typical mix-up too: "fährt" for "fuhr".
        let other: VerbTense = tense == .present ? .preterite : .present
        let sameTense = verb.forms(in: tense).shuffled(using: &rng)
        let mixUp = verb.form(for: person, tense: other)

        var result: [String] = []
        var keys: Set<String> = [correctKey]
        for candidate in [mixUp] + fakes.shuffled(using: &rng) + sameTense
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
    /// With the preterite known, its games join from level 1, a step behind the present.
    public static func kind<R: RandomNumberGenerator>(level: Int, allowSpeaking: Bool, hasPreterite: Bool = false,
                                                      using rng: inout R) -> VerbExerciseKind {
        var candidates: [VerbExerciseKind]
        switch level {
        case ...0: candidates = [.translateChoice, .chooseForm]
        case 1:
            candidates = [.translateGerman, .translateEnglish, .typeForm, .whichPerson]
                + (hasPreterite ? [.chooseFormPreterite, .whichPersonPreterite] : [])
        default:
            candidates = [.fullTable, .typeForm, .translateGerman] + (allowSpeaking ? [.speak, .translateSpeak] : [])
                + (hasPreterite ? [.typeFormPreterite, .fullTablePreterite] : [])
                + (hasPreterite && allowSpeaking ? [.speakPreterite] : [])
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

    /// Per kind: average progress over the verbs. Present and meaning games apply to every verb;
    /// a preterite game only to the verbs whose preterite is known (the others are left out, so
    /// it has no percentage until one is).
    public static func kindMastery(_ progress: [VerbProgress]) -> [VerbExerciseKind: Double] {
        var result: [VerbExerciseKind: Double] = [:]
        for kind in VerbExerciseKind.allCases {
            let applicable = progress.filter { kind.tense != .preterite || $0.hasPreterite }
            guard !applicable.isEmpty else { continue }
            let total = applicable.map { PathPlanner.progress(level: $0.streaks[kind] ?? 0) }.reduce(0, +)
            result[kind] = total / Double(applicable.count)
        }
        return result
    }

    /// Present tense only, for callers that do not know about the preterite.
    public static func kindMastery(_ streaks: [[VerbExerciseKind: Int]]) -> [VerbExerciseKind: Double] {
        kindMastery(streaks.map { VerbProgress(streaks: $0, hasPreterite: false) })
    }

    /// Average over all the kinds that apply, or over the given ones (translation / one tense).
    public static func mastery(_ progress: [VerbProgress], kinds subset: [VerbExerciseKind]? = nil) -> Double {
        let all = kindMastery(progress)
        let values = (subset ?? VerbExerciseKind.allCases).compactMap { all[$0] }
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    public static func mastery(_ streaks: [[VerbExerciseKind: Int]], kinds subset: [VerbExerciseKind]? = nil) -> Double {
        mastery(streaks.map { VerbProgress(streaks: $0, hasPreterite: false) }, kinds: subset)
    }
}

/// One verb's progress, as the percentages need it.
public struct VerbProgress: Hashable, Sendable {
    public var streaks: [VerbExerciseKind: Int]
    /// Whether the preterite games apply.
    public var hasPreterite: Bool

    public init(streaks: [VerbExerciseKind: Int], hasPreterite: Bool) {
        self.streaks = streaks
        self.hasPreterite = hasPreterite
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
        \(fieldGuide)

        Answer with JSON only, shaped as {"verbs": [ ... ]}.
        """
    }

    /// The fields of one verb, shared with the lookup of a single typed verb.
    static var fieldGuide: String {
        """
        - infinitive: the infinitive, e.g. "fahren", "aufstehen", "sich waschen".
        - english: the most common English translation, without "to".
        - forms: the present tense (Präsens) exactly as written after the pronoun, in this order: \
        ich, du, er/sie/es, wir, ihr, sie/Sie. Separable verbs with the prefix at the end \
        ("stehe auf"), reflexive verbs with the reflexive pronoun ("wasche mich", "wäschst dich").
        - preterite: the simple past (Präteritum) in the same order and style: ich, du, er/sie/es, \
        wir, ihr, sie/Sie ("fuhr", "fuhrst", "fuhr", "fuhren", "fuhrt", "fuhren"; "stand auf"; \
        "wusch mich"; "war", "hatte", "konnte").
        - group: one of "modal", "reflexive", "irregular", "stemChanging", "regular", for the verb \
        without its separable prefix (choose the first that applies in this order; sein, haben and \
        werden are "irregular", verbs changing vowel in du/er like fahren or sprechen are \
        "stemChanging", so "anfangen" is "stemChanging" and "sich anziehen" is "reflexive").
        - separablePrefix: for separable verbs the prefix that goes to the end of the sentence, \
        lowercase ("auf" for "aufstehen", "an" for "sich anziehen", "zurück" for "zurückkommen"); \
        null for verbs that are not separable, including inseparable prefixes (be-, ver-, er-, \
        ent-, ge-, zer-, emp-, miss-: "verstehen" is null).
        - note: in English, at most 8 words on what to watch out for (e.g. "a → ä with du and er"), null if regular.
        - emoji: exactly ONE emoji that evokes the verb.
        """
    }

    public static func userInstruction(for infinitives: [String]) -> String {
        "Conjugate in the present tense and the preterite: " + infinitives.joined(separator: ", ")
    }

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let forms: [String: Any] = ["type": "array", "items": string, "minItems": 6, "maxItems": 6]
        let group: [String: Any] = ["type": "string", "enum": VerbGroup.baseGroups.map(\.rawValue)]
        let properties: [String: Any] = [
            "infinitive": string, "english": string, "forms": forms, "preterite": forms, "group": group,
            "separablePrefix": nullableString, "note": nullableString, "emoji": string,
        ]
        let verb: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["infinitive", "english", "forms", "preterite", "group", "separablePrefix", "note", "emoji"],
            "additionalProperties": false,
        ]
        let verbs: [String: Any] = ["type": "array", "items": verb]
        let rootProperties: [String: Any] = ["verbs": verbs]
        return ["type": "object", "properties": rootProperties, "required": ["verbs"], "additionalProperties": false]
    }
}

/// Fills in a single verb the learner typed (text only, no photo).
public enum VerbLookupPrompt {
    public static func system() -> String {
        """
        You help an English-speaking learner conjugate German verbs. The learner typed one German \
        verb, possibly conjugated ("fährst"), with a typo, missing umlauts or wrong capitalization. \
        Find the verb they mean and describe it as exactly one verb, with its correct infinitive.

        Return:
        \(VerbExtractionPrompt.fieldGuide)

        Answer with JSON only, shaped as {"verbs": [ ... ]} with exactly one verb.
        """
    }

    public static func userInstruction(for verb: String) -> String {
        "Verb: \(verb)"
    }

    /// Same shape as the list conjugation, so the same parser reads it.
    public static var responseSchema: [String: Any] { VerbExtractionPrompt.responseSchema }

    /// The first verb the model returned, or nil when it found none.
    public static func parse(_ content: String) throws -> VerbEntry? {
        try VerbExtractionParser.parse(content).first
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
        let preterite = raw.preterite.map { clean($0) }
        guard !infinitive.isEmpty, !english.isEmpty, forms.count == Person.allCases.count,
              forms.allSatisfy({ !$0.isEmpty }) else { return nil }
        let note = clean(raw.note)
        var group = VerbGroup(rawValue: clean(raw.group)) ?? .regular
        var prefix = SeparableVerbs.clean(raw.separablePrefix)
        if group == .separable {
            // Older answers put separable verbs in their own group: keep the flag, not the group.
            group = .regular
            prefix = prefix ?? SeparableVerbs.inferPrefix(infinitive: infinitive, forms: forms)
        }
        return VerbEntry(
            infinitive: infinitive,
            english: english.hasPrefix("to ") ? String(english.dropFirst(3)) : english,
            forms: forms,
            // A partial preterite is worse than none: the verb just skips those games.
            preterite: preterite.count == Person.allCases.count && preterite.allSatisfy { !$0.isEmpty } ? preterite : [],
            group: group,
            note: note.isEmpty ? nil : note,
            emoji: clean(raw.emoji).first.map(String.init) ?? "🏃",
            separablePrefix: prefix
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
    let preterite: [String]
    let group: String?
    let separablePrefix: String?
    let note: String?
    let emoji: String?

    enum CodingKeys: String, CodingKey {
        case infinitive, english, forms, preterite, group, separablePrefix, note, emoji
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String? {
            (try? container.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        infinitive = string(.infinitive)
        english = string(.english)
        group = string(.group)
        separablePrefix = string(.separablePrefix)
        note = string(.note)
        emoji = string(.emoji)
        forms = Self.table(container, .forms)
        preterite = Self.table(container, .preterite)
    }

    /// A list in person order, or {"ich": "fahre", "du": "fährst", ...}.
    private static func table(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> [String] {
        if let list = try? container.decode([String].self, forKey: key) {
            return list
        }
        if let table = try? container.decode([String: String].self, forKey: key) {
            let keys = [["ich"], ["du"], ["er", "er/sie/es"], ["wir"], ["ihr"], ["sie", "sie/Sie", "Sie"]]
            return keys.map { options in options.lazy.compactMap { table[$0] }.first ?? "" }
        }
        return []
    }
}

// MARK: - Backup

public struct BackupVerb: Codable, Hashable, Sendable {
    public var id: UUID
    public var infinitive: String
    public var english: String
    public var forms: [String]
    /// Missing in backups made before the preterite was stored.
    public var preterite: [String]?
    public var group: VerbGroup
    public var note: String?
    public var emoji: String
    /// Missing in backups made before separable verbs had their own flag.
    public var separablePrefix: String?
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
        preterite = entry.preterite.isEmpty ? nil : entry.preterite
        group = entry.group
        note = entry.note
        emoji = entry.emoji
        separablePrefix = entry.separablePrefix
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.srs = srs
        self.streak = streak
        self.kindStreaks = Dictionary(uniqueKeysWithValues: kindStreaks.map { ($0.key.rawValue, $0.value) })
    }

    public var entry: VerbEntry {
        VerbEntry(id: id, infinitive: infinitive, english: english, forms: forms, preterite: preterite ?? [],
                  group: group, note: note, emoji: emoji, separablePrefix: separablePrefix)
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

// MARK: - Preterite for saved verbs

/// Adds the preterite to verbs saved before it was asked for: only the forms, text only.
public enum VerbPreteritePrompt {
    public static func system() -> String {
        """
        You help an English-speaking learner conjugate German verbs. You receive a list of German \
        infinitives. For every verb of the list, once, return its infinitive unchanged and its simple \
        past (Präteritum) exactly as written after the pronoun, in this order: ich, du, er/sie/es, wir, \
        ihr, sie/Sie. Separable verbs with the prefix at the end ("stand auf"), reflexive verbs with \
        the reflexive pronoun ("wusch mich", "wuschst dich").

        Answer with JSON only, shaped as {"verbs": [{"infinitive": "fahren", "preterite": \
        ["fuhr", "fuhrst", "fuhr", "fuhren", "fuhrt", "fuhren"]}]}.
        """
    }

    public static func userInstruction(for infinitives: [String]) -> String {
        "Preterite of: " + infinitives.joined(separator: ", ")
    }

    public static var responseSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let forms: [String: Any] = ["type": "array", "items": string, "minItems": 6, "maxItems": 6]
        let properties: [String: Any] = ["infinitive": string, "preterite": forms]
        let verb: [String: Any] = [
            "type": "object",
            "properties": properties,
            "required": ["infinitive", "preterite"],
            "additionalProperties": false,
        ]
        let verbs: [String: Any] = ["type": "array", "items": verb]
        let rootProperties: [String: Any] = ["verbs": verbs]
        return ["type": "object", "properties": rootProperties, "required": ["verbs"], "additionalProperties": false]
    }

    /// The six forms per verb, keyed by the infinitive's dedupe key; incomplete tables are left out.
    public static func parse(_ content: String) throws -> [String: [String]] {
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
        var result: [String: [String]] = [:]
        for raw in raws {
            let infinitive = (raw.infinitive ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let forms = raw.preterite.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !infinitive.isEmpty, forms.count == Person.allCases.count, forms.allSatisfy({ !$0.isEmpty }) else {
                continue
            }
            result[PhraseChecker.key(infinitive)] = result[PhraseChecker.key(infinitive)] ?? forms
        }
        return result
    }
}
