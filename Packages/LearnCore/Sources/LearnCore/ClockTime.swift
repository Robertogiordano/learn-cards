import Foundation

/// A time of day, minute precision.
public struct ClockTime: Hashable, Codable, Sendable, Comparable {
    public var hour: Int
    public var minute: Int

    /// Wraps around: hour 24 is 0, minute -15 is the previous hour's 45.
    public init(hour: Int, minute: Int) {
        let total = ((hour * 60 + minute) % 1440 + 1440) % 1440
        self.hour = total / 60
        self.minute = total % 60
    }

    public init(minuteOfDay: Int) {
        self.init(hour: 0, minute: minuteOfDay)
    }

    public var minuteOfDay: Int { hour * 60 + minute }

    /// 1...12, as on a clock face.
    public var hour12: Int { hour % 12 == 0 ? 12 : hour % 12 }

    /// "15:20", "07:05".
    public var digital: String { String(format: "%02d:%02d", hour, minute) }

    /// "3:20", as said in everyday speech (no morning or afternoon).
    public var digital12: String { String(format: "%d:%02d", hour12, minute) }

    public func adding(minutes: Int) -> ClockTime { ClockTime(hour: hour, minute: minute + minutes) }

    /// Same position on a clock face: 3:20 and 15:20.
    public func sameOnClockFace(as other: ClockTime) -> Bool {
        hour % 12 == other.hour % 12 && minute == other.minute
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minuteOfDay < rhs.minuteOfDay }
}

/// How a time is said: the official 24-hour way ("fünfzehn Uhr zwanzig", timetables, the radio)
/// or the everyday way on a clock face ("zwanzig nach drei", "halb vier").
public enum TimeRegister: String, Codable, Hashable, Sendable {
    case formal, informal
}

/// German time expressions, both ways.
public enum GermanTime {
    // MARK: - Saying a time

    /// The hour as said alone: "eins" (Viertel nach eins), "zwölf".
    static func hourWord(_ hour12: Int) -> String { GermanNumbers.spell(hour12) }

    /// The hour before "Uhr": "ein Uhr", not "eins Uhr".
    static func hourBeforeUhr(_ hour: Int) -> String { hour == 1 ? "ein" : GermanNumbers.spell(hour) }

    /// Official: "fünfzehn Uhr zwanzig", "ein Uhr", "null Uhr fünf".
    public static func formal(_ time: ClockTime) -> String {
        let base = "\(hourBeforeUhr(time.hour)) Uhr"
        return time.minute == 0 ? base : "\(base) \(GermanNumbers.spell(time.minute))"
    }

    /// Everyday, the most common phrasing: "Viertel nach drei", "halb vier",
    /// "fünf vor halb vier", "zwanzig nach drei".
    public static func informal(_ time: ClockTime) -> String {
        informalVariants(time)[0]
    }

    /// Every common everyday phrasing, the preferred one first. Minutes 20 and 40 have two:
    /// "zwanzig nach drei" / "zehn vor halb vier", "zwanzig vor vier" / "zehn nach halb vier".
    public static func informalVariants(_ time: ClockTime) -> [String] {
        let hour = hourWord(time.hour12)
        let next = hourWord(time.adding(minutes: 60).hour12)
        let m = time.minute
        switch m {
        case 0: return ["\(hourBeforeUhr(time.hour12)) Uhr"]
        case 15: return ["Viertel nach \(hour)"]
        case 30: return ["halb \(next)"]
        case 45: return ["Viertel vor \(next)"]
        case 20: return ["zwanzig nach \(hour)", "zehn vor halb \(next)"]
        case 40: return ["zwanzig vor \(next)", "zehn nach halb \(next)"]
        case 25: return ["fünf vor halb \(next)"]
        case 35: return ["fünf nach halb \(next)"]
        case 1..<30: return ["\(GermanNumbers.spell(m)) nach \(hour)"]
        default: return ["\(GermanNumbers.spell(60 - m)) vor \(next)"]
        }
    }

    /// The everyday phrasing with a capital, as at the start of a sentence: "Halb vier."
    public static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Reading a time

    /// A time read from text, with the register it was said in.
    public struct Reading: Hashable, Sendable {
        public let time: ClockTime
        /// Formal readings fix the hour; informal ones only the position on the clock face.
        public let registers: Set<TimeRegister>
        /// Read from digits ("15:20"), not words.
        public let isDigital: Bool
    }

    private static let fillers: Set<String> = ["es", "ist", "um", "jetzt", "genau", "minuten", "minute", "gleich"]

    /// Reads "Viertel nach drei", "halb vier", "zehn vor halb vier", "fünfzehn Uhr zwanzig",
    /// "15 Uhr 20", "15:20", also after "Es ist" or "um"; umlauts, ß and capitals do not matter.
    /// Regional "viertel vier" (3:15) and "dreiviertel vier" (3:45) count too.
    public static func parse(_ text: String) -> [Reading] {
        var results: [Reading] = []
        if let digital = parseDigits(text) {
            results.append(Reading(time: digital, registers: [.formal, .informal], isDigital: true))
        }
        let tokens = AnswerChecker.normalize(text)
            .split(separator: " ")
            .map { AnswerChecker.foldGerman(String($0)) }
            .filter { !fillers.contains($0) }
        guard !tokens.isEmpty else { return results }

        func number(_ token: String) -> Int? {
            if token == "ein" || token == "eine" { return 1 }
            return GermanNumbers.parse(token)
        }
        let isDigitToken: (String) -> Bool = { $0.allSatisfy(\.isNumber) }
        let n = tokens.map(number)
        func informal(_ hour: Int, _ minute: Int) -> Reading? {
            guard (1...12).contains(hour) || (hour == 0) else { return nil }
            return Reading(time: ClockTime(hour: hour, minute: minute), registers: [.informal],
                           isDigital: tokens.contains(where: isDigitToken))
        }

        switch tokens.count {
        case 1:
            // "drei" → 3:00 on the clock face.
            if let h = n[0], (1...12).contains(h) {
                results.append(Reading(time: ClockTime(hour: h, minute: 0), registers: [.informal],
                                       isDigital: isDigitToken(tokens[0])))
            }
        case 2:
            if tokens[1] == "uhr", let h = n[0], (0...24).contains(h) {
                // "drei Uhr" is both; "fünfzehn Uhr" only formal.
                let registers: Set<TimeRegister> = (1...12).contains(h) ? [.formal, .informal] : [.formal]
                results.append(Reading(time: ClockTime(hour: h, minute: 0), registers: registers,
                                       isDigital: isDigitToken(tokens[0])))
            } else if tokens[0] == "halb", let h = n[1] {
                informal(h - 1, 30).map { results.append($0) }
            } else if tokens[0] == "viertel", let h = n[1] {
                informal(h - 1, 15).map { results.append($0) }
            } else if tokens[0] == "dreiviertel", let h = n[1] {
                informal(h - 1, 45).map { results.append($0) }
            } else if let h = n[0], let m = n[1], isDigitToken(tokens[0]), isDigitToken(tokens[1]),
                      (0...24).contains(h), (0...59).contains(m) {
                // "15 20" from a transcript of "15:20".
                results.append(Reading(time: ClockTime(hour: h, minute: m), registers: [.formal, .informal], isDigital: true))
            }
        case 3:
            if tokens[1] == "uhr", let h = n[0], let m = n[2], (0...24).contains(h), (0...59).contains(m) {
                results.append(Reading(time: ClockTime(hour: h, minute: m), registers: [.formal],
                                       isDigital: tokens.contains(where: isDigitToken)))
            } else if tokens[0] == "viertel", tokens[1] == "nach", let h = n[2] {
                informal(h, 15).map { results.append($0) }
            } else if tokens[0] == "viertel", tokens[1] == "vor", let h = n[2] {
                informal(h - 1, 45).map { results.append($0) }
            } else if let m = n[0], (1...29).contains(m), let h = n[2] {
                if tokens[1] == "nach" { informal(h, m).map { results.append($0) } }
                if tokens[1] == "vor" { informal(h - 1, 60 - m).map { results.append($0) } }
            }
        case 4:
            if tokens[2] == "halb", let m = n[0], (1...29).contains(m), let h = n[3] {
                if tokens[1] == "nach" { informal(h - 1, 30 + m).map { results.append($0) } }
                if tokens[1] == "vor" { informal(h - 1, 30 - m).map { results.append($0) } }
            }
        default:
            break
        }
        return results
    }

    /// "15:20", "15.20", "7:05", "07:05 Uhr", "1520" is not accepted.
    public static func parseDigits(_ text: String) -> ClockTime? {
        var compact = text.lowercased().filter { !$0.isWhitespace }
        if compact.hasSuffix("uhr") { compact.removeLast(3) }
        let parts = compact.split(whereSeparator: { $0 == ":" || $0 == "." }).map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts[1].count == 2, parts[0].count <= 2,
              let h = Int(parts[0]), let m = Int(parts[1]), (0...24).contains(h), (0...59).contains(m) else { return nil }
        return ClockTime(hour: h, minute: m)
    }

    // MARK: - Checking answers

    /// The everyday phrasing in words: any common variant counts; one typo is almost.
    /// A formal answer ("fünfzehn Uhr zwanzig") or digits are wrong here.
    public static func checkInformal(_ given: String, time: ClockTime) -> Verdict {
        guard !given.contains(where: \.isNumber) else { return .wrong }
        if parse(given).contains(where: { $0.registers.contains(.informal) && $0.time.sameOnClockFace(as: time) }) {
            return .correct
        }
        return closeTo(given, any: informalVariants(time)) ? .almost : .wrong
    }

    /// The official phrasing in words: the hour must be the 24-hour one.
    public static func checkFormal(_ given: String, time: ClockTime) -> Verdict {
        guard !given.contains(where: \.isNumber) else { return .wrong }
        if parse(given).contains(where: { $0.registers.contains(.formal) && $0.time == time }) {
            return .correct
        }
        return closeTo(given, any: [formal(time)]) ? .almost : .wrong
    }

    /// Digits typed for a time: "7:45", "07.45"; with `clockFace` 19:45 counts too.
    public static func checkDigits(_ given: String, time: ClockTime, clockFace: Bool) -> Verdict {
        guard let read = parseDigits(given) else { return .wrong }
        if read == time { return .correct }
        return clockFace && read.sameOnClockFace(as: time) ? .correct : .wrong
    }

    /// Said aloud, either way: formal needs the right hour, informal the right clock position.
    public static func checkSpoken(_ transcripts: [String], time: ClockTime) -> Verdict {
        let matches = transcripts.contains { transcript in
            parse(transcript).contains { reading in
                reading.time == time || (reading.registers.contains(.informal) && reading.time.sameOnClockFace(as: time))
            }
        }
        return matches ? .correct : .wrong
    }

    private static func closeTo(_ given: String, any expected: [String]) -> Bool {
        let folded = GermanNumbers.fold(given)
        guard folded.count >= 4 else { return false }
        return expected.contains { phrase in
            let target = GermanNumbers.fold(phrase)
            return AnswerChecker.levenshtein(folded, target) <= (target.count > 12 ? 2 : 1)
        }
    }
}

// MARK: - Practice

/// Which minutes come up.
public enum TimeLevel: Int, CaseIterable, Codable, Hashable, Sendable {
    case halfHours = 1, quarters, fiveMinutes, anyMinute

    public var title: String {
        switch self {
        case .halfHours: return "Full and half hours"
        case .quarters: return "Quarters"
        case .fiveMinutes: return "Every 5 minutes"
        case .anyMinute: return "Any minute"
        }
    }

    public var shortTitle: String {
        switch self {
        case .halfHours: return ":00 :30"
        case .quarters: return "¼"
        case .fiveMinutes: return "5 min"
        case .anyMinute: return "1 min"
        }
    }

    /// Minutes for everyday phrasings: never finer than 5, as people round on a clock.
    var informalMinutes: [Int] {
        switch self {
        case .halfHours: return [0, 30]
        case .quarters: return [0, 15, 30, 45]
        case .fiveMinutes, .anyMinute: return Array(stride(from: 0, to: 60, by: 5))
        }
    }

    var formalMinutes: [Int] {
        self == .anyMinute ? Array(0..<60) : informalMinutes
    }
}

public enum TimeExerciseKind: String, CaseIterable, Codable, Hashable, Sendable {
    /// Clock face shown, pick the everyday phrasing among four.
    case readClock
    /// Hear the time, pick it among four.
    case listenChoice
    /// Clock face shown, write it the everyday way.
    case writeInformal
    /// Digital 24-hour time shown, write it the official way.
    case writeFormal
    /// Everyday phrasing shown, type the digits.
    case toDigits
    /// Clock shown, say the time.
    case speak

    public var title: String {
        switch self {
        case .readClock: return "Read the clock"
        case .listenChoice: return "Listen and choose"
        case .writeInformal: return "Write it (everyday)"
        case .writeFormal: return "Write it (official)"
        case .toDigits: return "Words → digits"
        case .speak: return "Say the time"
        }
    }

    /// The register trained: the time and options are drawn for it.
    public var register: TimeRegister {
        self == .writeFormal ? .formal : .informal
    }

    public var isTyping: Bool { self == .writeInformal || self == .writeFormal || self == .toDigits }
}

public struct TimeExercise: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let kind: TimeExerciseKind
    public let level: TimeLevel
    public let time: ClockTime
    /// Choice options: phrasings (readClock) or digital times (listenChoice).
    public let options: [String]
    public let answer: String

    public init(id: UUID = UUID(), kind: TimeExerciseKind, level: TimeLevel, time: ClockTime,
                options: [String] = [], answer: String) {
        self.id = id
        self.kind = kind
        self.level = level
        self.time = time
        self.options = options
        self.answer = answer
    }

    /// What is said aloud for this time: "Es ist halb vier."
    public var spoken: String {
        kind == .writeFormal ? "Es ist \(GermanTime.formal(time))." : "Es ist \(GermanTime.informal(time))."
    }
}

public enum TimeQuiz {
    public static let mistakeShare = 0.3

    public static func make<R: RandomNumberGenerator>(
        kind: TimeExerciseKind,
        level: TimeLevel,
        stats: TimeStats,
        using rng: inout R
    ) -> TimeExercise {
        let minutes = kind.register == .formal ? level.formalMinutes : level.informalMinutes
        let missed = stats.mistakes(in: level).map(ClockTime.init(minuteOfDay:))
            .filter { minutes.contains($0.minute) }
        let time: ClockTime
        if let pick = missed.randomElement(using: &rng), Double.random(in: 0..<1, using: &rng) < mistakeShare {
            time = pick
        } else {
            // Everyday times on the clock face: 12-hour, shown in the day (7:00–18:59) or not at all.
            let hour = kind.register == .formal ? Int.random(in: 0...23, using: &rng) : Int.random(in: 7...18, using: &rng)
            time = ClockTime(hour: hour, minute: minutes.randomElement(using: &rng) ?? 0)
        }

        switch kind {
        case .readClock:
            let distractors = confusable(with: time, level: level, using: &rng).map(GermanTime.informal)
            var options = Array(distractors.prefix(3)) + [GermanTime.informal(time)]
            options.shuffle(using: &rng)
            return TimeExercise(kind: kind, level: level, time: time, options: options, answer: GermanTime.informal(time))
        case .listenChoice:
            let distractors = confusable(with: time, level: level, using: &rng).map(\.digital12)
            var options = Array(distractors.prefix(3)) + [time.digital12]
            options.shuffle(using: &rng)
            return TimeExercise(kind: kind, level: level, time: time, options: options, answer: time.digital12)
        case .writeFormal:
            return TimeExercise(kind: kind, level: level, time: time, answer: GermanTime.formal(time))
        case .toDigits:
            return TimeExercise(kind: kind, level: level, time: time, answer: time.digital12)
        case .writeInformal, .speak:
            return TimeExercise(kind: kind, level: level, time: time, answer: GermanTime.informal(time))
        }
    }

    /// Times that really get confused, on the clock face: "halb vier" is 3:30, not 4:30;
    /// vor and nach swapped (Viertel nach drei ↔ Viertel vor drei, fünf vor halb ↔ fünf nach halb);
    /// then neighbours. Each differs from the others on the clock face.
    public static func confusable<R: RandomNumberGenerator>(with time: ClockTime, level: TimeLevel,
                                                            using rng: inout R) -> [ClockTime] {
        let m = time.minute
        var tricky: [ClockTime] = []
        if (20...40).contains(m) {
            // The "halb" trap: an hour later.
            tricky.append(time.adding(minutes: 60))
        }
        if m != 0 && m != 30 {
            // Mirror around the reference: the full hour for 5–15 and 45–55, the half hour for 25–35.
            let reference = (20...40).contains(m) ? 30 : (m < 30 ? 0 : 60)
            tricky.append(time.adding(minutes: 2 * (reference - m)))
        } else {
            tricky.append(time.adding(minutes: -60))
        }
        let step = level.informalMinutes.count > 4 ? 5 : (level == .quarters ? 15 : 30)
        let near = [time.adding(minutes: step), time.adding(minutes: -step), time.adding(minutes: 60),
                    time.adding(minutes: -60), time.adding(minutes: 2 * step)]
        var result: [ClockTime] = []
        for candidate in tricky + near.shuffled(using: &rng)
        where !candidate.sameOnClockFace(as: time) && !result.contains(where: { $0.sameOnClockFace(as: candidate) }) {
            result.append(candidate)
        }
        return result
    }
}

/// Time practice history: the last answers per level and kind, and recently missed times.
public struct TimeStats: Codable, Equatable, Sendable {
    public static let window = 20
    public static let maximumMistakes = 10

    public var results: [String: [Bool]]
    /// Minutes of the day, per level.
    public var mistakes: [String: [Int]]

    public init(results: [String: [Bool]] = [:], mistakes: [String: [Int]] = [:]) {
        self.results = results
        self.mistakes = mistakes
    }

    public var isEmpty: Bool { results.isEmpty }

    private static func key(_ level: TimeLevel, _ kind: TimeExerciseKind) -> String {
        "\(level.rawValue).\(kind.rawValue)"
    }

    /// Right answers among the last 20, over 20.
    public func progress(_ level: TimeLevel, _ kind: TimeExerciseKind) -> Double {
        let recent = results[Self.key(level, kind)] ?? []
        return Double(recent.filter { $0 }.count) / Double(Self.window)
    }

    public func progress(_ level: TimeLevel) -> Double {
        let kinds = TimeExerciseKind.allCases
        return kinds.map { progress(level, $0) }.reduce(0, +) / Double(kinds.count)
    }

    public func mistakes(in level: TimeLevel) -> [Int] {
        mistakes[String(level.rawValue)] ?? []
    }

    public mutating func record(_ correct: Bool, time: ClockTime, level: TimeLevel, kind: TimeExerciseKind) {
        let key = Self.key(level, kind)
        results[key, default: []].append(correct)
        if let count = results[key]?.count, count > Self.window {
            results[key]?.removeFirst(count - Self.window)
        }
        updateMistakes(correct, time: time, level: level)
    }

    /// Changes the last recorded answer of that level and kind ("I was right").
    public mutating func replaceLast(with correct: Bool, time: ClockTime, level: TimeLevel, kind: TimeExerciseKind) {
        let key = Self.key(level, kind)
        guard let last = results[key]?.indices.last else { return }
        results[key]?[last] = correct
        updateMistakes(correct, time: time, level: level)
    }

    private mutating func updateMistakes(_ correct: Bool, time: ClockTime, level: TimeLevel) {
        let key = String(level.rawValue)
        var list = mistakes[key] ?? []
        list.removeAll { $0 == time.minuteOfDay }
        if !correct {
            list.append(time.minuteOfDay)
            if list.count > Self.maximumMistakes { list.removeFirst(list.count - Self.maximumMistakes) }
        }
        mistakes[key] = list.isEmpty ? nil : list
    }
}
