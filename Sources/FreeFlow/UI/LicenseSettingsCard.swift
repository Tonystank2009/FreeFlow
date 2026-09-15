//
//  LicenseSettingsCard.swift
//  FreeFlow
//
//  Licence and account status, shown at the top of General settings.
//

import SwiftUI

struct LicenseSettingsCard: View {
    @Environment(\.theme) private var theme
    @ObservedObject private var license = LicenseManager.shared

    var body: some View {
        ThemedCard(style: .standard) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Licence", systemImage: "checkmark.seal")
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: self.statusIcon)
                        .foregroundStyle(self.statusColor)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(self.statusTitle)
                            .font(self.theme.typography.bodyStrong)
                            .foregroundStyle(.primary)

                        Text(self.statusDetail)
                            .font(self.theme.typography.bodySmall)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    if self.license.state.isLicensed {
                        if self.license.isSignedIn {
                            Button("Sign out") {
                                Task { await self.license.signOut() }
                            }
                        }
                        if self.license.installedLicenseRecord != nil {
                            Button("Remove licence key") {
                                Task { await self.license.removeLicenseKey() }
                            }
                        }
                    } else {
                        Button("Turn on AI formatting — \(Brand.Purchase.priceDisplay) \(Brand.Purchase.priceCadence)") {
                            self.license.presentUnlock()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()

                    Link("Source code", destination: Brand.sourceURL)
                        .font(self.theme.typography.caption)
                }

                Text("FreeFlow is free software under the GNU GPL v3. "
                    + "Your payment supports development — the complete source is public.")
                    .font(self.theme.typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Status

    private var statusIcon: String {
        switch self.license.state {
        case .licensed: return "checkmark.seal.fill"
        case .free: return "sparkles"
        }
    }

    private var statusColor: Color {
        switch self.license.state {
        case .licensed: return self.theme.palette.success
        case .free: return self.theme.palette.secondaryText
        }
    }

    private var statusTitle: String {
        switch self.license.state {
        case .licensed: return "AI formatting on"
        case .free:
            return "Dictation active · AI formatting off"
        }
    }

    private var statusDetail: String {
        switch self.license.state {
        case let .licensed(source):
            switch source {
            case let .account(email):
                return "Signed in as \(email). Works on every Mac you sign into."
            case .licenseKey:
                let masked = self.license.installedLicenseRecord?.maskedKey ?? ""
                return "Unlocked on this Mac with licence key \(masked)."
            }
        case .free:
            return "Dictation is free forever. AI formatting tidies punctuation and "
                + "paragraphs — free for \(Brand.Purchase.trialDays) days, then "
                + "\(Brand.Purchase.priceDisplay) \(Brand.Purchase.priceCadence)."
        }
    }
}
