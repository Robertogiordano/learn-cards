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
                return "Inserisci la API key di OpenRouter nelle Impostazioni."
            case .http(401, _):
                return "API key di OpenRouter non valida."
            case .http(402, _):
                return "Credito OpenRouter esaurito."
            case .http(429, _):
                return "Troppe richieste: riprova tra poco."
            case .http(let status, let message):
                return "Errore OpenRouter (\(status)): \(message)"
            case .emptyResponse:
                return "Il modello non ha restituito alcuna risposta."
            case .noWords:
                return "Nessuna parola tedesca trovata nella foto."
            case .noPhrases:
                return "Nessuna frase tedesca trovata nella foto."
            case .noVerbs:
                return "Nessun verbo tedesco trovato nella foto."
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
            schema: PhraseExtractionPrompt.responseSchema
        ))
        let phrases = try PhraseExtractionParser.parse(content, existingCategories: existingCategories)
        guard !phrases.isEmpty else { throw ClientError.noPhrases }
        return phrases
    }

    /// Verbs with their present tense.
    func extractVerbs(fromJPEG jpeg: Data) async throws -> [VerbEntry] {
        let content = try await extract(jpeg: jpeg, request: Request(
            system: VerbExtractionPrompt.system(),
            instruction: VerbExtractionPrompt.userInstruction,
            schemaName: "verbs",
            schema: VerbExtractionPrompt.responseSchema
        ))
        let verbs = try VerbExtractionParser.parse(content)
        guard !verbs.isEmpty else { throw ClientError.noVerbs }
        return verbs
    }

    private func extract(jpeg: Data, request: Request) async throws -> String {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        do {
            return try await complete(jpeg: jpeg, request: request, structured: true)
        } catch ClientError.http(let status, _) where status == 400 {
            // Some models reject structured outputs: retry with the prompt alone.
            return try await complete(jpeg: jpeg, request: request, structured: false)
        }
    }

    private func complete(jpeg: Data, request extraction: Request, structured: Bool) async throws -> String {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/robertogiordano/learn-cards", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LearnCards", forHTTPHeaderField: "X-Title")

        let textPart: [String: Any] = ["type": "text", "text": extraction.instruction]
        let imagePart: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"],
        ]
        let systemMessage: [String: Any] = ["role": "system", "content": extraction.system]
        let userMessage: [String: Any] = ["role": "user", "content": [textPart, imagePart]]
        var body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [systemMessage, userMessage],
        ]
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
