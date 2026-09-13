//
//  DodoLicenseClient.swift
//  FreeFlow
//
//  Thin client over the Dodo Payments licence endpoints.
//
//  These three endpoints are public by design — they authenticate with the
//  licence key itself, not with a merchant API key. That is what makes them
//  safe to call straight from an open-source client.
//

import Foundation

struct DodoActivation: Equatable {
    /// Dodo licence-key *instance* id (`lki_…`) — one per activated machine.
    let instanceID: String
    let licenseKeyID: String
    let productID: String
    let customerEmail: String?
    let activatedAt: Date
}

enum DodoLicenseError: LocalizedError {
    case notConfigured
    case emptyKey
    case network(Error)
    case rejected(status: Int, message: String?)
    case malformedResponse
    case wrongProduct

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "This build has no checkout configured. See Brand.swift."
        case .emptyKey:
            return "Enter your licence key."
        case let .network(error):
            return "Couldn’t reach the licence server: \(error.localizedDescription)"
        case let .rejected(status, message):
            if let message, !message.isEmpty { return message }
            if status == 404 { return "That licence key wasn’t found. Check for typos." }
            if status == 409 { return "That licence key has already been activated on the maximum number of machines." }
            return "The licence server rejected that key (HTTP \(status))."
        case .malformedResponse:
            return "The licence server sent a response FreeFlow couldn’t read."
        case .wrongProduct:
            return "That licence key belongs to a different product."
        }
    }
}

final class DodoLicenseClient {
    static let shared = DodoLicenseClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 30
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: - Activate

    /// Binds a licence key to this machine and returns the instance record.
    func activate(licenseKey: String, machineName: String) async throws -> DodoActivation {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DodoLicenseError.emptyKey }

        let payload: [String: Any] = ["license_key": key, "name": machineName]
        let json = try await self.post(Brand.Dodo.activateURL, payload: payload)

        guard let instanceID = json["id"] as? String,
              let licenseKeyID = json["license_key_id"] as? String
        else {
            throw DodoLicenseError.malformedResponse
        }

        let product = json["product"] as? [String: Any]
        let productID = product?["product_id"] as? String ?? ""

        // Guard against a licence for one of the seller's other products
        // unlocking this one.
        if !Brand.Purchase.productID.hasPrefix("REPLACE_ME"),
           !productID.isEmpty,
           productID != Brand.Purchase.productID
        {
            throw DodoLicenseError.wrongProduct
        }

        let customer = json["customer"] as? [String: Any]

        return DodoActivation(
            instanceID: instanceID,
            licenseKeyID: licenseKeyID,
            productID: productID,
            customerEmail: customer?["email"] as? String,
            activatedAt: Date()
        )
    }

    // MARK: - Validate

    /// Re-checks a stored licence. Throws on transport failure so the caller
    /// can distinguish "offline" from "revoked" — FreeFlow must never lock a
    /// paying user out because their wifi dropped.
    func validate(licenseKey: String, instanceID: String?) async throws -> Bool {
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw DodoLicenseError.emptyKey }

        var payload: [String: Any] = ["license_key": key]
        if let instanceID, !instanceID.isEmpty {
            payload["license_key_instance_id"] = instanceID
        }

        let json = try await self.post(Brand.Dodo.validateURL, payload: payload)
        guard let valid = json["valid"] as? Bool else { throw DodoLicenseError.malformedResponse }
        return valid
    }

    // MARK: - Deactivate

    /// Frees this machine's activation slot so the user can move to another Mac.
    func deactivate(licenseKey: String, instanceID: String) async throws {
        let payload: [String: Any] = [
            "license_key": licenseKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "license_key_instance_id": instanceID,
        ]
        _ = try await self.post(Brand.Dodo.deactivateURL, payload: payload)
    }

    // MARK: - Transport

    @discardableResult
    private func post(_ url: URL, payload: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("\(Brand.appName)/\(AppVersion.short)", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw DodoLicenseError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DodoLicenseError.malformedResponse
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]

        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (json?["message"] as? String)
                ?? (json?["error"] as? String)
                ?? (json?["detail"] as? String)
            throw DodoLicenseError.rejected(status: http.statusCode, message: message)
        }

        // `deactivate` legitimately returns an empty body.
        return json ?? [:]
    }
}

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
