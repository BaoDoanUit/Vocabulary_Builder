//
//  Components.swift
//  vocabulary_builder
//
//  Reusable views that lift the web app's inlined components. See
//  IOS_PORTING_GUIDE.md §8.
//

import SwiftUI

// MARK: - Chip

struct Chip: View {
    let label: String
    var icon: String? = nil
    var tint: Color = Theme.primary
    var outlined: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(outlined ? tint.opacity(0.1) : tint)
        .foregroundStyle(outlined ? tint : .white)
        .clipShape(Capsule())
    }
}

// MARK: - Stat circle (Home screen)

struct StatCircle: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2.bold()).tracking(0.5).foregroundStyle(.secondary)
        }
        .frame(width: 80, height: 80)
        .background(color.opacity(0.12))
        .clipShape(Circle())
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

// MARK: - Empty state

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (label: String, perform: () -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(title).font(.title3).bold()
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.label, action: action.perform)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(3)
            Spacer()
            if let retry {
                Button("Retry", action: retry)
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(12)
        .background(Theme.danger)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Primary button

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon { Image(systemName: icon) }
                Text(title).bold()
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Theme.primary)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Async image with cache

struct CachedImage: View {
    let url: URL?
    @State private var image: UIImage?
    private let cache = ImageCache.shared

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .overlay {
                        if url != nil {
                            ProgressView()
                        } else {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let cached = cache.image(for: url) {
                image = cached
                return
            }
            image = await cache.load(url)
        }
    }
}

// MARK: - Loading overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
