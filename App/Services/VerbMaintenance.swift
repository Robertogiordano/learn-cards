import Foundation
import LearnCore
import SwiftData

/// One-off jobs on saved verbs that need the model: the preterite for verbs saved before it was
/// asked for, and verbs that ended up among the words.
@MainActor
enum VerbMaintenance {
    /// Verbs per request: short lists keep the answers complete.
    private static let batchSize = 20

    enum Failure: LocalizedError {
        case noKey

        var errorDescription: String? {
            switch self {
            case .noKey: return "Add an OpenRouter API key in Settings first."
            }
        }
    }

    private static func client(existingCategories: [String] = []) throws -> OpenRouterClient {
        guard let key = Secrets.openRouterKey else { throw Failure.noKey }
        let model = (UserDefaults.standard.string(forKey: SettingsKey.model) ?? "").trimmed
        return OpenRouterClient(apiKey: key, model: model.isEmpty ? OpenRouterModels.defaultModel : model,
                                existingCategories: existingCategories)
    }

    // MARK: - Preterite

    /// Fills in the preterite of the verbs that lack it; returns how many got it.
    /// Progress (verbs done so far) is reported after every batch.
    static func fillPreterite(_ verbs: [Verb], context: ModelContext,
                              progress: (Int) -> Void = { _ in }) async throws -> Int {
        let missing = verbs.filter { !$0.hasPreterite }
        guard !missing.isEmpty else { return 0 }
        let client = try client()
        var filled = 0
        for start in stride(from: 0, to: missing.count, by: batchSize) {
            let batch = Array(missing[start..<min(start + batchSize, missing.count)])
            let tables = try await client.preterite(of: batch.map(\.infinitive))
            for verb in batch {
                guard let forms = tables[verb.dedupeKey] else { continue }
                verb.preterite = forms
                filled += 1
            }
            try? context.save()
            progress(min(start + batchSize, missing.count))
        }
        return filled
    }

    // MARK: - Verbs among the words

    struct MoveResult {
        /// Verbs created from words.
        var created = 0
        /// Words dropped because the verb was already in the verb section.
        var merged = 0
        /// Words the model could not conjugate: left among the words.
        var left: [String] = []
    }

    /// Moves the words marked as verbs to the verb section: each gets its present tense and preterite,
    /// keeps its emoji and English meaning, and the word is deleted. A verb already saved
    /// just absorbs the word (and gets its preterite if it was missing).
    static func moveVerbWords(_ words: [Word], verbs: [Verb], context: ModelContext,
                              progress: (Int) -> Void = { _ in }) async throws -> MoveResult {
        let verbWords = words.filter { $0.partOfSpeech == .verb }
        var result = MoveResult()
        guard !verbWords.isEmpty else { return result }
        let existing = Dictionary(verbs.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })

        var toConjugate: [Word] = []
        var absorbed: [Verb] = []
        for word in verbWords {
            if let verb = existing[PhraseChecker.key(word.german)] {
                absorbed.append(verb)
                context.delete(word)
                result.merged += 1
            } else {
                toConjugate.append(word)
            }
        }
        try? context.save()

        let client = try client()
        var done = result.merged
        for start in stride(from: 0, to: toConjugate.count, by: batchSize) {
            let batch = Array(toConjugate[start..<min(start + batchSize, toConjugate.count)])
            let conjugated = try await client.conjugateVerbs(batch.map(\.german))
            let byKey = Dictionary(conjugated.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
            for word in batch {
                guard var entry = byKey[PhraseChecker.key(word.german)] else {
                    result.left.append(word.german)
                    continue
                }
                entry.emoji = word.emoji
                if let english = word.english.first, !english.trimmed.isEmpty {
                    entry.english = word.english.joined(separator: ", ")
                }
                let verb = Verb(entry: entry, now: word.createdAt)
                // What the learner already knew of the meaning carries over to the translation games.
                verb.srs = word.srs(for: .translation)
                context.insert(verb)
                context.delete(word)
                result.created += 1
            }
            try? context.save()
            done += batch.count
            progress(done)
        }

        // Verbs that absorbed a word may still lack the preterite.
        _ = try? await fillPreterite(absorbed, context: context)
        return result
    }
}
