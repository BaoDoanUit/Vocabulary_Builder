//
//  LibraryView.swift
//  vocabulary_builder
//
//  Browse, search, filter, multi-select, swipe-delete, and create words.
//  Mirrors `LibraryPage` in the web app. See IOS_PORTING_GUIDE.md §7.4.
//

import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var api: APIClient
    @State private var search: String = ""
    @State private var categoryFilter: String? = nil
    @State private var selection: Set<UUID> = []
    @State private var isEditing: Bool = false
    @State private var showCreate: Bool = false
    @State private var page: Int = 0
    @State private var isLoadingList: Bool = false

    /// How many words one page holds. `GET /api/words` has no
    /// pagination — it returns the whole catalogue in one ~427 KB
    /// response (API.md §7) — so the list is paged on the device.
    static let pageSize: Int = 25

    private var categories: [String] { library.categories }

    private var filtered: [Vocabulary] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.sortedWords.filter { word in
            (categoryFilter == nil || word.category == categoryFilter) &&
            (q.isEmpty
             || word.word.localizedCaseInsensitiveContains(q)
             || word.definition.localizedCaseInsensitiveContains(q)
             || word.category.localizedCaseInsensitiveContains(q))
        }
    }

    /// How many pages the current filter needs.
    private var pageCount: Int {
        max(1, Int(ceil(Double(filtered.count) / Double(Self.pageSize))))
    }

    /// The page actually rendered, clamped so a shrinking list — a
    /// delete, a new filter — can never leave us on an empty page.
    private var currentPage: Int {
        min(max(page, 0), pageCount - 1)
    }

    /// The words on the current page.
    private var pageWords: [Vocabulary] {
        let start = currentPage * Self.pageSize
        let end = min(start + Self.pageSize, filtered.count)
        guard start < end else { return [] }
        return Array(filtered[start..<end])
    }

    /// "26–50 of 137"
    private var pageRange: String {
        guard !filtered.isEmpty else { return "0 of 0" }
        let start = currentPage * Self.pageSize + 1
        let end = min(start + Self.pageSize - 1, filtered.count)
        return "\(start)–\(end) of \(filtered.count)"
    }

    var body: some View {
        // The navigation stack now lives in `ContentView`, one per tab.
        // Declaring it here as well nested a second stack inside the
        // tab's, which left the pushed word detail short of the full
        // screen.
        VStack(spacing: 0) {
            if let err = library.lastError {
                ErrorBanner(message: err.errorDescription ?? "Error") {
                    Task { await library.reload(api: api) }
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            categoryStrip
            wordList
        }
        .background(Theme.pageBackground.ignoresSafeArea())
        .navigationTitle(isEditing ? "\(selection.count) selected" : "Library")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Search word, definition, category")
        .toolbar { toolbarContent }
        .fullScreenCover(isPresented: $showCreate) {
            // The editor is a screen of its own. A `.sheet` would draw
            // it as an inset card, and the `NavigationView` inside it
            // would nest a second stack inside the sheet's card.
            NavigationView {
                WordEditorView(mode: .create)
                    .hideTabBar()
            }
            .navigationViewStyle(.stack)
        }
        .refreshable {
            await library.reload(api: api)
        }
        .task {
            // The list is a snapshot unless it is refreshed when the tab
            // is opened. Skip the fetch when the store was updated
            // moments ago — `GET /api/words` is ~427 KB.
            guard !library.wordsAreFresh else { return }
            isLoadingList = true
            defer { isLoadingList = false }
            await library.reloadWords(api: api)
        }
        // A new search or filter always starts at the first page.
        .onChange(of: search) { _ in page = 0 }
        .onChange(of: categoryFilter) { _ in page = 0 }
        // Keep the stored page in step with a list that shrank.
        .onChange(of: filtered.count) { _ in page = currentPage }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(isEditing ? "Done" : "Select") {
                if isEditing { selection.removeAll() }
                isEditing.toggle()
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 8) {
                if isEditing {
                    Button {
                        if selection.count == filtered.count {
                            selection.removeAll()
                        } else {
                            selection = Set(filtered.map(\.id))
                        }
                    } label: {
                        Text(selection.count == filtered.count ? "Deselect all" : "Select all")
                            .font(.subheadline)
                    }
                    Button(role: .destructive) {
                        let ids = selection
                        Task {
                            for id in ids { await library.deleteWord(api: api, id: id) }
                            selection.removeAll()
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selection.isEmpty)
                } else {
                    Menu {
                        NavigationLink("Collections") { CollectionsView() }
                        NavigationLink("Generate with AI") { GenerateView() }
                        Button {
                            showCreate = true
                        } label: {
                            Label("New word", systemImage: "plus")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    label: "All",
                    selected: categoryFilter == nil
                ) { categoryFilter = nil }
                ForEach(categories, id: \.self) { cat in
                    CategoryChip(
                        label: cat,
                        selected: categoryFilter == cat
                    ) { categoryFilter = (categoryFilter == cat) ? nil : cat }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var wordList: some View {
        if isLoadingList && library.words.isEmpty {
            // First load of the tab: show the branded loader instead of
            // an empty list that fills in a moment later.
            BookLoader(message: "Loading your words…")
        } else if filtered.isEmpty {
            EmptyState(
                icon: "tray",
                title: library.words.isEmpty ? "No words yet" : "No matches",
                message: library.words.isEmpty
                    ? "Tap the + menu to add a word or generate with AI."
                    : "Try a different search or category filter."
            )
        } else {
            List {
                ForEach(pageWords) { word in
                    row(for: word)
                }
            }
            .listStyle(.plain)
            // The page controls sit below the list rather than inside
            // it, so they stay put while the words scroll.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if pageCount > 1 {
                    paginationBar
                }
            }
        }
    }

    /// The page controls — "26–50 of 137 · Page 2 of 6".
    private var paginationBar: some View {
        HStack(spacing: 12) {
            Button {
                page = currentPage - 1
            } label: {
                Label("Prev", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage == 0)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                Text(pageRange)
                    .font(.caption.monospacedDigit())
                Text("Page \(currentPage + 1) of \(pageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                page = currentPage + 1
            } label: {
                Label("Next", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage + 1 >= pageCount)
        }
        .font(.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.cardBackground)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private func row(for word: Vocabulary) -> some View {
        if isEditing {
            HStack {
                Image(systemName: selection.contains(word.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(word.id) ? Theme.primary : .secondary)
                    .font(.title3)
                rowContent(word)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selection.contains(word.id) { selection.remove(word.id) }
                else { selection.insert(word.id) }
            }
        } else {
            NavigationLink {
                // Pass the whole filtered list so the detail screen can
                // page through it with prev/next.
                WordDetailView(wordId: word.id, siblings: filtered)
            } label: {
                rowContent(word)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    Task { await library.deleteWord(api: api, id: word.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func rowContent(_ word: Vocabulary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.word).font(.headline)
                if let ipa = word.ipa, !ipa.isEmpty {
                    Text(ipa).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Text(word.definition)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if !word.category.isEmpty {
                    Chip(label: word.category, outlined: true)
                }
                if let pos = word.partOfSpeech.nonEmpty {
                    Chip(label: pos, tint: Theme.info, outlined: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryChip: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.primary : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
