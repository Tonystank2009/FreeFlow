//
//  LicenseManager.swift
//  FreeFlow
//
//  Owns the trial/licensed state machine, the Supabase account session, and
//  every decision about whether a dictation is allowed to start.
//

import AppKit
import Combine
import Foundation

enum LicenseSource: Equatable {
    case account(email: String)
    case licenseKey
}

enum LicenseState: Equatable {
    case trial(remaining: Int)
    case trialExhausted
    case licensed(LicenseSource)

    var isLicensed: Bool {
        if case .licensed = self { return true }
        return false
    }
}

/// Where the sign-in sheet currently is.
enum AuthStep: Equatable {
    case enterEmail
    case enterCode(email: String)
}

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    // Entitlement
    @Published private(set) var state: LicenseState = .trial(remaining: Brand.Purchase.freeDictations)

    // Account
    @Published private(set) var session: SupabaseSession?
    @Published var authStep: AuthStep = .enterEmail
    @Published private(set) var isSendingCode = false
    @Published private(set) var isVerifying = false
    @Published private(set) var isRefreshingEntitlement = false

    // Presentation
    @Published var isUnlockPromptPresented = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let supabase: SupabaseClient
    private let dodo: DodoLicenseClient
    private var hasBootstrapped = false

    init(supabase: SupabaseClient = .shared, dodo: DodoLicenseClient = .shared) {
        self.supabase = supabase
        self.dodo = dodo
        self.session = AccountStore.loadSession()
        self.recomputeState()
    }

    // MARK: - Derived state

    private func recomputeState() {
        // Paywall disabled: unconditionally unlocked, nothing to check.
        guard Brand.Purchase.isPaywallEnabled else {
            self.state = .licensed(.licenseKey)
            return
        }

        // A redeemed licence key wins outright — it's the offline fallback.
        if LicenseStore.load() != nil {
            self.state = .licensed(.licenseKey)
            return
        }

        if let session, let entitlement = AccountStore.loadEntitlement(), entitlement.isActive {
            self.state = .licensed(.account(email: session.email))
            return
        }

        let remaining = TrialCounter.remaining
        self.state = remaining > 0 ? .trial(remaining: remaining) : .trialExhausted
    }

    var isSignedIn: Bool { self.session != nil }
    var accountEmail: String? { self.session?.email }

    // MARK: - Gating

    /// The single question the dictation pipeline asks.
    var canStartDictation: Bool {
        switch self.state {
        case .licensed: return true
        case let .trial(remaining): return remaining > 0
        case .trialExhausted: return false
        }
    }

    var remainingFreeDictations: Int {
        switch self.state {
        case .licensed: return .max
        case let .trial(remaining): return remaining
        case .trialExhausted: return 0
        }
    }

    /// Shows the paywall when out of free runs. Returns false to abort.
    func requestDictationPermission() -> Bool {
        if self.canStartDictation { return true }
        self.presentUnlock()
        return false
    }

    func presentUnlock() {
        guard Brand.Purchase.isPaywallEnabled else { return }
        self.errorMessage = nil
        self.infoMessage = nil
        self.isUnlockPromptPresented = true
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called once a dictation has actually delivered text. Deliberately *not*
    /// called when a dictation fails, is empty, or is cancelled — nobody should
    /// burn a free run on a dictation that did nothing for them.
    func consumeDictation() {
        guard !self.state.isLicensed else { return }

        TrialCounter.increment()
        self.recomputeState()

        if case .trialExhausted = self.state {
            self.presentUnlock()
        }
    }

    // MARK: - Launch

    func bootstrap() {
        guard Brand.Purchase.isPaywallEnabled else { return }
        guard !self.hasBootstrapped else { return }
        self.hasBootstrapped = true

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
            await self?.refreshEntitlement()
        }
    }

    // MARK: - Sign in

    func sendCode(to email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), trimmed.count > 3 else {
            self.errorMessage = "Enter a valid email address."
            return
        }

        self.isSendingCode = true
        self.errorMessage = nil
        self.infoMessage = nil
        defer { self.isSendingCode = false }

        do {
            try await self.supabase.sendOTP(email: trimmed)
            self.authStep = .enterCode(email: trimmed)
            self.infoMessage = "We emailed a 6-digit code to \(trimmed)."
        } catch {
            self.errorMessage = self.describe(error)
        }
    }

    func verifyCode(_ code: String) async {
        guard case let .enterCode(email) = authStep else { return }

        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            self.errorMessage = "Enter the 6-digit code from your email."
            return
        }

        self.isVerifying = true
        self.errorMessage = nil
        defer { self.isVerifying = false }

        do {
            let session = try await supabase.verifyOTP(email: email, code: trimmed)
            AccountStore.saveSession(session)
            self.session = session
            self.infoMessage = nil
            await self.refreshEntitlement()

            // Signed in but not yet entitled: send them straight to checkout.
            if !self.state.isLicensed {
                self.infoMessage = "Signed in as \(session.email). Complete your purchase to unlock."
            }
        } catch {
            self.errorMessage = self.describe(error)
        }
    }

    func restartSignIn() {
        self.authStep = .enterEmail
        self.errorMessage = nil
        self.infoMessage = nil
    }

    func signOut() async {
        if let session {
            await self.supabase.signOut(accessToken: session.accessToken)
        }
        AccountStore.clearAll()
        self.session = nil
        self.authStep = .enterEmail
        self.recomputeState()
    }

    // MARK: - Entitlement

    /// Re-reads the entitlement from Supabase.
    ///
    /// Fails **open**: any transport error leaves the cached entitlement in
    /// place. The only thing that revokes access is the server actively
    /// reporting no active row — a refund or chargeback.
    func refreshEntitlement() async {
        guard self.session != nil else { return }
        guard !self.isRefreshingEntitlement else { return }

        self.isRefreshingEntitlement = true
        defer { self.isRefreshingEntitlement = false }

        do {
            let live = try await withValidSession { session in
                try await self.supabase.fetchEntitlement(session: session)
            }

            if let live, live.isActive {
                AccountStore.saveEntitlement(live)
            } else {
                AccountStore.clearEntitlement()
            }
            self.recomputeState()
        } catch {
            // Offline or server trouble — keep whatever we had cached.
            DebugLogger.shared.debug(
                "Entitlement refresh deferred: \(error.localizedDescription)",
                source: "LicenseManager"
            )
        }
    }

    /// Called when the user returns from the Dodo checkout page. Polls briefly
    /// because the webhook that writes the entitlement row is asynchronous.
    func pollForEntitlementAfterPurchase() async {
        guard self.session != nil else { return }

        for attempt in 0 ..< 10 {
            await self.refreshEntitlement()
            if self.state.isLicensed {
                self.isUnlockPromptPresented = false
                self.infoMessage = nil
                return
            }
            let backoff = UInt64(min(2 + attempt, 6)) * NSEC_PER_SEC
            try? await Task.sleep(nanoseconds: backoff)
        }

        self.infoMessage = "Payment not detected yet. It can take a moment — "
            + "reopen this window, or use your licence key if you received one."
    }

    /// Refreshes an expired access token before running `work`.
    private func withValidSession<T>(
        _ work: (SupabaseSession) async throws -> T
    ) async throws -> T {
        guard var current = session else { throw SupabaseError.notSignedIn }

        if current.isExpired {
            current = try await self.supabase.refresh(refreshToken: current.refreshToken)
            AccountStore.saveSession(current)
            self.session = current
        }

        return try await work(current)
    }

    // MARK: - Checkout

    func openCheckout() {
        guard let base = Brand.Purchase.checkoutURL else {
            self.errorMessage = DodoLicenseError.notConfigured.errorDescription
            return
        }

        // Hand Dodo the account this purchase belongs to. The webhook reads
        // these back to write the entitlement row against the right user.
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        if let session {
            items.append(URLQueryItem(name: "email", value: session.email))
            items.append(URLQueryItem(name: "metadata_supabase_user_id", value: session.userID))
        }
        components?.queryItems = items

        NSWorkspace.shared.open(components?.url ?? base)

        Task { await self.pollForEntitlementAfterPurchase() }
    }

    // MARK: - Licence key fallback

    /// Manual recovery path for when a webhook drops or someone bought before
    /// making an account.
    func redeemLicenseKey(_ key: String) async {
        self.errorMessage = nil
        self.isVerifying = true
        defer { self.isVerifying = false }

        do {
            let activation = try await dodo.activate(
                licenseKey: key,
                machineName: Self.machineName()
            )

            LicenseStore.save(LicenseRecord(
                licenseKey: key.trimmingCharacters(in: .whitespacesAndNewlines),
                instanceID: activation.instanceID,
                licenseKeyID: activation.licenseKeyID,
                productID: activation.productID,
                customerEmail: activation.customerEmail,
                activatedAt: activation.activatedAt,
                lastValidatedAt: Date()
            ))

            self.recomputeState()
            self.isUnlockPromptPresented = false
        } catch {
            self.errorMessage = self.describe(error)
        }
    }

    func removeLicenseKey() async {
        if let record = LicenseStore.load() {
            try? await self.dodo.deactivate(
                licenseKey: record.licenseKey,
                instanceID: record.instanceID
            )
        }
        LicenseStore.clear()
        self.recomputeState()
    }

    var installedLicenseRecord: LicenseRecord? { LicenseStore.load() }

    // MARK: - Helpers

    private func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func machineName() -> String {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        return "\(host) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}
