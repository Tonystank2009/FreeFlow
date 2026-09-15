//
//  HostedFormattingClient.swift
//  FreeFlow
//
//  Calls FreeFlow's own formatting endpoint, never a model provider directly.
//
//  There is no API key in this file, and there must never be one. FreeFlow is
//  GPL-3: every line here is published, so a key embedded in the client is a
//  key published to everyone. The licence key is the only credential the app
//  holds, and it authorises exactly one thing — this endpoint.
//

import Foundation

enum HostedFormattingError: LocalizedError {
    case notConfigured
    case notSubscribed
    case tooLong
    case rateLimited
    case unavailable
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Formatting isn't set up in this build."
        case .notSubscribed:
            return "Formatting needs an active subscription."
        case .tooLong:
            return "That dictation is too long to format."
        case .rateLimited:
            return "You've hit today's formatting limit."
        case .unavailable:
            return "Formatting is unavailable right now."
        case let .network(error):
            return "Couldn't reach formatting: \(error.localizedDescription)"
        }
    }
}

final class HostedFormattingClient {
    static let shared = HostedFormattingClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // Someone is watching a cursor, waiting for this. Better to give up
            // and paste the raw transcription than to hang.
            configuration.timeoutIntervalForRequest = 12
            configuration.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: configuration)
        }
    }

    var isAvailable: Bool {
        Brand.Supabase.isConfigured && LicenseManager.shared.installedLicenseRecord != nil
    }

    /// Cleans up dictated text. Throws rather than returning partial results, so
    /// the caller can fall back to the raw transcription.
    func format(_ text: String) async throws -> String {
        guard let projectURL = Brand.Supabase.projectURL else {
            throw HostedFormattingError.notConfigured
        }
        guard let licenseKey = await LicenseManager.shared.installedLicenseRecord?.licenseKey else {
            throw HostedFormattingError.notSubscribed
        }

        var request = URLRequest(
            url: projectURL.appendingPathComponent("functions/v1/format-text")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Brand.Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "license_key": licenseKey,
            "text": text,
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw HostedFormattingError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw HostedFormattingError.unavailable
        }

        switch http.statusCode {
        case 200: break
        case 402: throw HostedFormattingError.notSubscribed
        case 413: throw HostedFormattingError.tooLong
        case 429: throw HostedFormattingError.rateLimited
        case 503: throw HostedFormattingError.notConfigured
        default: throw HostedFormattingError.unavailable
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let formatted = json["text"] as? String,
            !formatted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw HostedFormattingError.unavailable
        }

        return formatted
    }
}
