import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, uiViewController.presentedViewController == nil,
              uiViewController.view.window != nil else { return }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        uiViewController.present(picker, animated: true)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker

        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.isPresented = false
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
            picker.dismiss(animated: true)
        }
    }
}
