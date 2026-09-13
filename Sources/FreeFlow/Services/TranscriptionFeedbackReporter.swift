import Foundation

enum TranscriptionFeedbackReporter {
    struct Payload: Encodable {
        let rawText: String
        let processedText: String
        let processingModel: String
        let comments: String
    }

    enum ReporterError: LocalizedError {
        case invalidURL
        case notConfigured
        case invalidResponse
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid report endpoint."
            case .notConfigured:
                return "This build has no sample-sharing service. Please open a GitHub issue instead."
            case .invalidResponse:
                return "Invalid report response."
            case let .httpError(statusCode):
                return "Report failed with HTTP \(statusCode)."
            }
        }
    }

    static func submit(_ payload: Payload) async throws {
        // Unset by default. Sharing dictation text is an opt-in that only
        // makes sense if you operate the receiving service yourself.
        guard let endpoint = Brand.transcriptionSampleEndpoint,
              let url = URL(string: endpoint)
        else {
            throw ReporterError.notConfigured
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ReporterError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ReporterError.httpError(httpResponse.statusCode)
        }
    }
}
