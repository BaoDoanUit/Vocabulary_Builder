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
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

// MARK: - Elevated card
//
// A card with a soft drop shadow. Used where a card needs to read as a
// raised surface rather than a flat panel — the word detail hero, for
// instance. The plain `Card` stays flat on purpose: a shadow on every
// row makes a long list look busy.

struct ElevatedCard<Content: View>: View {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Section header

/// A small uppercase heading that introduces a block of content.
struct SectionHeader: View {
    let title: String
    var icon: String? = nil
    var tint: Color = Theme.primary

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
        }
        .foregroundStyle(tint)
    }
}

// MARK: - Mastery badge

/// Shows how well the user knows a word. See `LibraryStore.mastery`.
struct MasteryBadge: View {
    let mastery: WordMastery

    private var tint: Color {
        switch mastery {
        case .new: return Theme.info
        case .learning: return Theme.warning
        case .known: return Theme.primary
        case .weak: return Theme.danger
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: mastery.icon).font(.caption2.weight(.bold))
            Text(mastery.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }
}

// MARK: - Stat tile

/// A labelled number, used in the progress row of the detail screen.
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
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

// MARK: - Loading

// The app-wide loading indicator lives in `LoaderView.swift`
// (`BookLoader` / `InlineSpinner`). It replaced the old
// `LoadingOverlay`, whose material card read as a second screen
// sliding over the one you were already on.
