//
//  StudyView.swift
//  vocabulary_builder
//
//  Flashcard study mode. Replaces `FlashcardView` and adds the 4 filters
//  documented in IOS_PORTING_GUIDE.md §7.5: all, weak, collection, and
//  category. Opens a word bump `studyCount` + `lastSeenAt`.
//

import SwiftUI

enum StudyFilter: Hashable {
    case all
    case weak
    case collection(UUID)
    case category(String)

    var label: String {
        switch self {
        case .all: return "All"
        case .weak: return "Weak"
        case .collection: return "Collection"
        case .category: return "Category"
        }
    }
}

struct StudyView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @State private var filter: StudyFilter = .all
    @State private var deck: [Vocabulary] = []
    @State private var index: Int = 0
    @State private var revealed: Bool = false
    @State private var showFilterSheet = false
    @StateObject private var speech = Speech.shared

    private var deck_: [Vocabulary] {
        // Build a deterministic deck per the current filter.
        switch filter {
        case .all:
            return library.words.shuffled()
        case .weak:
            let ids = Set(library.progress.values.filter(\.isWeak).map(\.wordId))
            return library.words.filter { ids.contains($0.id) }.shuffled()
        case .collection(let id):
            return library.collection(id: id)?.wordIds
                .compactMap { wid in library.words.first(where: { $0.id == wid }) }
                .shuffled() ?? []
        case .category(let name):
            return library.words(in: name).shuffled()
        }
    }

    private var currentWord: Vocabulary? {
        guard index < deck.count else { return nil }
        return deck[index]
    }

    var body: some View {
        // The navigation stack lives in `ContentView`, one per tab.
        VStack(spacing: 0) {
            filterBar
            if let word = currentWord {
                card(for: word)
                    .padding(.horizontal)
                Spacer()
                actionRow(for: word)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            } else {
                emptyState
            }
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle("Study")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showFilterSheet = true
                } label: {
                    Label(filter.label, systemImage: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reshuffle()
                } label: {
                    Image(systemName: "shuffle")
                }
                .accessibilityLabel("Shuffle deck")
            }
        }
        .onAppear {
            if deck.isEmpty { reshuffle() }
            // Pull in words imported since the last visit. Skipped when
            // the store was updated moments ago.
            Task {
                if library.words.isEmpty || !library.wordsAreFresh {
                    await library.reloadWords(api: api)
                }
            }
        }
        .onChange(of: filter) { _ in reshuffle() }
        .onChange(of: library.words) { _ in reshuffle() }
        .onDisappear { speech.stop() }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
        }
    }

    private var filterBar: some View {
        HStack {
            Text(filterDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !deck.isEmpty {
                Text("\(index + 1) / \(deck.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var filterDescription: String {
        switch filter {
        case .all: return "Studying all words"
        case .weak: return "Studying weak words"
        case .collection(let id):
            let name = library.collection(id: id)?.name ?? "Collection"
            return "Studying \(name)"
        case .category(let name):
            return "Studying \(name)"
        }
    }

    @ViewBuilder
    private func card(for word: Vocabulary) -> some View {
        VStack(spacing: 12) {
            HStack {
                if !word.category.isEmpty {
                    Chip(label: word.category, outlined: true)
                }
                if let pos = word.partOfSpeech.nonEmpty {
                    Chip(label: pos, tint: Theme.info, outlined: true)
                }
                Spacer()
                Button {
                    speech.speak(word.word)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.primary)
                }
                .accessibilityLabel("Pronounce")
            }
            Spacer()
            Text(word.word)
                .font(.system(size: 40, weight: .bold))
                .multilineTextAlignment(.center)
            if let ipa = word.ipa, !ipa.isEmpty {
                Text(ipa).font(.subheadline).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 4)
            if revealed {
                VStack(spacing: 8) {
                    Text(word.translation)
                        .font(.title2.weight(.semibold))
                    Text(word.definition)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if !word.exampleSentence.isEmpty {
                        Text("\u{201C}\(word.exampleSentence)\u{201D}")
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation { revealed = true }
                } label: {
                    Label("Tap to reveal", systemImage: "hand.tap")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Theme.primary.opacity(0.15))
                        .foregroundStyle(Theme.primary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if !deck.isEmpty {
                ProgressView(value: Double(index + 1), total: Double(deck.count))
                    .tint(Theme.primary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 380)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private func actionRow(for word: Vocabulary) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    await library.recordStudyOpen(api: api, for: word)
                    advance(known: false)
                }
            } label: {
                Label("Learning", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.warning.opacity(0.18))
                    .foregroundStyle(Theme.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button {
                Task {
                    await library.recordStudyOpen(api: api, for: word)
                    advance(known: true)
                }
            } label: {
                Label("Known", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.primary.opacity(0.18))
                    .foregroundStyle(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var emptyState: some View {
        EmptyState(
            icon: "books.vertical",
            title: "Nothing to study",
            message: emptyMessage,
            action: deck.isEmpty ? nil : ("Shuffle", { reshuffle() })
        )
    }

    private var emptyMessage: String {
        switch filter {
        case .all: return "Add some words in the Library tab."
        case .weak: return "You have no weak words right now. Great work!"
        case .collection(let id):
            let name = library.collection(id: id)?.name ?? "this collection"
            return "\(name) has no words yet."
        case .category(let name):
            return "No words in \(name) yet."
        }
    }

    private func reshuffle() {
        deck = deck_
        index = 0
        revealed = false
    }

    private func advance(known: Bool) {
        revealed = false
        if index + 1 < deck.count {
            index += 1
            speech.speak(deck[index].word)
        } else {
            reshuffle()
        }
    }

    private var filterSheet: some View {
        NavigationView {
            Form {
                Section {
                    Button {
                        filter = .all
                        showFilterSheet = false
                    } label: {
                        Label("All words", systemImage: "rectangle.stack")
                    }
                    Button {
                        filter = .weak
                        showFilterSheet = false
                    } label: {
                        Label("Weak words (\(library.weakCount))", systemImage: "exclamationmark.triangle")
                    }
                }
                if !library.collections.isEmpty {
                    Section("Collections") {
                        ForEach(library.collections) { c in
                            Button {
                                filter = .collection(c.id)
                                showFilterSheet = false
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text(c.name)
                                    Spacer()
                                    Text("\(c.wordIds.count)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if !library.categories.isEmpty {
                    Section("Categories") {
                        ForEach(library.categories, id: \.self) { cat in
                            Button {
                                filter = .category(cat)
                                showFilterSheet = false
                            } label: {
                                HStack {
                                    Image(systemName: "tag")
                                    Text(cat)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Study filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFilterSheet = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
