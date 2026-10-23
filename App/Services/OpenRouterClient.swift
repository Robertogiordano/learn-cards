import Foundation
import LearnCore

/// Sends a page photo to a vision model on OpenRouter and returns the vocabulary it finds.
struct OpenRouterClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case http(status: Int, message: String)
        case emptyResponse
        case noWords
        case noPhrases
        case noVerbs

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Enter your OpenRouter API key in Settings."
            case .http(401, _):
                return "Invalid OpenRouter API key."
            case .http(402, _):
                return "Out of OpenRouter credit."
            case .http(429, _):
                return "Too many requests: try again shortly."
            case .http(let status, let message):
                return "OpenRouter error (\(status)): \(message)"
            case .emptyResponse:
                return "The model returned no answer."
            case .noWords:
                return "No German words found in the photo."
            case .noPhrases:
                return "No German phrases found in the photo."
            case .noVerbs:
                return "No German verbs found in the photo."
            }
        }
    }

    let apiKey: String
    let model: String
    /// The learner's themes, so the model reuses them.
    var existingCategories: [String] = []
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// What to ask the model for one kind of extraction.
    private struct Request {
        let system: String
        let instruction: String
        let schemaName: String
        let schema: [String: Any]
        /// Extractions are mechanical: "thinking" only makes them slower and dearer.
        var reasoning: [String: Any]? = ["enabled": false]
    }

    func extractVocabulary(fromJPEG jpeg: Data) async throws -> [VocabEntry] {
        let content = try await extract(jpeg: jpeg, request: Request(
            system: ExtractionPrompt.system(existingCategories: existingCategories),
            instruction: ExtractionPrompt.userInstruction,
            schemaName: "vocabulary",
            schema: ExtractionPrompt.responseSchema
        ))
        let entries = try ExtractionParser.parse(content, existingCategories: existingCategories)
        guard !entries.isEmpty else { throw ClientError.noWords }
        return entries
    }

    /// Sentences and idioms; gap exercises (e.g. "find the question") come back solved.
    func extractPhrases(fromJPEG jpeg: Data) async throws -> [PhraseEntry] {
        let content = try await extract(jpeg: jpeg, request: Request(
            system: PhraseExtractionPrompt.system(existingCategories: existingCategories),
            instruction: PhraseExtractionPrompt.userInstruction,
            schemaName: "phrases",
            schema: PhraseExtractionPrompt.responseSchema,
            // Solving gap exercises benefits from a little reasoning.
            reasoning: ["effort": "low"]
        ))
        let phrases = try PhraseExtractionParser.parse(content, existingCategories: existingCategories)
        guard !phrases.isEmpty else { throw ClientError.noPhrases }
        return phrases
    }

    /// Step 1 of a verb import: only the infinitives on the photo.
    func extractVerbInfinitives(fromJPEG jpeg: Data) async throws -> [String] {
        let content = try await extract(jpeg: jpeg, request: Request(
            system: VerbListPrompt.system(),
            instruction: VerbListPrompt.userInstruction,
            schemaName: "verb_list",
            schema: VerbListPrompt.responseSchema
        ))
        let infinitives = try VerbListPrompt.parse(content)
        guard !infinitives.isEmpty else { throw ClientError.noVerbs }
        return infinitives
    }

    /// Step 2: the present tense of the verbs not yet saved (text only, no photo).
    func conjugateVerbs(_ infinitives: [String]) async throws -> [VerbEntry] {
        let content = try await extract(jpeg: nil, request: Request(
            system: VerbExtractionPrompt.system(),
            instruction: VerbExtractionPrompt.userInstruction(for: infinitives),
            schemaName: "verbs",
            schema: VerbExtractionPrompt.responseSchema
        ))
        let verbs = try VerbExtractionParser.parse(content)
        guard !verbs.isEmpty else { throw ClientError.noVerbs }
        return verbs
    }

    /// Today's lesson plan from the learner's summary (text only, no photo).
    func coachPlan(summary: CoachSummary) async throws -> CoachPlan {
        let content = try await extract(jpeg: nil, request: Request(
            system: CoachPrompt.system(),
            instruction: summary.json(),
            schemaName: "lesson",
            schema: CoachPrompt.responseSchema,
            reasoning: ["effort": "low"]
        ))
        return try CoachPrompt.parse(content)
    }

    private func extract(jpeg: Data?, request: Request) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        do {
            return try await complete(jpeg: jpeg, request: request, structured: true)
        } catch ClientError.http(let status, _) where status == 400 {
            // Some models reject the reasoning setting or structured outputs: drop them one at a time.
            var plain = request
            plain.reasoning = nil
            if request.reasoning != nil,
               let content = try? await complete(jpeg: jpeg, request: plain, structured: true) {
                return content
            }
            return try await complete(jpeg: jpeg, request: plain, structured: false)
        }
    }

    private func complete(jpeg: Data?, request extraction: Request, structured: Bool) async throws -> String {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/robertogiordano/learn-cards", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LearnCards", forHTTPHeaderField: "X-Title")

        let textPart: [String: Any] = ["type": "text", "text": extraction.instruction]
        var parts = [textPart]
        if let jpeg {
            let imagePart: [String: Any] = [
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"],
            ]
            parts.append(imagePart)
        }
        let systemMessage: [String: Any] = ["role": "system", "content": extraction.system]
        let userMessage: [String: Any] = ["role": "user", "content": parts]
        var body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [systemMessage, userMessage],
        ]
        if let reasoning = extraction.reasoning {
            body["reasoning"] = reasoning
        }
        if structured {
            let schema: [String: Any] = [
                "name": extraction.schemaName,
                "strict": true,
                "schema": extraction.schema,
            ]
            let responseFormat: [String: Any] = ["type": "json_schema", "json_schema": schema]
            body["response_format"] = responseFormat
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoded = try? JSONDecoder().decode(CompletionResponse.self, from: data)
        guard (200..<300).contains(status) else {
            let message = decoded?.error?.message ?? String(decoding: data.prefix(300), as: UTF8.self)
            throw ClientError.http(status: status, message: message)
        }
        // OpenRouter can report upstream failures inside a 200 response.
        if let error = decoded?.error {
            throw ClientError.http(status: error.code ?? status, message: error.message)
        }
        guard let content = decoded?.choices?.first?.message.content, !content.isEmpty else {
            throw ClientError.emptyResponse
        }
        return content
    }
}

private struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }

    struct APIError: Decodable {
        let message: String
        let code: Int?
    }

    let choices: [Choice]?
    let error: APIError?
}
