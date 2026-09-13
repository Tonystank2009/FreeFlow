//
//  SupabaseClient.swift
//  FreeFlow
//
//  The slice of Supabase FreeFlow actually needs: passwordless email OTP
//  sign-in and a single entitlement lookup.
//
//  Hand-rolled over URLSession rather than pulling in supabase-swift — two
//  endpoints and one table read do not justify a package dependency, and it
//  keeps the shipped binary and the Xcode project untouched.
//

import Foundation

// MARK: - Models

struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String

    var isExpired: Bool {
        Date() >= self.expiresAt.addingTimeInterval(-60)
    }
}

struct Entitlement: Codable, Equatable {
    var status: String
    var source: String?
    var grantedAt: Date?

    var isActive: Bool {
        self.status.lowercased() == "active"
    }

    enum CodingKeys: String, CodingKey {
        case status
        case source
        case grantedAt = "granted_at"
    }
}

enum SupabaseError: LocalizedError {
    case notConfigured
    case network(Error)
    case api(status: Int, message: String?)
    case malformedResponse
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This build has no Supabase project configured. See Brand.swift."
        case let .network(error):
            return "Couldn’t reach the server: \(error.localizedDescription)"
        case let .api(status, message):
            if let message, !message.isEmpty { return message }
            if status == 429 { return "Too many attempts. Wait a minute and try again." }
            return "The server returned an error (HTTP \(status))."
        case .malformedResponse:
            return "The server sent a response FreeFlow couldn’t read."
        case .notSignedIn:
            return "You’re not signed in."
        }
    }
}

// MARK: - Client

final class SupabaseClient {
    static let shared = SupabaseClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: Auth

    /// Emails a 6-digit code, creating the account if it doesn't exist.
    func sendOTP(email: String) async throws {
        guard let authURL = Brand.Supabase.authURL else { throw SupabaseError.notConfigured }

        _ = try await self.request(
            url: authURL.appendingPathComponent("otp"),
            method: "POST",
            body: [
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "create_user": true,
            ]
        )
    }

    /// Exchanges the emailed code for a session.
    func verifyOTP(email: String, code: String) async throws -> SupabaseSession {
        guard let authURL = Brand.Supabase.authURL else { throw SupabaseError.notConfigured }

        let json = try await request(
            url: authURL.appendingPathComponent("verify"),
            method: "POST",
            body: [
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "token": code.trimmingCharacters(in: .whitespacesAndNewlines),
                "type": "email",
            ]
        )

        return try self.parseSession(json)
    }

    /// Trades a refresh token for a fresh access token.
    func refresh(refreshToken: String) async throws -> SupabaseSession {
        guard let authURL = Brand.Supabase.authURL else { throw SupabaseError.notConfigured }

        var components = URLComponents(
            url: authURL.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw SupabaseError.notConfigured }

        let json = try await request(url: url, method: "POST", body: ["refresh_token": refreshToken])
        return try self.parseSession(json)
    }

    func signOut(accessToken: String) async {
        guard let authURL = Brand.Supabase.authURL else { return }
        _ = try? await self.request(
            url: authURL.appendingPathComponent("logout"),
            method: "POST",
            body: [:],
            accessToken: accessToken
        )
    }

    // MARK: Entitlement

    /// Reads this account's entitlement. Row-level security means the request
    /// can only ever return the caller's own row, so no filter is required —
    /// but one is sent anyway to keep the intent obvious.
    func fetchEntitlement(session: SupabaseSession) async throws -> Entitlement? {
        guard let restURL = Brand.Supabase.restURL else { throw SupabaseError.notConfigured }

        var components = URLComponents(
            url: restURL.appendingPathComponent(Brand.Supabase.entitlementsTable),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "select", value: "status,source,granted_at"),
            URLQueryItem(name: "user_id", value: "eq.\(session.userID)"),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { throw SupabaseError.notConfigured }

        let data = try await requestRaw(url: url, method: "GET", body: nil, accessToken: session.accessToken)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            return ISO8601DateFormatter.supabase.date(from: text) ?? Date()
        }

        let rows = (try? decoder.decode([Entitlement].self, from: data)) ?? []
        return rows.first
    }

    // MARK: Email capture

    /// Records an address so there is a way to reach this person later.
    ///
    /// Unverified on purpose — no account, no emailed code, no password. The
    /// cost is that some addresses will be typos; the benefit is that the ask
    /// is one field and one click, which is the difference between most people
    /// giving it and most people skipping.
    func captureEmail(_ email: String) async throws {
        guard let restURL = Brand.Supabase.restURL else { throw SupabaseError.notConfigured }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.count > 3 else { return }

        var request = URLRequest(url: restURL.appendingPathComponent("signups"))
        request.httpMethod = "POST"
        request.setValue(Brand.Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Brand.Supabase.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Deliberately no "resolution=ignore-duplicates": that turns the call
        // into an upsert, and an upsert needs a select policy to check the
        // conflict. With insert-only RLS it fails with a policy violation, so
        // the header meant every signup was silently rejected. A repeat address
        // now hits the unique index and comes back 409, which is success as far
        // as anyone here is concerned.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": trimmed,
            "source": "onboarding",
            "app_version": AppVersion.short,
        ])

        let response: URLResponse
        do {
            (_, response) = try await self.session.data(for: request)
        } catch {
            throw SupabaseError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { return }
        // 409 = already on the list.
        guard (200 ..< 300).contains(http.statusCode) || http.statusCode == 409 else {
            throw SupabaseError.api(status: http.statusCode, message: nil)
        }
    }

    // MARK: - Transport

    private func parseSession(_ json: [String: Any]) throws -> SupabaseSession {
        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let user = json["user"] as? [String: Any],
              let userID = user["id"] as? String
        else {
            throw SupabaseError.malformedResponse
        }

        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let email = (user["email"] as? String) ?? ""

        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userID: userID,
            email: email
        )
    }

    @discardableResult
    private func request(
        url: URL,
        method: String,
        body: [String: Any]?,
        accessToken: String? = nil
    ) async throws -> [String: Any] {
        let data = try await requestRaw(url: url, method: method, body: body, accessToken: accessToken)
        if data.isEmpty { return [:] }
        return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    private func requestRaw(
        url: URL,
        method: String,
        body: [String: Any]?,
        accessToken: String? = nil
    ) async throws -> Data {
        guard Brand.Supabase.isConfigured else { throw SupabaseError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Brand.Supabase.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Bearer \(accessToken ?? Brand.Supabase.anonKey)",
            forHTTPHeaderField: "Authorization"
        )

        if let body, method != "GET" {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw SupabaseError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw SupabaseError.malformedResponse }

        guard (200 ..< 300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["msg"] as? String)
                ?? (json?["error_description"] as? String)
                ?? (json?["message"] as? String)
                ?? (json?["error"] as? String)
            throw SupabaseError.api(status: http.statusCode, message: message)
        }

        return data
    }
}

extension ISO8601DateFormatter {
    static let supabase: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
