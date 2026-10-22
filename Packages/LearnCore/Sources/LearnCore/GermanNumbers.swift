import Foundation

/// German number words, 0 to 1,000,000, and back.
public enum GermanNumbers {
    public static let maximum = 1_000_000

    private static let small = [
        "null", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun",
        "zehn", "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn", "siebzehn", "achtzehn", "neunzehn",
    ]
    private static let tens = ["", "", "zwanzig", "dreißig", "vierzig", "fünfzig", "sechzig", "siebzig", "achtzig", "neunzig"]

    /// Canonical spelling, one word as German writes it: 21 → "einundzwanzig",
    /// 100 → "einhundert", 1001 → "eintausendeins", 1,000,000 → "eine Million".
    public static func spell(_ number: Int) -> String {
        precondition((0...maximum).contains(number), "Number out of range")
        if number == maximum { return "eine Million" }
        if number < 1000 { return below1000(number) }
        let thousands = number / 1000, rest = number % 1000
        return prefix(thousands) + "tausend" + (rest > 0 ? below1000(rest) : "")
    }

    private static func below100(_ number: Int) -> String {
        if number < 20 { return small[number] }
        let unit = number % 10, ten = number / 10
        guard unit > 0 else { return tens[ten] }
        return (unit == 1 ? "ein" : small[unit]) + "und" + tens[ten]
    }

    private static func below1000(_ number: Int) -> String {
        let hundreds = number / 100, rest = number % 100
        guard hundreds > 0 else { return below100(rest) }
        return prefix(hundreds) + "hundert" + (rest > 0 ? below100(rest) : "")
    }

    /// The form used before "hundert"/"tausend": "eins" becomes "ein" (einhundert, hunderteintausend).
    private static func prefix(_ number: Int) -> String {
        let word = below1000(number)
        return word.hasSuffix("eins") ? String(word.dropLast()) : word
    }

    // MARK: - Reading numbers

    /// Lowercase, umlauts and ß folded, everything but letters and digits removed.
    static func fold(_ text: String) -> String {
        AnswerChecker.foldGerman(text.precomposedStringWithCanonicalMapping.lowercased())
            .filter { $0.isLetter || $0.isNumber }
    }

    private static let foldedSmall: [String: Int] = {
        var table: [String: Int] = [:]
        for (value, word) in small.enumerated() { table[AnswerChecker.foldGerman(word)] = value }
        table["ein"] = 1
        table["eine"] = 1
        return table
    }()

    private static let foldedTens: [String: Int] = {
        var table: [String: Int] = [:]
        for (index, word) in tens.enumerated() where !word.isEmpty { table[AnswerChecker.foldGerman(word)] = index * 10 }
        return table
    }()

    /// Reads digits ("47", "1.000") or German words ("siebenundvierzig", "sieben und vierzig",
    /// "hundert", "einhundert"). Returns nil when the text is not a number up to a million.
    public static func parse(_ text: String) -> Int? {
        let compact = text.filter { !$0.isWhitespace && $0 != "." && $0 != "'" }
        if !compact.isEmpty, compact.allSatisfy(\.isNumber) {
            guard let value = Int(compact), value <= maximum else { return nil }
            return value
        }
        let folded = fold(text)
        guard !folded.isEmpty, !folded.contains(where: \.isNumber) else { return nil }
        return parseWords(folded)
    }

    private static func parseWords(_ text: String) -> Int? {
        for suffix in ["millionen", "million"] where text.hasSuffix(suffix) {
            let count = String(text.dropLast(suffix.count))
            return count.isEmpty || count == "ein" || count == "eine" ? maximum : nil
        }
        if let range = text.range(of: "tausend") {
            let left = String(text[..<range.lowerBound]), right = String(text[range.upperBound...])
            guard let thousands = left.isEmpty ? 1 : parseBelow1000(left), thousands > 0,
                  let rest = right.isEmpty ? 0 : parseBelow1000(right) else { return nil }
            let value = thousands * 1000 + rest
            return value < maximum ? value : nil
        }
        return parseBelow1000(text)
    }

    private static func parseBelow1000(_ text: String) -> Int? {
        if let range = text.range(of: "hundert") {
            let left = String(text[..<range.lowerBound]), right = String(text[range.upperBound...])
            guard let hundreds = left.isEmpty ? 1 : foldedSmall[left], (1...9).contains(hundreds),
                  let rest = right.isEmpty ? 0 : parseBelow100(right) else { return nil }
            return hundreds * 100 + rest
        }
        return parseBelow100(text)
    }

    private static func parseBelow100(_ text: String) -> Int? {
        if let value = foldedSmall[text], text != "eine" { return value }
        if let value = foldedTens[text] { return value }
        guard let range = text.range(of: "und") else { return nil }
        let unitWord = String(text[..<range.lowerBound]), tenWord = String(text[range.upperBound...])
        guard let unit = unitWord == "eins" ? nil : foldedSmall[unitWord], (1...9).contains(unit),
              let ten = foldedTens[tenWord] else { return nil }
        return ten + unit
    }

    // MARK: - Display

    /// Digits grouped the German way: 1.000, 25.300.
    public static func digits(_ number: Int) -> String {
        var groups: [String] = []
        var rest = number
        repeat {
            let group = rest % 1000
            rest /= 1000
            groups.insert(rest > 0 ? String(format: "%03d", group) : String(group), at: 0)
        } while rest > 0
        return groups.joined(separator: ".")
    }
}
