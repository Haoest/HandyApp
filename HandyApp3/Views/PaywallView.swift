import SwiftUI

/// Which free-tier limit triggered the paywall — determines the message shown.
enum PaywallReason {
    case assets
    case events
    case transactions

    var message: String {
        switch self {
        case .assets:
            return String(localized: "You're at the free tier's limit of \(PurchaseManager.freeAssetLimit) things.")
        case .events:
            return String(localized: "You're at the free tier's limit of \(PurchaseManager.freeEventLimit) events on this thing.")
        case .transactions:
            return String(localized: "You're at the free tier's limit of \(PurchaseManager.freeTransactionLimit) money records on this thing.")
        }
    }
}

/// Shown when a free-tier user tries to create or restore an asset, event, or
/// transaction beyond the free limit. Offers the one-time Full Version unlock,
/// plus a restore link for users who already own it (reinstall, new device, or
/// a stale entitlement check).
struct PaywallView: View {
    var reason: PaywallReason = .assets

    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Baron.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        hero
                        benefits
                        unlockButton
                        restoreButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
        }
        .alert("Purchase Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: purchases.isFullVersion) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Text("Close")
                    .font(Baron.body(12.5, .medium))
                    .foregroundStyle(Baron.neutral700)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Baron.inset, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Baron.surface)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Baron Book")
                .font(Baron.body(10.5, .medium))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.65))
            Text("Everything, unlimited")
                .font(Baron.heading(29))
                .foregroundStyle(.white)
                .padding(.top, 11)
            Text(reason.message)
                .font(Baron.body(13))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Baron.accent900, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// Spelled out from the same constants the limits are enforced with, so the list can never
    /// promise something the free tier already allows.
    private var benefitLines: [LocalizedStringKey] {
        [
            "Unlimited things — the free tier stops at ^[\(PurchaseManager.freeAssetLimit) thing](inflect: true).",
            "Unlimited events and money records on every thing, instead of ^[\(PurchaseManager.freeEventLimit) each](inflect: true).",
            "Restore anything from Deleted items, however many things you already have.",
            "One payment. No subscription, and it covers every device on your Apple ID."
        ]
    }

    private var benefits: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefitLines.enumerated()), id: \.offset) { index, line in
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 11) {
                        Text("✓")
                            .font(Baron.heading(13))
                            .foregroundStyle(Baron.accent700)
                        Text(line)
                            .font(Baron.body(13))
                            .foregroundStyle(Baron.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 12)
                    if index < benefitLines.count - 1 {
                        Baron.line.frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 15)
        .baronCard(elevation: .low)
    }

    private var unlockButton: some View {
        Button { purchase() } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(purchaseButtonTitle)
                        .font(Baron.heading(13))
                        .tracking(1)
                        .textCase(.uppercase)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Baron.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(purchases.product == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || purchases.product == nil)
    }

    private var restoreButton: some View {
        Button { restore() } label: {
            Group {
                if isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Already bought it? Restore")
                        .font(Baron.body(12.5, .medium))
                }
            }
            .foregroundStyle(Baron.accent800)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
    }

    private var purchaseButtonTitle: String {
        if let price = purchases.product?.displayPrice {
            return String(localized: "\(price) once · unlock")
        }
        return String(localized: "Unlock the full version")
    }

    private func purchase() {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            do {
                try await purchases.purchase()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            await purchases.restore()
        }
    }
}
