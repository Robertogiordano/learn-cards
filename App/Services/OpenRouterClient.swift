import Foundation
import LearnCore

/// Sends a page photo to a vision model on OpenRouter and returns the vocabulary it finds.
struct OpenRouterClient {
    enum ClientError: LocalizedError {
        case missingAPIKey
        case http(status: Int, message: String)
        case emptyResponse
        case noWords

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
            }
        }
    }

    let apiKey: String
    let model: String
    /// The learner's themes, so the model reuses them.
    var existingCategories: [String] = []
    var session: URLSession = .shared

    private static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    func extractVocabulary(fromJPEG jpeg: Data) async throws -> [VocabEntry] {
        guard !apiKey.isEmpty else { throw ClientError.missingAPIKey }
        let content: String
        do {
            content = try await complete(jpeg: jpeg, structured: true)
        } catch ClientError.http(let status, _) where status == 400 {
            // Some models reject structured outputs: retry with the prompt alone.
            content = try await complete(jpeg: jpeg, structured: false)
        }
        let entries = try ExtractionParser.parse(content, existingCategories: existingCategories)
        guard !entries.isEmpty else { throw ClientError.noWords }
        return entries
    }

    private func complete(jpeg: Data, structured: Bool) async throws -> String {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/robertogiordano/learn-cards", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("LearnCards", forHTTPHeaderField: "X-Title")

        let textPart: [String: Any] = ["type": "text", "text": ExtractionPrompt.userInstruction]
        let imagePart: [String: Any] = [
            "type": "image_url",
            "image_url": ["url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"],
        ]
        let systemMessage: [String: Any] = [
            "role": "system",
            "content": ExtractionPrompt.system(existingCategories: existingCategories),
        ]
        let userMessage: [String: Any] = ["role": "user", "content": [textPart, imagePart]]
        var body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [systemMessage, userMessage],
        ]
        if structured {
            let schema: [String: Any] = [
                "name": "vocabulary",
                "strict": true,
                "schema": ExtractionPrompt.responseSchema,
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
