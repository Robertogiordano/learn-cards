import Foundation

/// The exercises of the separable-verbs practice.
public enum SeparableExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Infinitive shown: separable or not?
    case separableOrNot
    /// A sentence with the verb split: which infinitive is it?
    case findVerb
    /// English and infinitive: pick the right German sentence among four.
    case chooseSentence
    /// English and the pieces: write the German sentence.
    case writeSentence

    public var title: String {
        switch self {
        case .separableOrNot: return "Separable?"
        case .findVerb: return "Find the verb"
        case .chooseSentence: return "Choose the sentence"
        case .writeSentence: return "Write the sentence"
        }
    }

    public var caption: String {
        switch self {
        case .separableOrNot: return "aufstehen · verstehen"
        case .findVerb: return "steht … auf → aufstehen"
        case .chooseSentence: return "pick one of four"
        case .writeSentence: return "the whole sentence"
        }
    }
}

/// One exercise on a separable or non-separable verb.
public struct SeparableExercise: Hashable, Identifiable, Sendable {
    public static let separableOption = "Separable"
    public static let notSeparableOption = "Not separable"

    public var id: String { "\(kind.rawValue)|\(verb.dedupeKey)|\(sentence)" }
    public let kind: SeparableExerciseKind
    public let verb: VerbEntry
    /// The prefix that goes to the end ("auf"), nil when the verb is not separable.
    public let prefix: String?
    /// The German sentence of the exercise (shown in "find the verb", the solution otherwise).
    public let sentence: String
    /// Every sentence that counts as right when writing (subject or time first).
    public let accepted: [String]
    /// The sentence in English; nil without a usable translation.
    public let english: String?
    /// Choices to pick from; empty when writing.
    public let options: [String]
    /// The right choice; the sentence when writing.
    public let answer: String
    /// The pieces to use when writing ("Pedro", "um 8 Uhr").
    public let cues: [String]
    /// Why: where the prefix goes, or why there is none.
    public let explanation: String

    public var isSeparable: Bool { prefix != nil }
    public var emoji: String { verb.emoji }

    public func check(_ given: String) -> Verdict {
        switch kind {
        case .writeSentence: return PhraseChecker.check(given, accepted: accepted)
        default: return given == answer ? .correct : .wrong
        }
    }
}

public enum SeparablePractice {
    /// Prefixes that never separate (be-, ver-, …).
    static let inseparablePrefixes = ["miss", "emp", "ent", "ver", "zer", "be", "er", "ge"]

    /// Extra infinitives for "find the verb", when the learner has few verbs.
    static let fallbackInfinitives = ["aufstehen", "anrufen", "einkaufen", "fernsehen", "verstehen",
                                      "bekommen", "besuchen", "erklären", "kommen", "machen", "stehen"]

    /// The learner's verbs that fit in a plain sentence (not modal or reflexive).
    public static func canUse(verb: VerbEntry) -> Bool {
        WordOrderQuiz.canUse(verb: verb)
    }

    /// The prefix as the table shows it ("stehe auf"), else the stored one.
    public static func prefix(of verb: VerbEntry) -> String? {
        WordOrderVerb(form: verb.form(for: .ich))?.particle ?? verb.separablePrefix
    }

    /// "ver" for "verstehen": an inseparable prefix in front of a stem long enough to be a verb.
    public static func inseparablePrefix(of verb: VerbEntry) -> String? {
        guard prefix(of: verb) == nil else { return nil }
        let infinitive = verb.infinitive.lowercased()
        return inseparablePrefixes.first { infinitive.hasPrefix($0) && infinitive.count - $0.count >= 5 }
    }

    /// One line on the rule for this verb.
    public static func explanation(for verb: VerbEntry) -> String {
        let ich = "ich " + verb.form(for: .ich)
        if let prefix = prefix(of: verb) {
            return "\(verb.infinitive) is separable: \(prefix) goes to the end of the sentence (\(ich))."
        }
        if let prefix = inseparablePrefix(of: verb) {
            return "\(verb.infinitive) is not separable: \(prefix)- always stays on the verb (\(ich))."
        }
        return "\(verb.infinitive) has no separable prefix: the verb stays whole (\(ich))."
    }

    /// `count` exercises from the learner's verbs, separable and not in turns; `kind` nil mixes them.
    public static func make<R: RandomNumberGenerator>(
        count: Int, kind: SeparableExerciseKind?, verbs: [VerbEntry], using rng: inout R
    ) -> [SeparableExercise] {
        let usable = verbs.filter(canUse(verb:))
        let separable = usable.filter { prefix(of: $0) != nil }.shuffled(using: &rng)
        let plain = usable.filter { prefix(of: $0) == nil }.shuffled(using: &rng)
        guard !separable.isEmpty else { return [] }

        var result: [SeparableExercise] = []
        var seen = Set<String>()
        var separableIndex = 0, plainIndex = 0
        for attempt in 0..<(count * 4) where result.count < count {
            let chosenKind = kind ?? SeparableExerciseKind.allCases[attempt % SeparableExerciseKind.allCases.count]
            // Separable verbs are the point; the others come up about one time in three.
            let pickPlain = !plain.isEmpty && attempt % 3 == 2
            let verb: VerbEntry
            if pickPlain {
                verb = plain[plainIndex % plain.count]
                plainIndex += 1
            } else {
                verb = separable[separableIndex % separable.count]
                separableIndex += 1
            }
            guard let exercise = exercise(kind: chosenKind, verb: verb, pool: usable, using: &rng),
                  seen.insert(exercise.id).inserted else { continue }
            result.append(exercise)
        }
        result.shuffle(using: &rng)
        return result
    }

    static func exercise<R: RandomNumberGenerator>(
        kind: SeparableExerciseKind, verb: VerbEntry, pool: [VerbEntry], using rng: inout R
    ) -> SeparableExercise? {
        guard let built = SeparableSentence.make(verb: verb, using: &rng) else { return nil }
        let prefix = prefix(of: verb)
        let options: [String]
        let answer: String
        switch kind {
        case .separableOrNot:
            options = [SeparableExercise.separableOption, SeparableExercise.notSeparableOption]
            answer = prefix == nil ? SeparableExercise.notSeparableOption : SeparableExercise.separableOption
        case .findVerb:
            options = infinitiveOptions(for: verb, prefix: prefix, pool: pool, using: &rng)
            answer = verb.infinitive
        case .chooseSentence:
            let wrong = built.wrongSentences(verb: verb, using: &rng)
            guard wrong.count >= 2 else { return nil }
            options = (wrong.prefix(3) + [built.sentence]).shuffled(using: &rng)
            answer = built.sentence
        case .writeSentence:
            options = []
            answer = built.sentence
        }
        return SeparableExercise(kind: kind, verb: verb, prefix: prefix, sentence: built.sentence,
                                 accepted: built.accepted, english: built.english, options: options,
                                 answer: answer, cues: built.cues, explanation: explanation(for: verb))
    }

    /// The right infinitive, the same verb without its prefix ("stehen" for "aufstehen"), then others.
    static func infinitiveOptions<R: RandomNumberGenerator>(
        for verb: VerbEntry, prefix: String?, pool: [VerbEntry], using rng: inout R
    ) -> [String] {
        var keys: Set<String> = [verb.dedupeKey]
        var distractors: [String] = []
        func add(_ infinitive: String) {
            guard distractors.count < 3, keys.insert(PhraseChecker.key(infinitive)).inserted else { return }
            distractors.append(infinitive)
        }
        let infinitive = verb.infinitive.lowercased()
        if let prefix, infinitive.hasPrefix(prefix), infinitive.count > prefix.count + 2 {
            add(String(infinitive.dropFirst(prefix.count)))
        }
        // A verb with the same stem and another prefix: "verstehen" next to "aufstehen".
        let stem = String(infinitive.dropFirst(prefix?.count ?? inseparablePrefix(of: verb)?.count ?? 0))
        let candidates = pool.map(\.infinitive) + fallbackInfinitives
        for other in candidates.shuffled(using: &rng) where other.lowercased().hasSuffix(stem) {
            add(other)
        }
        for other in pool.shuffled(using: &rng) { add(other.infinitive) }
        for other in fallbackInfinitives.shuffled(using: &rng) { add(other) }
        return (distractors + [verb.infinitive]).shuffled(using: &rng)
    }
}

/// A sentence with the verb in place, kept in pieces so wrong versions can be made from it.
struct SeparableSentence {
    /// The pieces of the shown sentence; the finite verb and the prefix at known places.
    let chunks: [String]
    let finiteIndex: Int
    let particleIndex: Int?
    let punctuation: String
    let accepted: [String]
    let english: String?
    let cues: [String]
    let subject: WordOrderSubject

    var sentence: String { WordOrderExercise.sentence(from: chunks, punctuation: punctuation) }

    static func make<R: RandomNumberGenerator>(verb: VerbEntry, using rng: inout R) -> SeparableSentence? {
        let isQuestion = Int.random(in: 0..<3, using: &rng) == 0
        let subjects = isQuestion ? WordOrderSubject.askable : WordOrderSubject.all
        guard let subject = subjects.randomElement(using: &rng),
              let split = WordOrderVerb(form: verb.form(for: subject.person)),
              let time = WordOrderQuiz.times.randomElement(using: &rng) else { return nil }
        let tail = [split.particle].compactMap { $0 }
        let englishVerb = EnglishVerb(english: verb.english)
        let third = subject.isThirdPersonSingular
        let timeEnglish = WordOrderQuiz.englishPhrases[time] ?? time

        let orders: [[String]]
        let english: String?
        let punctuation: String
        if isQuestion {
            orders = [[split.finite, subject.text, time] + tail]
            english = englishVerb.map {
                EnglishGloss.capitalized("\($0.question(subject: subject.english, thirdPerson: third, negated: false)) \(timeEnglish)?")
            }
            punctuation = "?"
        } else {
            orders = [[subject.text, split.finite, time] + tail, [time, split.finite, subject.text] + tail]
            english = englishVerb.map {
                EnglishGloss.capitalized("\(subject.english) \($0.present(thirdPerson: third)) \(timeEnglish).")
            }
            punctuation = "."
        }
        let shown = orders[0]
        return SeparableSentence(
            chunks: shown,
            finiteIndex: isQuestion ? 0 : 1,
            particleIndex: split.particle == nil ? nil : shown.count - 1,
            punctuation: punctuation,
            accepted: orders.map { WordOrderExercise.sentence(from: $0, punctuation: punctuation) },
            english: english,
            cues: [subject.text, time],
            subject: subject
        )
    }

    /// Typical mistakes, never one of the accepted sentences: the prefix left on the verb or
    /// in the wrong place, a prefix split off that never separates, the wrong person, the infinitive.
    func wrongSentences<R: RandomNumberGenerator>(verb: VerbEntry, using rng: inout R) -> [String] {
        var candidates: [[String]] = []
        let finite = chunks[finiteIndex]
        if let particleIndex {
            let particle = chunks[particleIndex]
            var joined = chunks
            joined[finiteIndex] = particle + finite
            joined.remove(at: particleIndex)
            candidates.append(joined)
            var early = chunks
            early.remove(at: particleIndex)
            early.insert(particle, at: finiteIndex + 1)
            candidates.append(early)
        } else if let prefix = SeparablePractice.inseparablePrefix(of: verb), finite.lowercased().hasPrefix(prefix) {
            var split = chunks
            split[finiteIndex] = String(finite.dropFirst(prefix.count))
            split.append(prefix)
            candidates.append(split)
        }
        // Another person's form, prefix kept where it belongs.
        for person in Person.allCases.shuffled(using: &rng) {
            guard let other = WordOrderVerb(form: verb.form(for: person)),
                  PhraseChecker.key(other.finite) != PhraseChecker.key(finite) else { continue }
            var wrong = chunks
            wrong[finiteIndex] = other.finite
            candidates.append(wrong)
        }
        var bare = chunks
        bare[finiteIndex] = verb.infinitive
        if let particleIndex { bare.remove(at: particleIndex) }
        candidates.append(bare)

        var keys = Set(accepted.map(PhraseChecker.key))
        var result: [String] = []
        for chunks in candidates {
            let text = WordOrderExercise.sentence(from: chunks, punctuation: punctuation)
            if keys.insert(PhraseChecker.key(text)).inserted { result.append(text) }
        }
        // The prefix mistakes first: they are what the exercise is about.
        let structural = Array(result.prefix(particleIndex == nil ? 1 : 2))
        return structural + result.dropFirst(structural.count).shuffled(using: &rng)
    }
}
