//
//  Brand.swift
//  FreeFlow
//
//  Single source of truth for product identity and commerce configuration.
//
//  Everything a fork needs to change lives here. `scripts/release.sh` refuses
//  to cut a release build while any REPLACE_ME placeholder remains, so a
//  misconfigured checkout can never ship.
//

import Foundation

enum Brand {
    // MARK: - Identity

    static let appName = "FreeFlow"
    static let bundleID = "com.freeflowapp.FreeFlow"

    static let githubOwner = "adhyanshupadhyaya"
    static let githubRepo = "FreeFlow"

    static var githubSlug: String { "\(self.githubOwner)/\(self.githubRepo)" }

    static var sourceURL: URL {
        URL(string: "https://github.com/\(self.githubSlug)")!
    }

    static var releasesURL: URL {
        URL(string: "https://github.com/\(self.githubSlug)/releases")!
    }

    static var issuesURL: URL {
        URL(string: "https://github.com/\(self.githubSlug)/issues/new/choose")!
    }

    /// Shown wherever the app has to point a user at the licence text.
    static var licenseURL: URL {
        URL(string: "https://github.com/\(self.githubSlug)/blob/main/LICENSE")!
    }

    // MARK: - Commerce

    enum Purchase {
        /// Master switch for the paywall.
        ///
        /// `false` ships FreeFlow completely free: no gate, no trial counter,
        /// no account required, and nothing to configure. Flip to `true` to
        /// turn on the trial-then-pay flow — the whole implementation is intact
        /// behind this flag.
        static let isPaywallEnabled = true

        /// Dictations a user gets before the unlock prompt becomes mandatory.
        /// Ignored entirely while `isPaywallEnabled` is false.
        static let freeDictations = 5

        /// Display-only. The authoritative price lives in the Dodo dashboard.
        static let priceDisplay = "$5"

        /// Dodo Payments hosted checkout link for the one-time $5 product.
        /// Dashboard → Products → your product → Share / Payment Link.
        static let checkoutURLString = "REPLACE_ME_DODO_CHECKOUT_URL"

        /// Dodo product id (`pdt_…`). Activation responses are checked against
        /// this so a licence minted for a *different* product cannot unlock
        /// FreeFlow.
        static let productID = "REPLACE_ME_DODO_PRODUCT_ID"

        static var checkoutURL: URL? {
            guard !self.checkoutURLString.hasPrefix("REPLACE_ME") else { return nil }
            return URL(string: self.checkoutURLString)
        }

        static var isConfigured: Bool {
            self.checkoutURL != nil && !self.productID.hasPrefix("REPLACE_ME")
        }
    }

    // MARK: - Dodo Payments API

    enum Dodo {
        /// Flip to `true` only while testing against Dodo's sandbox.
        static let useTestMode = false

        static var baseURL: URL {
            self.useTestMode
                ? URL(string: "https://test.dodopayments.com")!
                : URL(string: "https://live.dodopayments.com")!
        }

        /// The licence endpoints are public: they take no API key. That matters
        /// here — FreeFlow is GPL-3, so anything embedded in the binary is also
        /// in the published source. There is deliberately no secret to leak.
        static var activateURL: URL { self.baseURL.appendingPathComponent("licenses/activate") }
        static var validateURL: URL { self.baseURL.appendingPathComponent("licenses/validate") }
        static var deactivateURL: URL { self.baseURL.appendingPathComponent("licenses/deactivate") }
    }

    // MARK: - Supabase (accounts + entitlements)

    enum Supabase {
        /// Project URL, e.g. https://abcdefgh.supabase.co
        static let projectURLString = "REPLACE_ME_SUPABASE_URL"

        /// The anon / publishable key. This is public by design — it carries no
        /// privilege on its own and every table is protected by row-level
        /// security. Safe to ship in a GPL binary whose source is published.
        static let anonKey = "REPLACE_ME_SUPABASE_ANON_KEY"

        static var projectURL: URL? {
            guard !self.projectURLString.hasPrefix("REPLACE_ME") else { return nil }
            return URL(string: self.projectURLString)
        }

        static var isConfigured: Bool {
            self.projectURL != nil && !self.anonKey.hasPrefix("REPLACE_ME")
        }

        static var authURL: URL? { self.projectURL?.appendingPathComponent("auth/v1") }
        static var restURL: URL? { self.projectURL?.appendingPathComponent("rest/v1") }

        /// Table holding one row per entitled account.
        static let entitlementsTable = "entitlements"
    }

    // MARK: - Support

    /// Optional public support address. Left unset by default — a shipped app
    /// broadcasts this to every user, so it's a deliberate choice, not a
    /// default. Unset means support routes to GitHub issues instead.
    static let supportEmail = "REPLACE_ME_SUPPORT_EMAIL"

    static var supportEmailIfSet: String? {
        self.supportEmail.hasPrefix("REPLACE_ME") ? nil : self.supportEmail
    }

    /// Endpoint that receives opt-in transcription samples.
    ///
    /// Deliberately unset. Upstream posted raw and processed dictation text to
    /// its own server; FreeFlow must never send a user's words anywhere they
    /// didn't choose. Leave this nil unless you run such a service and say so
    /// in your privacy policy.
    static let transcriptionSampleEndpoint: String? = nil

    /// Endpoint that receives in-app feedback. Unset routes users to GitHub.
    static let feedbackEndpoint: String? = nil
}
