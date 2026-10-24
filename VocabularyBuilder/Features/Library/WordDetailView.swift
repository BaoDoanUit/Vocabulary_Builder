//
//  WordDetailView.swift
//  vocabulary_builder
//
//  Read-only view of one word + entry points to edit/delete. Mirrors
//  `WordDetailPage`. See IOS_PORTING_GUIDE.md §7.7.
//
//  The screen can page through the list it was opened from: pass the
//  sibling words in `siblings` and the prev/next bar appears. This is
//  the difference between reading one word and browsing a list — with
//  137 words in the library, jumping back and forth through the list
//  for every entry is the tedious part.
//
//  The view keeps its own index into `siblings` instead of pushing a
//  new screen per word, so the back button still returns to the list
//  in one tap and the navigation stack does not grow.
//

import SwiftUI

struct WordDetailView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var session: SessionStore

    /// The word this screen was opened for.
    let wordId: UUID

    /// The words this screen can page through, in order. Empty means
    /// the screen shows a single word with no paging.
    var siblings: [Vocabulary] = []

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var index: Int = 0
    @State private var strongThreshold: Int = 3
    @StateObject private var speech = Speech.shared

    /// The words this screen can page through. A local copy so a
    /// deleted word drops out of the list instead of still being
    /// there after the delete.
    @State private var items: [Vocabulary] = []

    /// The word currently on screen.
    private var word: Vocabulary? {
        if items.isEmpty {
            return library.words.first(where: { $0.id == wordId })
        }
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private var canGoBack: Bool { index > 0 }
    private var canGoForward: Bool { index + 1 < items.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let word {
                    hero(word: word)
                    imageBlock(word: word)
                    meaning(word: word)
                    example(word: word)
                    progress(word: word)
                } else {
                    Card {
                        Text("This word no longer exists on the server.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        // Swipe left / right to page through the list. `simultaneous`
        // so the scroll view keeps its own vertical dragging.
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { value in
                    guard items.count > 1 else { return }
                    // Only a mostly-horizontal drag counts, so the
                    // vertical scroll is not stolen.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 { goForward() } else { goBack() }
                }
        )
        .navigationTitle(word?.word ?? "Word")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Group {
                    if word != nil {
                        Menu {
                            Button {
                                showEdit = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if items.count > 1 {
                pagingBar
            }
        }
        .fullScreenCover(isPresented: $showEdit) {
            // The editor is a screen of its own — a `.sheet` would
            // draw it as an inset card with a second navigation stack
            // nested inside.
            if let word {
                NavigationView {
                    WordEditorView(mode: .edit(word))
                        .hideTabBar()
                }
                .navigationViewStyle(.stack)
            }
        }
        .confirmationDialog(
            "Delete this word?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteCurrentWord() }
            }
        } message: {
            Text("This permanently removes the word and its progress from the server.")
        }
        .onAppear {
            // Start on the word the screen was opened for.
            items = siblings
            if let i = items.firstIndex(where: { $0.id == wordId }) {
                index = i
            }
        }
        .task {
            // The mastery badge needs the user's own threshold.
            if let user = session.user, let s = try? await api.getSettings(userId: user.id) {
                strongThreshold = s.strongThreshold
            }
        }
    }

    // MARK: - Sections

    /// The headword, its pronunciation and the chips that classify it.
    private func hero(word: Vocabulary) -> some View {
        ElevatedCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(word.word)
                        .font(.system(size: 34, weight: .bold))
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button {
                        speech.speak(word.word)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Theme.primary)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Pronounce \(word.word)")
                }

                if let ipa = word.ipa, !ipa.isEmpty {
                    Text(ipa)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    MasteryBadge(mastery: library.mastery(word, strongThreshold: strongThreshold))
                    if !word.category.isEmpty {
                        Chip(label: word.category, outlined: true)
                    }
                    if let pos = word.partOfSpeech.nonEmpty {
                        Chip(label: pos, tint: Theme.info, outlined: true)
                    }
                    if let level = word.difficultyLevel?.nonEmpty {
                        Chip(label: level, tint: Theme.warning, outlined: true)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func imageBlock(word: Vocabulary) -> some View {
        if word.hasImage {
            let url = api.mediaURL(.images, word.imageId!)
            CachedImage(url: url)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
                .padding(.horizontal)
        }
    }

    /// Definition and translation, side by side in meaning.
    private func meaning(word: Vocabulary) -> some View {
        ElevatedCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Definition", icon: "text.book.closed")
                    Text(word.definition)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Translation", icon: "character.book.closed", tint: Theme.info)
                    Text(word.translation)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func example(word: Vocabulary) -> some View {
        if !word.exampleSentence.isEmpty {
            ElevatedCard {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Example", icon: "quote.opening", tint: Theme.warning)
                    Text("\u{201C}\(word.exampleSentence)\u{201D}")
                        .font(.callout)
                        .italic()
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func progress(word: Vocabulary) -> some View {
        if let p = library.progress(for: word) {
            ElevatedCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Progress", icon: "chart.bar.fill", tint: Theme.primary)
                    HStack(spacing: 8) {
                        StatTile(value: "\(p.attempts)", label: "Attempts")
                        StatTile(value: "\(p.correct)", label: "Correct", tint: Theme.primary)
                        StatTile(value: "\(p.incorrect)", label: "Wrong", tint: Theme.danger)
                        StatTile(value: "\(p.consecutiveCorrect)", label: "Streak")
                    }
                    if p.isWeak {
                        Chip(label: "Marked weak — review this one", icon: "exclamationmark.circle", tint: Theme.danger)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    /// The prev/next bar, pinned to the bottom of the screen.
    private var pagingBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                pagingButton(
                    systemImage: "chevron.left",
                    label: "Previous",
                    isEnabled: canGoBack
                ) {
                    goBack()
                }

                // Tapping the counter jumps back to the first word.
                Button {
                    index = 0
                } label: {
                    VStack(spacing: 1) {
                        Text("\(index + 1) of \(items.count)")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                        Text("Word")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Word \(index + 1) of \(items.count)")

                pagingButton(
                    systemImage: "chevron.right",
                    label: "Next",
                    isEnabled: canGoForward
                ) {
                    goForward()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
        }
    }

    /// Step to the previous word, if there is one.
    private func goBack() {
        guard canGoBack else { return }
        index -= 1
        speech.stop()
    }

    /// Step to the next word, if there is one.
    private func goForward() {
        guard canGoForward else { return }
        index += 1
        speech.stop()
    }

    private func pagingButton(
        systemImage: String,
        label: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? Theme.primary : Color.secondary.opacity(0.3))
                .frame(width: 40, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isEnabled ? Theme.primary.opacity(0.12) : Color.clear)
                )
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }

    // MARK: - Actions

    /// Delete the word on screen and step to the next one, so the
    /// list stays browsable.
    private func deleteCurrentWord() async {
        guard let word else { return }
        let removedIndex = index
        await library.deleteWord(api: api, id: word.id)
        items.removeAll { $0.id == word.id }
        // The deleted word was at `removedIndex`; the word that took
        // its place is now at the same index. If it was the last one,
        // step back instead.
        if removedIndex >= items.count {
            index = max(0, items.count - 1)
        } else {
            index = removedIndex
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
