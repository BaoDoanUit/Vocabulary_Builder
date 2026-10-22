//
//  MultiLineTextField.swift
//  vocabulary_builder
//
//  Multi-line TextField for iOS 15. The native `TextField(_:text:axis:)`
//  and `lineLimit(_:range:)` are iOS 16+; this wraps a UITextView so the
//  app can use multi-line input on the iOS 15 deployment target.
//

import SwiftUI
import UIKit

struct MultiLineTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 140

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if uiView.text.isEmpty, !placeholder.isEmpty {
            uiView.text = placeholder
            uiView.textColor = .placeholderText
        } else {
            uiView.textColor = .label
        }
        let size = uiView.sizeThatFits(CGSize(width: uiView.bounds.width, height: .greatestFiniteMagnitude))
        let clamped = min(max(size.height, minHeight), maxHeight)
        context.coordinator.lastHeight = clamped
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var lastHeight: CGFloat = 44

        init(text: Binding<String>) { _text = text }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            // Reset placeholder behaviour.
            if textView.text.isEmpty {
                textView.textColor = .placeholderText
            } else {
                textView.textColor = .label
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.textColor = .label
            }
        }
    }
}

private extension UITextView {
    /// Convenience: a snapshot helper used by `Form` rows to size correctly.
    var fittingHeight: CGFloat {
        let target = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
        return sizeThatFits(target).height
    }
}
