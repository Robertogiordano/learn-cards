import Foundation

/// Just enough English grammar to translate the generated practice sentences, from the
/// translations the learner already stored ("to cook", "printer").
public enum EnglishGloss {
    /// The first meaning of a stored translation, without "to" or notes: "to cook, to make (food)" → "cook".
    public static func verbBase(_ english: String) -> String? {
        let base = firstMeaning(english)
        let words = base.split(separator: " ").map(String.init)
        let trimmed = words.first?.lowercased() == "to" ? words.dropFirst().joined(separator: " ") : base
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "printer" → "a printer", "the apple" → "an apple".
    public static func indefinite(_ english: String) -> String? {
        var noun = firstMeaning(english)
        for article in ["the ", "a ", "an "] where noun.lowercased().hasPrefix(article) {
            noun = String(noun.dropFirst(article.count))
            break
        }
        guard let first = noun.lowercased().first else { return nil }
        return ("aeiou".contains(first) ? "an " : "a ") + noun
    }

    /// "cook" → "cooks", "watch TV" → "watches TV", "get up" → "gets up".
    public static func thirdPerson(_ base: String) -> String {
        var words = base.split(separator: " ").map(String.init)
        guard let verb = words.first else { return base }
        let irregular = ["be": "is", "have": "has", "do": "does", "go": "goes"]
        let inflected: String
        if let form = irregular[verb.lowercased()] {
            inflected = form
        } else if ["s", "x", "z", "ch", "sh", "o"].contains(where: verb.hasSuffix) {
            inflected = verb + "es"
        } else if verb.hasSuffix("y"), let before = verb.dropLast().last, !"aeiou".contains(before) {
            inflected = verb.dropLast() + "ies"
        } else {
            inflected = verb + "s"
        }
        words[0] = inflected
        return words.joined(separator: " ")
    }

    private static func firstMeaning(_ text: String) -> String {
        var meaning = text.split(whereSeparator: { ",;/".contains($0) }).first.map(String.init) ?? ""
        if let open = meaning.firstIndex(of: "(") {
            meaning = String(meaning[..<open])
        }
        return meaning.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// An English verb in the simple present, or "would like" for möchten.
struct EnglishVerb: Hashable, Sendable {
    let base: String
    let isModal: Bool

    init(base: String, isModal: Bool = false) {
        self.base = base
        self.isModal = isModal
    }

    init?(english: String) {
        guard let base = EnglishGloss.verbBase(english) else { return nil }
        self.init(base: base)
    }

    static let wouldLike = EnglishVerb(base: "like", isModal: true)

    /// "I cook", "she cooks", "I would like".
    func present(thirdPerson: Bool) -> String {
        if isModal { return "would \(base)" }
        return thirdPerson ? EnglishGloss.thirdPerson(base) : base
    }

    /// "I don't cook", "she doesn't cook", "I wouldn't like".
    func negative(thirdPerson: Bool) -> String {
        if isModal { return "wouldn't \(base)" }
        return "\(thirdPerson ? "doesn't" : "don't") \(base)"
    }

    /// The emphatic yes that answers doch: "I do cook", "I would like".
    func emphatic(thirdPerson: Bool) -> String {
        if isModal { return "would \(base)" }
        return "\(thirdPerson ? "does" : "do") \(base)"
    }

    /// "Do you cook", "Don't you cook", "Would you like" (rest of the question follows).
    func question(subject: String, thirdPerson: Bool, negated: Bool) -> String {
        let auxiliary = isModal ? "Would" : (thirdPerson ? "Does" : "Do")
        let asked = negated ? (isModal ? "Wouldn't" : auxiliary + "n't") : auxiliary
        return "\(asked) \(subject) \(base)"
    }
}
