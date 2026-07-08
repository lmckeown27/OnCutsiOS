//
//  CameraImagePicker.swift
//  OnCuts
//
//  Presents `UIImagePickerController` for `.camera` from SwiftUI (e.g. message composer).
//

#if canImport(UIKit)
import SwiftUI
import UIKit

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker

        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }

        /// Dismissal + callback must not run during UIKit’s picker delegate callback (same run loop as SwiftUI updates).
        private func finishDismissThenReportImage(_ image: UIImage?) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.isPresented = false
                if let image {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.parent.onImage(image)
                    }
                }
            }
        }

        private func finishDismissOnly() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.isPresented = false
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            finishDismissOnly()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            if let image {
                finishDismissThenReportImage(image)
            } else {
                finishDismissOnly()
            }
        }
    }
}
#endif
