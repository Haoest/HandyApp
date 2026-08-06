import SwiftUI
import UIKit

/// Commits an in-progress text edit from every path that can end it.
///
/// The detail rows hold the user's typing in local `@State` and write it to the store only
/// when the edit ends, so a half-typed value never reaches store validation. Focus loss alone
/// isn't enough: when the view is torn down — a NavigationStack pop, or the `.id()`-driven
/// subtree swap that swipe-paging performs — the focus-loss handler doesn't reliably run and
/// the draft is silently discarded. Backgrounding fires neither handler.
///
/// `commit` **must be idempotent and dirty-checked** — it returns early when the value it would
/// write already equals the stored one. It is called more than once per edit by design, and
/// `Form` recycles off-screen rows (firing `onDisappear` on scroll), so an unconditional commit
/// would bump `modifiedDate` and schedule saves for edits that never happened.
private struct CommitsPendingEdit: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let isFocused: Bool
    let commit: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onDisappear { commit() }
            // onDisappear doesn't fire on backgrounding, and the app-level save in
            // HandyApp3App can't rescue a draft that never reached the store.
            .onChange(of: scenePhase) { _, phase in
                if phase == .inactive || phase == .background { commit() }
            }
    }
}

extension View {
    /// Writes a pending text edit back to the store on focus loss, view teardown, or the app
    /// leaving the foreground. `commit` must be idempotent — see `CommitsPendingEdit`.
    func commitsPendingEdit(focused isFocused: Bool, _ commit: @escaping () -> Void) -> some View {
        modifier(CommitsPendingEdit(isFocused: isFocused, commit: commit))
    }
}

/// Ends editing app-wide, resigning whatever text field holds first responder. Used before a
/// transition that destroys the view containing the focused field, so its focus-loss commit
/// runs while the view is still installed instead of racing the teardown.
func endTextEditing() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}
