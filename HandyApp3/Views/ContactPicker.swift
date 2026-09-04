import SwiftUI
import ContactsUI

struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (String, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, uiViewController.presentedViewController == nil,
              uiViewController.view.window != nil else { return }
        context.coordinator.requestAccessAndPresent(from: uiViewController)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker
        private var isRequestingAccess = false

        init(parent: ContactPicker) { self.parent = parent }

        /// The contact authorization prompt belongs at the picker boundary: every place that
        /// embeds ContactPicker now stays lazy without duplicating permission code.
        func requestAccessAndPresent(from host: UIViewController) {
            guard !isRequestingAccess else { return }
            isRequestingAccess = true
            Task { @MainActor [weak self, weak host] in
                guard let self, let host else { return }
                let granted = (try? await ContactResolver.shared.requestAccess()) ?? false
                self.isRequestingAccess = false
                guard self.parent.isPresented else { return }

                if granted {
                    let picker = CNContactPickerViewController()
                    picker.delegate = self
                    host.present(picker, animated: true)
                } else {
                    self.parent.isPresented = false
                    self.presentAccessDeniedAlert(from: host)
                }
            }
        }

        private func presentAccessDeniedAlert(from host: UIViewController) {
            let alert = UIAlertController(
                title: String(localized: "Contacts Access Needed"),
                message: String(localized: "Allow Contacts access in Settings to choose a contact."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
            alert.addAction(UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
            host.present(alert, animated: true)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let full = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let name = full.isEmpty ? contact.organizationName : full
            parent.onPick(contact.identifier, name)
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
