//
//  ImagePicker.swift
//  vocabulary_builder
//
//  UIImagePickerController wrapper for camera capture. The web app forces
//  a file upload; on iOS we capture directly into the same pipeline.
//  PhotosPicker handles the library-pick case.
//

import SwiftUI
import UIKit

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Fall back to library if camera isn't available (Simulator).
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType)
            ? sourceType
            : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        // The picker is presented inside a `.fullScreenCover`, but it
        // sets its own presentation style, which would otherwise make
        // it a partial-height card over the OCR flow. Forcing
        // `.fullScreen` keeps the camera edge to edge.
        picker.modalPresentationStyle = .fullScreen
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
