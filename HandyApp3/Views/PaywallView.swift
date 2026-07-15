import SwiftUI

/// Which free-tier limit triggered the paywall — determines the message shown.
enum PaywallReason {
    case assets
    case events
    case transactions

    var message: String {
        switch self {
        case .assets:
            return "The free version is limited to \(PurchaseManager.freeAssetLimit) active assets. Unlock the Full Version to add more."
        case .events:
            return "The free version is limited to \(PurchaseManager.freeEventLimit) events per asset. Unlock the Full Version to add more."
        case .transactions:
            return "The free version is limited to \(PurchaseManager.freeTransactionLimit) transactions per asset. Unlock the Full Version to add more."
        }
    }
}

/// Shown when a free-tier user tries to create or restore an asset, event, or
/// transaction beyond the free limit. Offers the one-time Full Version unlock,
/// plus a restore link for users who already own it (reinstall, new device, or
/// a stale entitlement check).
struct PaywallView: View {
    var reason: PaywallReason = .assets

    @Environment(AssetStore.self) private var store
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    private var palette: ThemePalette { store.backgroundTheme.palette }

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Full Version")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.onBackground)
                    Text(reason.message)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.onBackgroundSecondary)
                        .padding(.horizontal, 24)

                    Button {
                        purchase()
                    } label: {
                        if isPurchasing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(purchaseButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPurchasing || purchases.product == nil)
                    .padding(.horizontal, 24)

                    Button {
                        restore()
                    } label: {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(isRestoring)
                    .font(.footnote)
                    .foregroundStyle(palette.onBackgroundSecondary)

                    Spacer()
                }
                .environment(\.colorScheme, .light)
            }
            .navigationTitle("Unlock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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
    }

    private var purchaseButtonTitle: String {
        if let price = purchases.product?.displayPrice {
            return "Unlock Full Version — \(price)"
        }
        return "Unlock Full Version"
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
