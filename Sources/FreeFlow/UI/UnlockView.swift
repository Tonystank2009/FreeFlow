//
//  UnlockView.swift
//  FreeFlow
//
//  The paywall. Shown when the free dictations run out, and reachable any time
//  from Settings.
//

import SwiftUI

struct UnlockView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var license = LicenseManager.shared

    @State private var email = ""
    @State private var code = ""
    @State private var licenseKey = ""
    @State private var isShowingKeyEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.lg) {
            self.header

            if self.license.state.isLicensed {
                self.licensedBody
            } else {
                self.purchaseBody
            }

            self.messages

            Spacer(minLength: 0)
            self.footer
        }
        .padding(self.theme.metrics.spacing.xxl)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background(self.theme.palette.windowBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.xs) {
            Text(self.license.state.isLicensed ? "FreeFlow is unlocked" : "Unlock FreeFlow")
                .font(self.theme.typography.title)
                .foregroundStyle(self.theme.palette.primaryText)

            Text(self.subtitle)
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        switch self.license.state {
        case let .licensed(source):
            switch source {
            case let .account(email): return "Signed in as \(email). Thank you for buying FreeFlow."
            case .licenseKey: return "Unlocked with a licence key on this Mac."
            }
        case let .trial(remaining):
            let noun = remaining == 1 ? "dictation" : "dictations"
            return "You have \(remaining) free \(noun) left. "
                + "One payment of \(Brand.Purchase.priceDisplay) unlocks FreeFlow forever."
        case .trialExhausted:
            return "You've used your \(Brand.Purchase.freeDictations) free dictations. "
                + "One payment of \(Brand.Purchase.priceDisplay) unlocks FreeFlow forever — "
                + "no subscription, all future updates included."
        }
    }

    // MARK: - Purchase flow

    @ViewBuilder
    private var purchaseBody: some View {
        if self.license.isSignedIn {
            self.checkoutStep
        } else {
            self.signInStep
        }

        if self.isShowingKeyEntry {
            self.licenseKeyField
        }
    }

    @ViewBuilder
    private var signInStep: some View {
        switch self.license.authStep {
        case .enterEmail:
            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
                Text("Your purchase is tied to an account, so it works on every Mac you sign into.")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("you@example.com", text: self.$email)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { self.submitEmail() }

                Button {
                    self.submitEmail()
                } label: {
                    HStack {
                        if self.license.isSendingCode { ProgressView().controlSize(.small) }
                        Text(self.license.isSendingCode ? "Sending…" : "Email me a code")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(self.license.isSendingCode || self.email.isEmpty)
            }

        case let .enterCode(address):
            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
                Text("Enter the 6-digit code sent to \(address).")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("123456", text: self.$code)
                    .textFieldStyle(.roundedBorder)
                    .font(self.theme.typography.codeCaption)
                    .onSubmit { self.submitCode() }

                HStack(spacing: self.theme.metrics.spacing.sm) {
                    Button {
                        self.submitCode()
                    } label: {
                        HStack {
                            if self.license.isVerifying { ProgressView().controlSize(.small) }
                            Text(self.license.isVerifying ? "Verifying…" : "Continue")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(self.license.isVerifying || self.code.isEmpty)

                    Button("Use a different email") {
                        self.code = ""
                        self.license.restartSignIn()
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    private var checkoutStep: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
            if let email = license.accountEmail {
                Text("Signed in as \(email).")
                    .font(self.theme.typography.bodySmall)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            Button {
                self.license.openCheckout()
            } label: {
                Text("Buy FreeFlow — \(Brand.Purchase.priceDisplay) once")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if self.license.isRefreshingEntitlement {
                HStack(spacing: self.theme.metrics.spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for your payment to clear…")
                        .font(self.theme.typography.caption)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }
            }

            Button("I've already paid — check again") {
                Task { await self.license.refreshEntitlement() }
            }
            .buttonStyle(.link)
        }
    }

    private var licenseKeyField: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
            Divider()
            Text("Redeem a licence key")
                .font(self.theme.typography.bodySmallStrong)
                .foregroundStyle(self.theme.palette.primaryText)

            TextField("XXXX-XXXX-XXXX-XXXX", text: self.$licenseKey)
                .textFieldStyle(.roundedBorder)
                .font(self.theme.typography.codeCaption)

            Button("Redeem") {
                Task { await self.license.redeemLicenseKey(self.licenseKey) }
            }
            .disabled(self.licenseKey.isEmpty || self.license.isVerifying)
        }
    }

    // MARK: - Licensed

    private var licensedBody: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
            Label("All features unlocked, on every Mac you sign into.", systemImage: "checkmark.seal.fill")
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.success)

            Button("Done") { self.dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    // MARK: - Messages

    @ViewBuilder
    private var messages: some View {
        if let error = license.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let info = license.infoMessage {
            Text(info)
                .font(self.theme.typography.caption)
                .foregroundStyle(self.theme.palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: self.theme.metrics.spacing.md) {
            if !self.license.state.isLicensed {
                Button(self.isShowingKeyEntry ? "Hide licence key" : "I have a licence key") {
                    withAnimation { self.isShowingKeyEntry.toggle() }
                }
                .buttonStyle(.link)
            }

            Spacer()

            Button("Not now") { self.dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(self.theme.palette.secondaryText)
                .font(self.theme.typography.caption)
        }
    }

    // MARK: - Actions

    private func submitEmail() {
        Task { await self.license.sendCode(to: self.email) }
    }

    private func submitCode() {
        Task { await self.license.verifyCode(self.code) }
    }
}
