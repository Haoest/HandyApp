import Foundation
import StoreKit
import Observation

enum PurchaseError: Error {
    case productUnavailable
    case verificationFailed
}

/// Tracks the one-time "Full Version" unlock via StoreKit 2. Entitlements are the
/// source of truth — `isFullVersion` is never persisted, only re-derived each launch.
@Observable
@MainActor
final class PurchaseManager {
    static let fullVersionID = "haoest.HandyApp3.fullversion"
    static let freeAssetLimit = 5

    private(set) var isFullVersion = false
    private(set) var product: Product?

    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
    }

    /// Loads the product, checks current entitlements, and starts listening for
    /// transaction updates for the rest of the app's lifetime. Call once at launch.
    func start() {
        Task { await loadProduct() }
        Task { await refreshEntitlements() }
        updatesTask?.cancel()
        updatesTask = Task {
            for await update in StoreKit.Transaction.updates {
                await handle(update)
            }
        }
    }

    func purchase() async throws {
        guard let product else { throw PurchaseError.productUnavailable }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verify(verification)
            await transaction.finish()
            isFullVersion = true
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    /// Force-resyncs with the App Store and re-checks entitlements. Doesn't charge
    /// the user — it only re-fetches what the signed-in Apple ID already owns.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func loadProduct() async {
        product = try? await Product.products(for: [Self.fullVersionID]).first
    }

    private func refreshEntitlements() async {
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            guard let transaction = try? verify(entitlement) else { continue }
            if transaction.productID == Self.fullVersionID, transaction.revocationDate == nil {
                isFullVersion = true
                return
            }
        }
    }

    private func handle(_ update: VerificationResult<StoreKit.Transaction>) async {
        guard let transaction = try? verify(update) else { return }
        await transaction.finish()
        if transaction.productID == Self.fullVersionID {
            isFullVersion = transaction.revocationDate == nil
        }
    }

    private func verify<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw PurchaseError.verificationFailed
        case .verified(let value): return value
        }
    }
}
