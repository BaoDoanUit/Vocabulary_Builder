//
//  LoaderView.swift
//  vocabulary_builder
//
//  One loading indicator for the whole app.
//
//  The screens that wait on the network all use this, so a slow request
//  always looks the same: the app's open-book artwork breathing gently
//  above a plain spinner.
//
//  It deliberately draws *inline* — no material panel, no overlay. The
//  old `LoadingOverlay` put a blurred `.regularMaterial` card over the
//  content, which read as a second screen sliding in rather than as a
//  wait on the screen you were already on.
//
//  See IOS_PORTING_GUIDE.md §8 (design system) and §7.6 (quiz screen).
//

import SwiftUI

// MARK: - Book loader

/// The app icon's open book, pulsing, with a spinner underneath.
///
/// - Parameters:
///   - message: Optional caption under the spinner.
///   - showsSpinner: Set to `false` when the artwork alone is enough
///     (inside a compact control, for instance).
///   - artworkSize: Edge length of the artwork in points.
struct BookLoader: View {
    var message: String? = nil
    var showsSpinner: Bool = true
    var artworkSize: CGFloat = 96

    @State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Image("LoaderBook")
                .resizable()
                .scaledToFit()
                .frame(width: artworkSize, height: artworkSize)
                .opacity(pulse ? 0.45 : 1.0)
                .scaleEffect(pulse ? 0.92 : 1.0)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )

            if showsSpinner {
                ProgressView()
                    .controlSize(.large)
            }

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message ?? "Loading")
    }
}

// MARK: - Inline spinner

/// A bare spinner, for places where the artwork would be too loud —
/// inside a button, a list row, or a toolbar.
struct InlineSpinner: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
    }
}
