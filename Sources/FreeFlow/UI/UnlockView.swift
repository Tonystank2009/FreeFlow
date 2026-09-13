//
//  UnlockView.swift
//  FreeFlow
//
//  The paywall. Shown when the free dictations run out, and reachable any time
//  from Settings.
//
//  No account, no emailed code. Buying sends a licence key; pasting it once
//  unlocks this Mac permanently. That keeps the whole purchase path on one
//  service and removes every step that isn't paying.
//

import SwiftUI

struct UnlockView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var license = LicenseManager.shared

    @State private var licenseKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.lg) {
            self.header

            if self.license.state.isLicensed {
                self.licensedBody
            } else {
                self.purchaseBody
            }

            if let error = license.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
            self.footer
        }
        .padding(self.theme.metrics.spacing.xxl)
        .frame(width: 440)
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
        case .licensed:
            return "Thank you. Every future update is included."
        case let .trial(remaining):
            let noun = remaining == 1 ? "task" : "tasks"
            return "You have \(remaining) free \(noun) left. "
                + "One payment of \(Brand.Purchase.priceDisplay) unlocks FreeFlow forever."
        case .trialExhausted:
            return "You've used your \(Brand.Purchase.freeDictations) free tasks. "
                + "\(Brand.Purchase.priceDisplay) once, and it's yours forever — no subscription."
        }
    }

    // MARK: - Purchase

    private var purchaseBody: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.md) {
            Button {
                self.license.openCheckout()
            } label: {
                Text("Buy FreeFlow — \(Brand.Purchase.priceDisplay) once")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Divider()

            VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
                Text("Already bought it?")
                    .font(self.theme.typography.bodySmallStrong)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text("Paste the licence key from your receipt.")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(self.theme.palette.secondaryText)

                HStack(spacing: self.theme.metrics.spacing.sm) {
                    TextField("XXXX-XXXX-XXXX-XXXX", text: self.$licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .font(self.theme.typography.codeCaption)
                        .onSubmit { self.redeem() }

                    Button(self.license.isVerifying ? "Checking…" : "Unlock") {
                        self.redeem()
                    }
                    .disabled(self.licenseKey.isEmpty || self.license.isVerifying)
                }
            }
        }
    }

    private var licensedBody: some View {
        VStack(alignment: .leading, spacing: self.theme.metrics.spacing.sm) {
            Label("All features unlocked on this Mac.", systemImage: "checkmark.seal.fill")
                .font(self.theme.typography.bodySmall)
                .foregroundStyle(self.theme.palette.success)

            Button("Done") { self.dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var footer: some View {
        HStack {
            Link("Source code", destination: Brand.sourceURL)
                .font(self.theme.typography.caption)

            Spacer()

            if !self.license.state.isLicensed {
                Button("Not now") { self.dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .font(self.theme.typography.caption)
            }
        }
    }

    private func redeem() {
        Task { await self.license.redeemLicenseKey(self.licenseKey) }
    }
}
